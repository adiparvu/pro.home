import Foundation
import Observation
import Supabase

// MARK: - ChatRealtimeChannel (chat unification P3d)
//
// ONE realtime channel lifecycle for both chat engines. DirectMessageService
// and MessageService each carried a near-verbatim copy of the subscribe /
// rebuild machinery — the rejoin grace, the storm breaker, the stale-close
// kill watch, the diagnostics banner — so every hard-won realtime lesson
// (b1036, b1040, b1157, b1173, b1182, b1197) had to be fixed twice. This type owns
// the channel and the whole lifecycle; an engine contributes only what
// genuinely differs, through `Configuration`:
//   - its fully scoped topic string (the scope identity for idempotency),
//   - its handler registrations (postgres_changes + typing + dm_new/msg_new),
//   - its post-rebuild refetch (DM: merge-load; group: cursor loadNewer),
//   - a detach hook for engine state bound to the channel (the activity
//     indicator, pending debounced refetches).
// The broadcast round-trip self-test rides along for BOTH engines now — the
// group chat previously lacked it and reported "live" on a channel whose
// broadcast relay was dead (typing and the msg_new delivery ping both ride
// on broadcast, so a dead relay silences everything live at once).

@MainActor
@Observable
final class ChatRealtimeChannel {

    /// Everything one engine's conversation channel needs from that engine.
    /// Built fresh per call — the closures capture the engine's current scope
    /// (property/thread/group) exactly like the pre-extraction code captured
    /// its parameters.
    struct Configuration {
        /// Fully scoped topic ("dm:<property>" /
        /// "messages:<property>:<scope>"). Also the scope identity: two calls
        /// with the same topic address the same conversation channel.
        let topic: String
        /// Short engine tag for the flight recorder and debug logs
        /// ("dm" / "chat").
        let tag: String
        /// Registers the engine's postgres_changes and broadcast handlers on
        /// the fresh channel — callbacks must be registered before
        /// subscribing — and returns the retained handles. `onPostgresChange`
        /// returns a handle whose deinit removes the callback, so the handles
        /// must be held for the callbacks to keep firing; this type stores
        /// them and drops them at every teardown point.
        let register: @MainActor (RealtimeChannelV2) -> [RealtimeSubscription]
        /// Post-rebuild refetch, run after `ensureLiveDelivery` rebuilds a
        /// dead channel so nothing that arrived during the outage is missed.
        let refetch: @MainActor () async -> Void
        /// Called whenever the retained handles are dropped (same-topic
        /// teardown, failed subscribe, unsubscribe) so the engine detaches
        /// its own channel-bound state.
        let onDetach: @MainActor () -> Void
    }

    /// Live realtime diagnostic, surfaced by the chat views' warning banner.
    /// Exactly `"live"` when the channel is subscribed AND the broadcast
    /// round-trip is proven (banner hidden); a `"socket:… chan:…"` string when
    /// degraded; and `"FAIL: <error> · socket:…"` carrying the FULL, verbatim
    /// subscribe error when `subscribeWithError()` throws — the whole point
    /// being that the real error is finally visible instead of swallowed.
    private(set) var realtimeStatus: String = "…"

    /// The live channel. Engines read it to broadcast their delivery pings
    /// ("dm_new"/"msg_new") and to sync the activity indicator.
    private(set) var channel: RealtimeChannelV2?

    /// Topic the live channel is currently bound to, so repeated subscribe
    /// calls (re-entering the chat tab, opening a thread) are no-ops instead
    /// of stacking duplicate channels or tearing a live one down.
    private(set) var subscribedTopic: String?

    /// Broadcast round-trip self-test. Typing/recording AND live delivery
    /// (dm_new/msg_new) all ride on channel broadcast — postgres_changes can
    /// be withheld from the recipient by the table's SELECT policy by design.
    /// So if broadcast doesn't relay, EVERYTHING live breaks together. The
    /// channel is created with receiveOwnBroadcasts=on and, once subscribed,
    /// we broadcast a one-shot nonce to ourselves: if it echoes back the whole
    /// broadcast path is proven live; if it never returns, broadcast relay is
    /// the culprit. nil = not yet tested, true = echoed, false = timed out.
    private(set) var broadcastEcho: Bool?

