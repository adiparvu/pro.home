import Foundation
import Supabase

// MARK: - One receipt/reaction/poll side channel (chat unification, P6b)
//
// MessageService carried FOUR near-verbatim copies of the same ~65 lines:
// subscribe to one side table's INSERTs for one (property, group) scope,
// debounce a refetch, tear down with a real leave. Every realtime lesson
// paid for on the main channel (b1173 leave-from-every-state, the 15s
// timebox, scope-change teardown, liveness idempotency) had to be patched
// four times — and the b1197/b1198 socket lessons never made it here at
// all. One type now owns the lifecycle; the engines own only WHAT to
// refetch.
@MainActor
final class ChatSideChannel {
    private let table: String
    private let tag: String
    private var channel: RealtimeChannelV2?
    private var subs: [RealtimeSubscription] = []
    private var reloadTask: Task<Void, Never>?

    init(table: String, tag: String) {
        self.table = table
        self.tag = tag
    }

    /// Subscribes for one (property, group) scope; `reload` is the debounced
    /// refetch fired on every INSERT the filter lets through.
    ///
    /// The topic carries the group scope: the main chat and a community
    /// group used to claim the SAME "<table>:{propertyId}" topic, and the
    /// realtime client returns the already-subscribed channel for a
    /// duplicate topic — the second conversation's callbacks were silently
    /// dropped. Liveness idempotency (audit 2026-07-21): a repeat call for
    /// the same scope keeps the live channel; a scope change tears down
    /// cleanly (real leave) first.
    func subscribe(propertyId: UUID, groupId: UUID?,
                   reload: @escaping @MainActor () async -> Void) async {
        let scope = groupId?.uuidString ?? "main"
        let topic = "\(table):\(propertyId.uuidString):\(scope)"
        if let ch = channel, ch.topic.hasSuffix(topic),
           ch.status == .subscribed || ch.status == .subscribing { return }
        if channel != nil { await unsubscribe() }
        // The b1197 law, applied to the side channels at last: never burn
        // the join timebox on a dead socket — wait (bounded) for it first.
        await awaitSocketConnected()
        let ch = realtimeAnon.channel(topic)
        subs.append(ch.onPostgresChange(
            InsertAction.self,
            schema: "public",
            table: table,
            filter: "property_id=eq.\(propertyId.uuidString)"
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleReload(reload)
            }
        })
        do {
            // Timeboxed: a hung handshake must not stall the thread's
            // appear chain on a never-recovering socket.
            try await withRealtimeTimeout(seconds: 15) {
                try await ch.subscribeWithError()
            }
            channel = ch
        } catch {
            // No trace on failure (b1173: leave from every state).
            debugLog("\(tag) realtime subscribe failed:", error)
            subs.removeAll()
            await ch.unsubscribe()
            await realtimeAnon.removeChannel(ch)
        }
    }

    func unsubscribe() async {
        reloadTask?.cancel()
        reloadTask = nil
        subs.removeAll()
        if let ch = channel {
            await ch.unsubscribe()   // real leave from every state (b1173)
            await realtimeAnon.removeChannel(ch)
            channel = nil
        }
    }

    /// Coalesces bursts of INSERT events into one refetch per quiet window
    /// (C2), and stays quiet in the background (the 0x8BADF00D law).
    private func scheduleReload(_ reload: @escaping @MainActor () async -> Void) {
        reloadTask?.cancel()
        reloadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, !AppLifecycle.isBackgrounded else { return }
            await reload()
        }
    }

    /// Bounded wait for a live socket before starting the join clock —
    /// with the b1198 lesson baked in: a cancelled sleep EXITS the wait
    /// (`catch { return }`), it never busy-spins.
    private func awaitSocketConnected() async {
        guard realtimeAnon.status != .connected else { return }
        if realtimeAnon.status == .disconnected {
            Task { await realtimeAnon.connect() }
        }
        let deadline = Date().addingTimeInterval(10)
        while realtimeAnon.status != .connected, Date() < deadline,
              !AppLifecycle.isBackgrounded {
            do { try await Task.sleep(nanoseconds: 500_000_000) }
            catch { return }
        }
    }
}
