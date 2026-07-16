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
    private static let cap = 80

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