    /// Retained handles for the engine's registered callbacks (see
    /// `Configuration.register`); cleared at every teardown point.
    @ObservationIgnored private var subs: [RealtimeSubscription] = []
    @ObservationIgnored private var selftestSub: RealtimeSubscription?
    @ObservationIgnored private var selftestNonce = ""
    @ObservationIgnored private var selftestTask: Task<Void, Never>?
    /// The engine's detach hook from the most recent subscribe — kept so a
    /// bare `unsubscribe()` can still let the engine release its state.
    @ObservationIgnored private var onDetachHook: (@MainActor () -> Void)?
    /// True while a subscribe is mid-flight (across the `subscribeWithError()`
    /// await). The open-thread `.task` AND the 3s delivery heartbeat both
    /// drive subscription; without this, one path's `unsubscribe()` cancels
    /// the other's in-flight subscribe with `CancellationError`, so the
    /// channel never reaches `.subscribed` and typing/live delivery die while
    /// the socket is up. The guard makes concurrent callers step aside
    /// instead of tearing the subscribe down.
    @ObservationIgnored private var isSubscribing = false
    /// Last heartbeat-driven channel rebuild — the 30s backoff's clock.
    @ObservationIgnored private var lastRebuildAt: Date?
    /// The post-confirm stale-close kill watch (b1182) — one per subscribe.
    @ObservationIgnored private var killWatchTask: Task<Void, Never>?
    /// The last configuration any caller subscribed with — the reconnect
    /// re-arm's memory of what SHOULD be live (b1197). Stamped on every
    /// subscribe intent, cleared only by an explicit `unsubscribe()`.
    @ObservationIgnored private var lastConfig: Configuration?
    /// Topics whose last join timed out or failed (b1197): that join may
    /// survive server-side as an orphan — queued on a dead socket, flushed
    /// by the reconnect AFTER our cleanup — so the NEXT subscribe for the
    /// topic must send an explicit leave on a live socket and start from a
    /// fresh channel object before rejoining.
    @ObservationIgnored private var dirtyTopics: Set<String> = []
    /// The socket-status observer behind the reconnect re-arm (b1197).
    @ObservationIgnored private var reconnectTriggerTask: Task<Void, Never>?
    /// The recovery run a reconnect spawns; a fresh reconnect supersedes it.
    @ObservationIgnored private var reconnectRecoveryTask: Task<Void, Never>?

    // MARK: - Subscribe

    func subscribe(_ config: Configuration) async {
        // UNSTRUCTURED on purpose (field log 11:49:33 → chan:none on a
        // connected socket): the open-thread `.task` that calls this dies
        // with the view (or an id change), and a cancellation landing
        // BETWEEN the teardown and the join tore the old channel down and
        // never joined the new one — the CancellationError catch read it as
        // "superseded", but no successor existed, so live delivery sat dead
        // for the whole 30s rebuild backoff. An unstructured task does not
        // inherit the caller's cancellation: teardown + join complete as
        // one atomic unit no matter what happens to the view.
        let work = Task { @MainActor [weak self] in
            await self?.performSubscribe(config)
        }
        await work.value
    }

