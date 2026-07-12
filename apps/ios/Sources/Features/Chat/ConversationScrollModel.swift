import SwiftUI
import Observation

// MARK: - Conversation scroll coordinator (Chat unification P1)
//
// The first shared seam between DirectMessageView and ChatView: the
// jump-to-latest button's visibility and the debounced toggle that keeps it
// from flickering at the bottom rest. Both message lists used to carry their
// own copy of this state and logic — DM's debounced, Chat's immediate — so
// every scroll tweak had to be made twice. They now hold one of these instead.
//
// Behaviour is preserved verbatim per view: DM drives it through the debounced
// `setJumpToLatest`, Chat assigns `showJumpToLatest` directly and calls `hide()`
// after a programmatic snap. Later phases can converge them onto one path.
@MainActor
@Observable
final class ConversationScrollModel {
    /// Whether the "jump to latest" button is currently showing.
    var showJumpToLatest = false

    /// Debounce for the bottom-sentinel toggle: at the bottom rest the 1pt
    /// marker can flip in/out on sub-point settles, flickering the button and
    /// stealing its first tap. Only a state that survives 150ms is committed.
    private var toggleTask: Task<Void, Never>?

    /// Debounced show/hide — used by the DM list, whose sentinel jitters.
    func setJumpToLatest(_ show: Bool) {
        toggleTask?.cancel()
        guard show != showJumpToLatest else { return }
        toggleTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) { self.showJumpToLatest = show }
        }
    }

    /// Force the button hidden immediately — after a programmatic snap to the
    /// bottom, where it must never linger.
    func hide() {
        guard showJumpToLatest else { return }
        withAnimation(.easeInOut(duration: 0.2)) { showJumpToLatest = false }
    }

    /// Cancel any pending debounce (call on disappear).
    func cancel() {
        toggleTask?.cancel()
        toggleTask = nil
    }
}
