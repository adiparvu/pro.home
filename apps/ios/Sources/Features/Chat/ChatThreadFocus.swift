// iMessage-style reply THREADS. Tapping a reply's quoted preview (or the
// "View thread" menu item) isolates the whole reply chain it belongs to: the
// conversation recedes behind a frosted blur and only the thread's messages
// stay in focus, exactly like Messages on iOS. A single Reply button bridges
// back into the existing reply-focus composer, already targeting the thread.
//
// The engine is model-agnostic: both the group `Message` and the 1:1
// `DirectMessage` carry a `reply_to` parent id, so `ChatThread` computes the
// ordered thread from whichever list the caller already holds in memory, and
// the overlay is generic over the row view each engine builds from its own
// bubble adapter. Nothing here duplicates presentation — the thread renders the
// real `MessageBubble` / `DMBubble`.
import SwiftUI

// MARK: - Threadable abstraction

/// The minimum a message must expose to take part in a reply thread. Kept
/// separate from `Identifiable` (distinct property names) so conforming the two
/// existing models can never clash with their own `id`/`replyTo` members.
protocol ChatThreadMessage {
    var threadId: UUID { get }
    /// The parent this message replies to, if any.
    var threadParentId: UUID? { get }
}

extension Message: ChatThreadMessage {
    var threadId: UUID { id }
    var threadParentId: UUID? { replyTo }
}

extension DirectMessage: ChatThreadMessage {
    var threadId: UUID { id }
    var threadParentId: UUID? { replyTo }
}

// MARK: - Thread computation

enum ChatThread {
    /// The full iMessage-style thread the message at `anchor` belongs to: climb
    /// to the root (the earliest ancestor still loaded), then collect the root
    /// and every transitive reply, in chronological (array) order.
    ///
    /// A reply can only ever follow its parent in a chat transcript, so a single
    /// forward pass over the already-ordered `all` collects every descendant.
    static func members<M: ChatThreadMessage>(anchoredAt anchor: UUID, in all: [M]) -> [UUID] {
        var parentOf: [UUID: UUID?] = [:]
        var present: Set<UUID> = []
        parentOf.reserveCapacity(all.count)
        present.reserveCapacity(all.count)
        for m in all {
            parentOf[m.threadId] = m.threadParentId
            present.insert(m.threadId)
        }
        guard present.contains(anchor) else { return [anchor] }

        // Climb to the root, but only through parents that are actually loaded —
        // an older page not yet fetched simply bounds the thread at what we have.
        var root = anchor
        var steps = 0
        while let parent = parentOf[root] ?? nil, present.contains(parent), steps < 1000 {
            root = parent
            steps += 1
        }

        // Root + transitive descendants, preserving chronological order.
        var keep: Set<UUID> = [root]
        var ordered: [UUID] = []
        for m in all {
            if m.threadId == root {
                ordered.append(m.threadId)
            } else if let parent = m.threadParentId, keep.contains(parent) {
                keep.insert(m.threadId)
                ordered.append(m.threadId)
            }
        }
        return ordered
    }

    /// True when the message at `anchor` is part of a real thread (a parent or
    /// at least one reply is loaded) — the gate for offering thread focus.
    static func hasThread<M: ChatThreadMessage>(anchoredAt anchor: UUID, in all: [M]) -> Bool {
        members(anchoredAt: anchor, in: all).count > 1
    }
}

// MARK: - Thread-focus overlay

/// The frosted, full-screen focus that isolates one reply thread. Generic over
/// the row view so each chat engine renders its own real bubble; the overlay
/// owns only the backdrop, the thread scroll, and the close / reply chrome.
struct ChatThreadFocusOverlay<Row: View>: View {
    let ids: [UUID]
    /// Accent for the Reply control — the conversation's outgoing bubble colour.
    var accent: Color = .accentColor
    /// Bridge into the normal reply-focus composer, already targeting the thread.
    let onReply: () -> Void
    let onDismiss: () -> Void
    /// Builds the real bubble for a message id (each engine's own adapter).
    let row: (UUID) -> Row

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: 0) {
                topBar
                thread
                replyButton
            }
            .opacity(shown ? 1 : 0)
            .scaleEffect(reduceMotion ? 1 : (shown ? 1 : 0.96))
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) { shown = true }
        }
    }

    // A tap anywhere outside the thread column dismisses (iMessage). The
    // material frosts the live conversation behind it rather than hiding it.
    private var backdrop: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { onDismiss() }
            .opacity(shown ? 1 : 0)
            .accessibilityLabel(Text("Close"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onDismiss() }
    }

    private var topBar: some View {
        ZStack {
            Text("chat_thread_title")
                .font(AppFont.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            HStack {
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark")
                        .font(AppFont.subheadline.weight(.semibold))
                        .foregroundStyle(Color.secondaryTextColor)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .glassCircle()
                .accessibilityLabel(Text("Close"))
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.top, AppSpacing.md)
        .padding(.bottom, AppSpacing.sm)
    }

    private var thread: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 2) {
                ForEach(ids, id: \.self) { id in row(id) }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.lg)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.bottom)
        .frame(maxHeight: .infinity)
    }

    private var replyButton: some View {
        Button { onReply() } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrowshape.turn.up.left.fill")
                Text("Reply")
            }
            .font(AppFont.subheadline.weight(.semibold))
            .foregroundStyle(accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.md)
        }
        .buttonStyle(.plain)
        .glassCapsule()
        .padding(.horizontal, AppSpacing.xl)
        .padding(.bottom, AppSpacing.lg)
    }
}