    private func performSubscribe(_ config: Configuration) async {
        // Reconnect re-arm memory (b1197): from the first subscribe intent
        // on, this class SHOULD be live on this topic. The socket observer
        // (armReconnectTrigger) uses it to re-kick the rebuild after a
        // reconnect — before, NOTHING did: ensureLiveDelivery only ran on
        // foreground/appear, so the 16:25 outage left the banner parked on
        // "chan:none" for good. Cleared only by an explicit unsubscribe().
        lastConfig = config
        armReconnectTrigger()
        // Idempotent ONLY for the same conversation scope (the topic carries
        // the full scope) on a genuinely live channel. Two real-world failures
        // hid behind an older `!= nil` check: a community thread opened after
        // the main chat kept coasting on the MAIN topic (same property,
        // different group — no messages, no typing), and a channel whose
        // initial subscribe failed at launch was kept as if live, silencing
        // the whole session.
        // Live for this scope → keep it. Trust the channel's own status
        // (supabase-swift auto-reconnects the socket under it). `.subscribing`
        // counts as alive too: after a reconnect the SDK's rejoinChannels()
        // resets and re-joins this very channel, and tearing it down mid-join
        // raced that rejoin into a leave/join churn loop (the Build 1036 lag).
        if let ch = channel, subscribedTopic == config.topic,
           ch.status == .subscribed || ch.status == .subscribing { return }
        // REJOIN GRACE at the single choke point (field log 23:21:44 → 1006):
        // right after a socket reconnect the SDK's rejoinChannels() owns every
        // registered channel, and a channel's state flickers through
        // .unsubscribed before the rejoin's own subscribe starts. The VIEW
        // paths (.task on appear, scenePhase-active) land exactly in that
        // flicker — the heartbeat already had this grace, they didn't — pass
        // the liveness check above, tear the channel down mid-rejoin and put
        // a SECOND join for the topic on the socket; the server answers each
        // new join by closing the previous one until it drops the whole
        // socket (code 1006). Holding a channel for this scope moments after
        // a reconnect means the rejoin owns it: stand down and let it land —
        // the 3s heartbeat retries after the grace if it genuinely died.
        // The grace holds even with NO channel object (b1182 field log): our
        // previous join may live on server-side as an orphan whose stale
        // phx_close — topic-matched, join_ref unchecked by SDK 2.52 — kills
        // any join added in the window. Cold launches have no disconnect on
        // record, so the first-ever subscribe stays instant; a scope SWITCH
        // proceeds too (a fresh topic no orphan close can touch).
        if RealtimeFlightRecorder.shared.inRejoinGrace(seconds: 10),
           channel == nil || subscribedTopic == config.topic { return }
        // Only ONE subscribe in flight. The open-thread `.task` and the 3s
        // heartbeat both call this; a second entrant must step aside rather
        // than run `unsubscribe()`, which cancels the first's
        // `subscribeWithError()` with CancellationError — the exact FAIL the
        // diagnostic surfaced.
        guard !isSubscribing else { return }
        isSubscribing = true
        defer { isSubscribing = false }
        onDetachHook = config.onDetach
        // NEVER burn the join timebox on a dead socket (b1197 field log:
        // socket disc 16:25:18 → conn 16:25:37, a 19s outage against a 15s
        // timebox): subscribeWithError() QUEUED its phx_join on the down
        // socket while the clock ran out on pure dead air. The timeout
        // cleanup then tore the client channel down — its phx_leave equally
        // undeliverable — and the reconnect flushed the queued join anyway:
        // "Received event phx_reply" landed right after "subscribing →
        // unsubscribed", a server confirm for a channel no client owned.
        // That orphan's stale phx_close then murdered the topic's next
        // confirmed join (the b1173 signature — the presence channel's
        // subscribed → phx_close loop in the same log). The timebox exists
        // to bound a hung JOIN, not to race a reconnect: wait (bounded) for
        // the socket first, and only then start the join clock. The
        // teardown below waits too — a leave needs a live socket as much as
        // a join does. If the socket never comes up, fail exactly as today.
        await awaitSocketConnected(config)
        // A wait cut short by cancellation means a newer subscribe or an
        // explicit teardown superseded this one — proceeding would run the
        // teardown/scrub/join sequence on a cancelled task, where every
        // await returns instantly and the SDK calls misfire.
        if Task.isCancelled { return }
        if let old = channel, !old.topic.hasSuffix(config.topic) {
            await unsubscribe()                 // genuine scope/property switch
            lastConfig = config                 // the switch's intent survives it
        } else if let old = channel {
            // SAME topic: never discard the object — a fresh object
            // double-joins the topic, and the server's close of the previous
            // join (stale join_ref, unchecked by SDK 2.52.0) kills the new,
            // just-confirmed subscription (b1173 field log). Drop our
            // callback handles, then drive THIS object down: unsubscribe()
            // sends phx_leave even mid-join and awaits the server's
            // phx_close, so no orphan join survives server-side.
            detachHandles()
            subscribedTopic = nil
            channel = nil
            await old.unsubscribe()
        }
        // DIRTY-TOPIC SCRUB (b1197): the topic's last join timed out or
        // failed, so an orphaned server-side join may be waiting to kill
        // the one below with its stale phx_close (b1173) — the failure
        // cleanup's own leave was undeliverable on the dead socket. Now
        // that the socket is up, push an explicit leave for the topic
        // through a throwaway registration and deregister it, so the join
        // below starts from a clean server slate on a FRESH channel object.
        if dirtyTopics.contains(config.topic), realtimeAnon.status == .connected {
            dirtyTopics.remove(config.topic)
            RealtimeFlightRecorder.shared.note(
                "\(config.tag): scrubbing orphaned join before rejoin")
            let scrub = realtimeAnon.channel(config.topic) {
                $0.broadcast.receiveOwnBroadcasts = true
            }
            // Real leave from every state (b1173) — timeboxed so a mute
            // server cannot latch `isSubscribing` through the scrub.
            try? await withRealtimeTimeout(seconds: 5) { await scrub.unsubscribe() }
            await realtimeAnon.removeChannel(scrub)
        }
        // Channel auth rides the client's accessToken closure (see
        // SupabaseClient): the user's session JWT, so RLS-scoped
        // postgres_changes actually deliver member rows.
        // channel(_:) returns the already-registered instance for a live
        // topic — the reuse funnels the app and the SDK's rejoinChannels()
        // into ONE join per topic.
        // receiveOwnBroadcasts lets the post-subscribe self-test hear its own
        // ping. The engines' typing/dm_new/msg_new handlers already ignore
        // their own signals (name != myName, from != my id), so echoing our
        // own broadcasts back is harmless to them and gives us a
        // zero-second-device liveness probe. (On reuse the options closure is
        // ignored by the SDK — the registered instance already carries
        // receiveOwnBroadcasts = true.)
        let ch = realtimeAnon.channel(config.topic) {
            $0.broadcast.receiveOwnBroadcasts = true
        }
        // The engine's handlers go on first (callbacks must be registered
        // before subscribing); the returned handles are retained here.
        subs = config.register(ch)
        // The broadcast liveness probe's receiver: our own ping coming back.
        selftestSub = ch.onBroadcast(event: "selftest") { [weak self] json in
            guard let nonce = broadcastString(json, "nonce") else { return }
            Task { @MainActor [weak self] in
                guard let self, nonce == self.selftestNonce else { return }
                self.selftestTask?.cancel()
                self.broadcastEcho = true
                self.refreshStatus()
            }
        }
        do {
            // Timeboxed: a subscribe awaiting a never-recovering socket would
            // otherwise latch `isSubscribing` forever, freezing both the 3s
            // heartbeat's recovery and the banner. (connectOnSubscribe still
            // auto-connects the socket; the watchdog owns long-term revival.)
            try await withRealtimeTimeout(seconds: 15) {
                try await ch.subscribeWithError()
            }
        } catch {
            // A failed subscribe must leave NO trace: keeping the dead channel
            // made the idempotent guard treat the whole session as live.
            // Surface the FULL error to the diagnostic banner after cleanup.
            detachHandles()
            // unsubscribe() FIRST: from .subscribing it cancels the join AND
            // sends phx_leave; removeChannel alone sends no leave from a
            // non-.subscribed state, and a join confirming after the 15s
            // timebox would live on as the server orphan that closes the
            // topic's next join (b1173).
            await ch.unsubscribe()
            await realtimeAnon.removeChannel(ch)
            // A cancellation is NOT a real failure: it means a newer subscribe
            // or a socket reset-for-reconnect superseded this attempt. Don't
            // brand the session FAILED — leave the status for the heartbeat to
            // re-establish. Only genuine errors surface as FAIL.
            if error is CancellationError {
                debugLog("\(config.tag) realtime subscribe superseded (cancelled)")
                return
            }
            // Remember the wound (b1197): this join may have been QUEUED on
            // a down socket and outlive its own cleanup — the 16:25 log
            // shows its phx_reply landing right after "subscribing →
            // unsubscribed", and the leave above is just as undeliverable
            // then. The NEXT subscribe for this topic scrubs the orphan
            // with an explicit leave on a live socket before rejoining.
            dirtyTopics.insert(config.topic)
            debugLog("\(config.tag) realtime subscribe failed:", error)
            realtimeStatus = "b\(appBuildTag) FAIL: \(error) · socket:\(socketStatusText) · tok:\(tokenHint)"
            return
        }
        channel = ch
        subscribedTopic = config.topic
        runBroadcastSelfTest(on: ch)
        refreshStatus()
        armStaleCloseKillWatch(on: ch, config: config)
    }

