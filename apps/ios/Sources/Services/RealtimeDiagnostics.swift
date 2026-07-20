import Foundation
import Supabase

// MARK: - Realtime flight recorder + watchdog
//
// The app runs ALL realtime on one standalone client (`realtimeAnon`). Two
// structural gaps kept its failures both invisible and unrecoverable:
//
//  1. supabase-swift's auto-reconnect is ONE-SHOT: a dropped socket schedules a
//     single retry after `reconnectDelay`; if that one attempt throws (network
//     mid-transition on a phone), the client parks in `.disconnected` forever —
//     nothing in the SDK ever tries again. Only an explicit `connect()` revives
//     it. The watchdog below is that explicit hand.
//
//  2. Nothing recorded WHY a socket died — the banner showed a point-in-time
//     status with no history, so every field failure was undiagnosable. The
//     recorder below keeps the last N connection events (SDK log lines carry
//     close codes + reconnect decisions) and the status transitions; the
//     banner's copy action exports the whole log.

/// Thread-safe ring buffer of realtime connection events. Doubles as the
/// `SupabaseLogger` plugged into `realtimeAnon`, so SDK-internal close codes
/// and reconnect decisions land in the same timeline as app-side events.
final class RealtimeFlightRecorder: SupabaseLogger, @unchecked Sendable {
    static let shared = RealtimeFlightRecorder()

    private let lock = NSLock()
    private var lines: [String] = []
    private var transitions: [String] = []
    private var watchdogStarted = false
    private var _lastConnectedAt: Date?
    private var _lastDisconnectAt: Date?
    private static let cap = 80

    /// When the socket last reached `.connected`. After a reconnect the
    /// SDK's `rejoinChannels()` owns every registered channel for a few
    /// seconds — an app-side rebuild in that window puts TWO joins for the
    /// same topic on one socket and the server answers each new join by
    /// closing the previous one (the b1040 3-4s subscribe→phx_close loop).
    /// The services' heartbeats read this to stand down during the rejoin.
    var lastConnectedAt: Date? {
        lock.lock(); defer { lock.unlock() }
        return _lastConnectedAt
    }

    /// True within `seconds` of a RE-connect — a `.connected` that followed
    /// a real disconnect. In that window the previous topics may survive
    /// server-side as orphans whose stale phx_close (topic-matched, join_ref
    /// unchecked by SDK 2.52) kills any join the app adds (b1182 field log).
    /// A cold launch has no disconnect on record, so first subscribes stay
    /// instant.
    func inRejoinGrace(seconds: TimeInterval) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard _lastDisconnectAt != nil, let connected = _lastConnectedAt else { return false }
        return Date().timeIntervalSince(connected) < seconds
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    // MARK: SupabaseLogger

    /// Keeps only the connection + channel-lifecycle narrative:
    /// connect/disconnect/reconnect/close, subscribe/unsubscribe (join/leave)
    /// and anything at warning+ severity. Without the subscribe lines the log
    /// showed every death but no rebirth — half the story. Message-frame debug
    /// spam is still dropped so the buffer stays a story, not a firehose.
    func log(message: SupabaseLogMessage) {
        let text = message.message
        let relevant = message.level == .warning || message.level == .error
            || text.localizedCaseInsensitiveContains("connect")
            || text.localizedCaseInsensitiveContains("close")
            || text.localizedCaseInsensitiveContains("error")
            || text.localizedCaseInsensitiveContains("subscrib")
            || text.localizedCaseInsensitiveContains("channel")
        guard relevant else { return }
        append("[\(message.level)] \(text)")
    }

    /// App-side events (watchdog kicks, subscribe outcomes) join the timeline.
    func note(_ line: String) { append(line) }

    private func append(_ line: String) {
        let stamped = "\(Self.clock.string(from: Date())) \(line)"
        lock.lock(); defer { lock.unlock() }
        lines.append(stamped)
        if lines.count > Self.cap { lines.removeFirst(lines.count - Self.cap) }
    }

    private func recordTransition(_ status: RealtimeClientStatus) {
        let name = switch status {
        case .connected: "conn"
        case .connecting: "conn…"
        case .disconnected: "disc"
        @unknown default: "?"
        }
        let stamped = "\(name)@\(Self.clock.string(from: Date()))"
        lock.lock(); defer { lock.unlock() }
        if status == .connected { _lastConnectedAt = Date() }
        if status == .disconnected { _lastDisconnectAt = Date() }
        transitions.append(stamped)
        if transitions.count > Self.cap { transitions.removeFirst(transitions.count - Self.cap) }
    }

    // MARK: Banner exports

    /// The last few status transitions, compact — appended to the diagnostic
    /// banner so a screenshot alone shows the socket's recent life.
    var tail: String {
        lock.lock(); defer { lock.unlock() }
        return transitions.suffix(3).joined(separator: "→")
    }

