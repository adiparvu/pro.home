import Foundation
import Observation
import Supabase

// MARK: - Typing/recording activity (Chat unification P3a)
//
// The peer-activity subsystem both chat engines share: the throttled
// typing/recording broadcast on the engine's live channel, and the received
// indicator state with its per-peer 4s expiry. DirectMessageService and
// MessageService used to carry byte-identical copies of all of it — every
// tweak (the recording variant, the throttle window) had to be made twice.
// Each engine now owns one of these; the engine keeps owning the channel
// lifecycle and syncs `channel`/`myName` before delegating.
@MainActor
@Observable
final class ChatActivityIndicator {
    /// Peers currently typing or recording (drives the activity bubble).
    private(set) var typingNames: Set<String> = []
    /// Subset of `typingNames` whose latest signal was "recording" — drives
    /// the mic variant of the in-thread activity bubble (WhatsApp-style).
    private(set) var recordingNames: Set<String> = []

    /// The engine's live channel to broadcast on — synced by the engine
    /// before each use, so this type never owns realtime lifecycle.
    @ObservationIgnored var channel: RealtimeChannelV2?
    /// The signed-in user's display name — own signals are never shown.
    @ObservationIgnored var myName: String = ""

    @ObservationIgnored private var typingTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var lastTypingSentAt: Date = .distantPast

    func sendTyping() { sendActivity(kind: "typing") }

    /// Periodic signal while the voice recorder is live — same broadcast as
    /// typing with `kind: "recording"`, so old clients (which ignore the extra
    /// field) still show their plain typing indicator.
    func sendRecording() { sendActivity(kind: "recording") }

    private func sendActivity(kind: String) {
        guard let ch = channel, !myName.isEmpty else { return }
        // Called on every keystroke — throttle to one broadcast per 2.5s
        // (receivers keep the indicator alive 4s per event, so it stays smooth).
        let now = Date()
        guard now.timeIntervalSince(lastTypingSentAt) > 2.5 else { return }
        lastTypingSentAt = now
        // Capture the name by value: Task's implicit self capture would
        // otherwise retain the indicator for the broadcast's lifetime.
        let name = myName
        Task { await ch.broadcast(event: "typing",
                                  message: ["name": .string(name), "kind": .string(kind)]) }
    }

    func handleTyping(_ name: String, kind: String) {
        guard !name.isEmpty, name != myName else { return }
        typingNames.insert(name)
        // The latest signal wins: a peer who stops recording and starts
        // typing flips back to the dots without waiting out the expiry.
        if kind == "recording" { recordingNames.insert(name) }
        else { recordingNames.remove(name) }
        typingTasks[name]?.cancel()
        typingTasks[name] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            self?.typingNames.remove(name)
            self?.recordingNames.remove(name)
        }
    }

    /// Clears indicator state and pending expiries (engine unsubscribe).
    func reset() {
        typingTasks.values.forEach { $0.cancel() }
        typingTasks.removeAll()
        typingNames.removeAll()
        recordingNames.removeAll()
    }
}