    // MARK: - Socket wait (b1197)

    /// Bounded wait for the realtime socket BEFORE the join timebox starts.
    /// b1197 field log: the socket dropped at 16:25:18 and came back at
    /// 16:25:37 — 19 seconds, longer than the 15s timebox — so a subscribe
    /// entered during the outage always died on the clock, never on the
    /// join. Waiting here means the 15s budget times a real join handshake
    /// again; the wait itself never touches the socket (the SDK's
    /// auto-reconnect and the watchdog own revival), and it stands down in
    /// the background (Build 1036's 0x8BADF00D law). If the socket stays
    /// down past the deadline, fall through and fail exactly as before.
    /// The wait is its own banner state ("chan:join-wait") so a screenshot
    /// pins WHERE a stuck subscribe sits instead of lying "unsubscribed".
    private func awaitSocketConnected(_ config: Configuration) async {
        guard realtimeAnon.status != .connected else { return }
        RealtimeFlightRecorder.shared.note(
            "\(config.tag): join-wait — socket \(socketStatusText), holding the join timebox")
        // Self-sufficient: on a chat-first cold entry NOTHING else may ever
        // connect the socket — connectOnSubscribe fires from the very join
        // this wait is deliberately holding back. Kick the connect once;
        // the SDK ignores it when already connecting.
        if realtimeAnon.status == .disconnected {
            Task { await realtimeAnon.connect() }
        }
        // Banner set ONCE, not per tick — the b1198 family-wide freeze was
        // this loop cancelled mid-wait: `try?` swallowed Task.sleep's
        // CancellationError, every 500ms tick collapsed to ~0ms, and the
        // per-tick observable status write became a 20-second invalidation
        // storm on the main actor. A cancelled wait must EXIT: a newer
        // subscribe or an explicit teardown owns the topic now.
        realtimeStatus = "b\(appBuildTag) socket:\(socketStatusText) chan:join-wait · \(RealtimeFlightRecorder.shared.tail)"
        let deadline = Date().addingTimeInterval(20)
        while realtimeAnon.status != .connected, Date() < deadline,
              !AppLifecycle.isBackgrounded {
            do { try await Task.sleep(nanoseconds: 500_000_000) }
            catch { return }
        }
        RealtimeFlightRecorder.shared.note(
            "\(config.tag): join-wait over — socket \(socketStatusText)")
    }