    /// The full recorded timeline (transitions + SDK/app events) for the
    /// banner's copy action.
    var fullLog: String {
        lock.lock(); defer { lock.unlock() }
        let t = "TRANSITIONS: " + transitions.joined(separator: " → ")
        return ([t] + lines).joined(separator: "\n")
    }

    // MARK: Watchdog

    /// Owns the socket's life from app start: connects once up front (instead
    /// of racing ~8 services' connect-on-subscribe), records every status
    /// transition, and — the actual fix — revives the client whenever the
    /// SDK's one-shot reconnect leaves it parked in `.disconnected`.
    func startWatchdog() {
        lock.lock()
        guard !watchdogStarted else { lock.unlock(); return }
        watchdogStarted = true
        lock.unlock()

        // Status observer: the transition history the banner shows.
        Task.detached(priority: .utility) { [weak self] in
            for await status in realtimeAnon.statusChange {
                self?.recordTransition(status)
            }
        }
        // Keeper: explicit connect now, then revive on every parked-dead poll.
        // NEVER in the background: the SDK's RealtimeLifecycleManager owns
        // backgrounding (it deliberately lets the socket rest), and reviving
        // it there produced connect/teardown churn while backgrounded — fuel
        // for the 0x8BADF00D scene-update watchdog kill (Build 1036).
        Task.detached(priority: .utility) { [weak self] in
            await realtimeAnon.connect()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                let backgrounded = await AppLifecycle.isBackgrounded
                if backgrounded { continue }
                if realtimeAnon.status == .disconnected {
                    self?.note("watchdog: socket parked disconnected — reviving")
                    await realtimeAnon.connect()
                }
            }
        }
    }
}

// MARK: - Storm breaker (orphaned server-side joins)

/// Escalation for the join/close storm a stale `phx_close` sustains.
///
/// Phoenix closes the PREVIOUS join when a new join for the same topic
/// arrives on the same socket, and that close carries the OLD join_ref.
/// realtime-js drops lifecycle events whose ref doesn't match the current
/// join; supabase-swift (2.52.0) does no ref check — the stale close tears
/// down the just-confirmed subscription and deregisters the channel. From
/// there every rebuild sends a fresh join with NO leave for the orphaned
/// previous one (`removeChannel` only sends leave from `.subscribed`, and
/// the stale close already flipped the state), so each rebuild manufactures
/// the NEXT stale close: confirmed → closed, forever — the b1066 group log
/// (23:24:18/19/22), with postgres_changes for the newest, orphaned join
/// still flowing while the banner read `chan:unsubscribed`.
///
/// No app-side join sequence converges out of that (the close is always one
/// join behind), but a socket bounce does: disconnecting kills EVERY
/// server-side channel process — orphans included — and the SDK's reconnect
/// + rejoinChannels() then joins each registered channel exactly once,
/// cleanly. The chat engines report every server-closed-channel rebuild
/// here; the second one without an intervening stretch of health escalates
/// to one bounce, rate-limited so a genuinely sick server can't turn the
/// cure into its own storm.
@MainActor
enum RealtimeStormBreaker {
    private static var closeRebuilds = 0
    private static var lastBounceAt: Date?

    /// The caller is rebuilding a channel the server closed while the socket
    /// stayed connected. Returns true when the pattern has repeated and the
    /// caller should bounce the socket instead of feeding another doomed join.
    static func shouldBounceSocket() -> Bool {
        closeRebuilds += 1
        guard closeRebuilds >= 2 else { return false }
        if let last = lastBounceAt, Date().timeIntervalSince(last) < 120 { return false }
        closeRebuilds = 0
        lastBounceAt = Date()
        return true
    }

    /// A rebuilt channel survived a full backoff window — the storm is over.
    static func noteStable() { closeRebuilds = 0 }

    /// Drops the socket (shedding every orphaned join server-side) and
    /// reconnects; registered channels rejoin through the SDK's own path.
    /// The caller re-subscribes its own (deregistered) topic afterwards.
    static func bounceSocket(reason: String) async {
        RealtimeFlightRecorder.shared.note("storm-breaker: socket bounce — \(reason)")
        realtimeAnon.disconnect()
        await realtimeAnon.connect()
    }
}

// MARK: - Subscribe timebox

struct RealtimeSubscribeTimeout: Error, CustomStringConvertible {
    let seconds: Int
    var description: String { "subscribe timed out after \(seconds)s" }
}

/// Races an async operation against a deadline. A `subscribeWithError()` that
/// hangs awaiting a never-recovering socket would otherwise latch the services'
/// `isSubscribing` guard forever, freezing both recovery and the banner.
func withRealtimeTimeout<T: Sendable>(
    seconds: Int,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            throw RealtimeSubscribeTimeout(seconds: seconds)
        }
        // First finisher wins; cancel the loser. If the deadline wins, the
        // subscribe task is cancelled (its CancellationError is discarded).
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