    // MARK: - Teardown

    /// Drops every retained handle bound to the current channel object, resets
    /// the self-test and lets the engine detach its own channel-bound state.
    private func detachHandles() {
        subs.removeAll()
        selftestSub = nil
        selftestTask?.cancel()
        selftestTask = nil
        broadcastEcho = nil
        onDetachHook?()
    }

    func unsubscribe() async {
        // Explicit teardown = this class should NOT be live anymore: drop
        // the reconnect re-arm's memory (b1197) so a later reconnect can't
        // resurrect a conversation the user closed. subscribe() re-stamps.
        lastConfig = nil
        reconnectRecoveryTask?.cancel()
        reconnectRecoveryTask = nil
        killWatchTask?.cancel()
        killWatchTask = nil
        detachHandles()
        subscribedTopic = nil
        if let ch = channel {
            // Real leave from EVERY state (removeChannel skips the leave when
            // the channel isn't .subscribed) — otherwise the server keeps an
            // orphan join whose stale phx_close kills the topic's next
            // confirmed join (b1173).
            await ch.unsubscribe()
            await realtimeAnon.removeChannel(ch)
            channel = nil
        }
    }

    // MARK: - Stale-close kill watch

    /// Stale-close kill detector (b1182 field log): a join the server just
    /// CONFIRMED that flips to `.unsubscribed` within seconds — without any
    /// local teardown — was murdered by the phx_close of an EARLIER join on
    /// this topic (join_ref unchecked in SDK 2.52). Rejoining the same topic
    /// only arms the next close, so the chain never converges on its own.
    /// Each detected kill counts as a storm strike; on the breaker's
    /// threshold the socket bounces (shedding every server-side orphan) and
    /// ONE clean resubscribe follows — convergence in two cycles instead of
    /// minutes of heartbeat whack-a-mole.
    private func armStaleCloseKillWatch(on ch: RealtimeChannelV2,
                                        config: Configuration) {
        killWatchTask?.cancel()
        killWatchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, !Task.isCancelled else { return }
            // Still OUR current channel, same scope, not torn down locally —
            // yet unsubscribed on a connected socket: the kill signature.
            guard self.channel === ch,
                  self.subscribedTopic == config.topic,
                  ch.status == .unsubscribed,
                  realtimeAnon.status == .connected,
                  !AppLifecycle.isBackgrounded else { return }
            RealtimeFlightRecorder.shared.note(
                "\(config.tag): confirmed join killed by stale close")
            guard RealtimeStormBreaker.shouldBounceSocket() else { return }
            // Recovery in its OWN task: unsubscribe() cancels this very watch
            // task, and a self-cancelled task must not carry the bounce. The
            // immediate resubscribe may stand down behind the fresh rejoin
            // grace — the heartbeat completes it right after.
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.unsubscribe()
                await RealtimeStormBreaker.bounceSocket(
                    reason: "\(config.tag) stale-close kill")
                await self.subscribe(config)
            }
        }
    }

    // MARK: - Broadcast self-test

    /// Sends a nonce to ourselves over the just-subscribed channel and waits
    /// for the echo. Success proves socket + channel + broadcast relay are all
    /// live; timing out fingers broadcast as the reason typing/recording and
    /// instant delivery are dead. Result is surfaced in `realtimeStatus`.
    private func runBroadcastSelfTest(on ch: RealtimeChannelV2) {
        selftestTask?.cancel()
        broadcastEcho = nil
        let nonce = UUID().uuidString
        selftestNonce = nonce
        selftestTask = Task { [weak self] in
            await ch.broadcast(event: "selftest", message: ["nonce": .string(nonce)])
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, !AppLifecycle.isBackgrounded else { return }
            await MainActor.run { [weak self] in
                guard let self, self.broadcastEcho == nil else { return }
                self.broadcastEcho = false          // no echo in 4s → relay dead
                self.refreshStatus()
            }
        }
    }

    // MARK: - Diagnostics

    /// Compact, non-secret description of the realtime auth token: whether a
    /// session JWT is present and how long until it expires (negative =
    /// already expired). Lets the diagnostic banner reveal a token/refresh
    /// fault without leaking the token itself.
    private var tokenHint: String {
        guard let s = supabase.auth.currentSession else { return "none" }
        let secs = Int(s.expiresAt - Date().timeIntervalSince1970)
        return "jwt(exp \(secs)s)"
    }

    /// Short lowercase description of the realtime WebSocket connection.
    private var socketStatusText: String {
        switch realtimeAnon.status {
        case .connected: "connected"
        case .connecting: "connecting"
        case .disconnected: "disconnected"
        @unknown default: "unknown"
        }
    }

    /// Short description of a channel's subscription state (`nil` = no channel).
    private func channelStatusText(_ status: RealtimeChannelStatus?) -> String {
        switch status {
        case .subscribed: "subscribed"
        case .subscribing: "subscribing"
        case .unsubscribing: "unsubscribing"
        case .unsubscribed: "unsubscribed"
        case nil: "none"
        @unknown default: "unknown"
        }
    }

    /// Healthy = the channel is subscribed. The channel's own status is the
    /// reliable signal: supabase-swift keeps it `.subscribed` across transient
    /// socket blips and auto-reconnects underneath, flipping it off
    /// `.subscribed` only when the subscription is genuinely gone. An earlier
    /// build ALSO required `realtimeV2.status == .connected`, but that
    /// socket-status read can lag `.connecting` right after a subscribe —
    /// turning the 3s heartbeat into a teardown/rebuild loop that silences the
    /// very channel it guards. Broadcast liveness is proven separately by the
    /// round-trip self-test.
    var realtimeHealthy: Bool {
        channel?.status == .subscribed
    }

    /// Recomputes `realtimeStatus` from current socket + channel health,
    /// folding in the broadcast round-trip probe. "live" only once broadcast
    /// is proven — a subscribed channel whose broadcast never echoes is the
    /// exact broken state (typing/delivery ride on broadcast), so it must NOT
    /// read as live.
    private func refreshStatus() {
        guard realtimeHealthy else {
            // Carry the socket's recent transition history so a single
            // screenshot shows how it died, not just where it sits now.
            realtimeStatus = "b\(appBuildTag) socket:\(socketStatusText) chan:\(channelStatusText(channel?.status)) · \(RealtimeFlightRecorder.shared.tail)"
            return
        }
        switch broadcastEcho {
        case .some(true):  realtimeStatus = "live"
        case .some(false): realtimeStatus = "b\(appBuildTag) socket:\(socketStatusText) chan:subscribed bcast:DEAD"
        case .none:        realtimeStatus = "b\(appBuildTag) socket:\(socketStatusText) chan:subscribed bcast:testing"
        }
    }

    // MARK: - Reconnect re-arm (b1197)

    /// Socket-status observer: on every reconnect (… → .connected) it
    /// re-kicks the rebuild when this class believes it should be live
    /// (`lastConfig` is stamped) but the channel isn't subscribed. b1197's
    /// second lesion: after the outage killed the join, NOTHING re-tried —
    /// ensureLiveDelivery only ran on foreground/appear — so "chan:none"
    /// sat on a healthy socket indefinitely. This is a TRIGGER, not a new
    /// lifecycle: the recovery run funnels into ensureLiveDelivery, so
    /// every existing guard (background quiet, rejoin grace, 30s backoff,
    /// storm breaker) still decides — a flapping network cannot storm
    /// joins through it, it can only ask the usual gatekeepers again.
    private func armReconnectTrigger() {
        guard reconnectTriggerTask == nil else { return }
        reconnectTriggerTask = Task { @MainActor [weak self] in
            var previous = realtimeAnon.status
            for await status in realtimeAnon.statusChange {
                guard let self else { return }
                let reconnected = previous != .connected && status == .connected
                previous = status
                guard reconnected else { continue }
                self.reconnectRecoveryTask?.cancel()
                self.reconnectRecoveryTask = Task { @MainActor [weak self] in
                    await self?.reconnectRecovery()
                }
            }
        }
    }

    /// One recovery run after a reconnect. Sleeps past the rejoin grace
    /// first (the SDK's rejoinChannels() owns the first ~10s — rebuilding
    /// inside it is the b1040 double-join), then lets ensureLiveDelivery
    /// decide with the last stamped configuration. Two passes, one backoff
    /// window apart: the first may legitimately stand down behind the 30s
    /// rebuild backoff, and without the second the recovery would starve
    /// against the very guard that keeps it polite.
    private func reconnectRecovery() async {
        try? await Task.sleep(nanoseconds: 11_000_000_000)
        for _ in 0..<2 {
            guard !Task.isCancelled, let config = lastConfig,
                  realtimeAnon.status == .connected,
                  !AppLifecycle.isBackgrounded else { return }
            if subscribedTopic == config.topic, realtimeHealthy { return }
            RealtimeFlightRecorder.shared.note(
                "\(config.tag): reconnect re-arm chan=\(channelStatusText(channel?.status))")
            await ensureLiveDelivery(config)
            try? await Task.sleep(nanoseconds: 31_000_000_000)
        }
    }

    // MARK: - Delivery safety net

    /// Delivery safety net for an OPEN conversation: verifies the channel is
    /// genuinely subscribed to THIS scope and, when it isn't (failed initial
    /// subscribe, dropped socket), rebuilds it and refetches — so a thread
    /// the user is looking at can never sit silent. Free when healthy.
    func ensureLiveDelivery(_ config: Configuration) async {
        // Quiet in the background — no rebuilds, no status churn: backgrounded
        // scene updates are what the 0x8BADF00D watchdog kills (Build 1036).
        guard !AppLifecycle.isBackgrounded else { return }
        // A subscribe is already in flight (the open-thread `.task`): DO NOT
        // interfere. Tearing it down here is precisely what cancelled it with
        // CancellationError and kept the channel from ever going live.
        guard !isSubscribing else { return }
        // Healthy = the channel is subscribed to THIS scope. Refresh the
        // diagnostic on the healthy path so the banner reflects the socket text.
        if subscribedTopic == config.topic, realtimeHealthy {
            // A channel that outlived a full backoff window since its last
            // rebuild proves the join/close storm (if any) has passed.
            if lastRebuildAt.map({ Date().timeIntervalSince($0) > 45 }) ?? true {
                RealtimeStormBreaker.noteStable()
            }
            refreshStatus()
            return
        }
        // Surface the CURRENT state first (the banner must never sit on a
        // stale snapshot).
        refreshStatus()
        // Never fight the SDK for this channel:
        //  - while the socket is down/reconnecting, the watchdog + the SDK's
        //    auto-reconnect own recovery, and rejoinChannels() re-subscribes
        //    this very channel — tearing it down here raced that rejoin into
        //    a leave/join churn loop (the Build 1036 group-chat lag);
        //  - while the same-scope channel is mid-join/mid-leave, let it finish
        //    (the 15s subscribe timebox bounds a hung join).
        guard realtimeAnon.status == .connected else { return }
        if let st = channel?.status, st == .subscribing || st == .unsubscribing,
           subscribedTopic == config.topic { return }
        // Rejoin grace (b1040): for ~10s after a reconnect the SDK's
        // rejoinChannels() is re-joining every registered channel. A rebuild
        // in that window puts a SECOND join for this topic on the socket and
        // the server answers each new join by closing the previous one —
        // every close re-armed the next rebuild (the 3-4s subscribe→phx_close
        // loop in the field log). The rejoin lands on its own; stand down.
        if let connectedAt = RealtimeFlightRecorder.shared.lastConnectedAt,
           Date().timeIntervalSince(connectedAt) < 10 { return }
        // Backoff: one rebuild per 30s. If the server keeps closing a
        // freshly confirmed join, retrying 3s later never helps — it reads
        // as join/leave abuse server-side and feeds the 1006 socket drops.
        if let last = lastRebuildAt, Date().timeIntervalSince(last) < 30 { return }
        lastRebuildAt = Date()
        // Reaching here with an .unsubscribed channel on a connected socket
        // means the SERVER closed a confirmed join. Once is a blip; twice
        // without an intervening stretch of health is the stale-phx_close
        // storm (see RealtimeStormBreaker) — another plain rejoin would only
        // manufacture the next close. Bounce the socket to shed the orphaned
        // server-side joins, then rebuild on the clean connection (our topic
        // was deregistered by the close, so the SDK's rejoin skips it and
        // subscribe below owns it without competition).
        // The gate covers chan=none too (b1157 field log): a bounce's own
        // unsubscribe nils the channel, and a narrower gate then looped
        // "rebuild chan=none" forever without re-engaging the breaker.
        if channel == nil || channel?.status == .unsubscribed,
           RealtimeStormBreaker.shouldBounceSocket() {
            await unsubscribe()
            await RealtimeStormBreaker.bounceSocket(
                reason: "\(config.tag) join/close loop")
        }
        // Genuinely dead on a healthy socket: rebuild. subscribe owns its own
        // teardown (behind the isSubscribing guard), so don't pre-unsubscribe
        // here — that reopened the very cancellation race.
        RealtimeFlightRecorder.shared.note(
            "\(config.tag): rebuild chan=\(channelStatusText(channel?.status)) sock=\(socketStatusText)")
        await subscribe(config)
        await config.refetch()
    }
}
