import SwiftUI

// MARK: - Long-press action menu shape (chat unification)
//
// ONE definition of the message menu's anatomy — order, labels, icons, and
// the destructive Delete at the end (HIG row anatomy is law) — for both
// engines. The group and DM lists had byte-similar copies that had already
// drifted subtly; now they pass only their bindings and the shape cannot
// diverge again. A deleted message is just a tombstone: the only thing left
// to do with it is remove it from your own view.

struct ChatActionMenuConfig {
    var isDeleted: Bool
    var isOwn: Bool
    /// Own message with a plain-text body — the only editable kind.
    var canEdit: Bool
    /// The message anchors a loaded reply thread (parent or replies present).
    var hasThread: Bool
    var isMarked: Bool
    var isPinned: Bool

    var onReply: () -> Void
    var onForward: () -> Void
    var onViewThread: () -> Void
    var onCopy: () -> Void
    var onToggleMark: () -> Void
    var onTogglePin: () -> Void
    var onDetails: () -> Void
    var onSelect: () -> Void
    var onEdit: () -> Void
    var onReport: () -> Void
    var onDelete: () -> Void
}

enum ChatActionMenu {
    static func items(_ c: ChatActionMenuConfig) -> [ChatActionItem] {
        if c.isDeleted {
            return [ChatActionItem("Delete", "trash", destructive: true, action: c.onDelete)]
        }
        var items: [ChatActionItem] = [
            ChatActionItem("Reply", "arrowshape.turn.up.left", action: c.onReply),
            ChatActionItem("Forward", "arrowshape.turn.up.right", action: c.onForward),
        ]
        // Isolate the reply thread (iMessage) — offered only when this
        // message is actually part of one.
        if c.hasThread {
            items.append(ChatActionItem("View thread", "bubble.left.and.bubble.right",
                                        action: c.onViewThread))
        }
        items.append(contentsOf: [
            ChatActionItem("Copy", "doc.on.doc", action: c.onCopy),
            ChatActionItem(c.isMarked ? "Unmark" : "Mark", "flag", action: c.onToggleMark),
            ChatActionItem(c.isPinned ? "Unpin" : "Pin", "pin", action: c.onTogglePin),
            // Message details live in the long-press menu (moved off the
            // left-swipe, which peeks the send time iMessage-style).
            ChatActionItem("Details", "info.circle", action: c.onDetails),
            // Enter iMessage-style multi-select, this message pre-checked.
            ChatActionItem("Select", "checkmark.circle", action: c.onSelect),
        ])
        if c.canEdit {
            items.append(ChatActionItem("Edit", "pencil", action: c.onEdit))
        }
        if !c.isOwn {
            // UGC compliance (Guideline 1.2): someone else's message can be
            // reported; the reason dialog + insert live in ReportMessageDialogs.
            items.append(ChatActionItem("Report", "exclamationmark.bubble", action: c.onReport))
        }
        items.append(ChatActionItem("Delete", "trash", destructive: true, action: c.onDelete))
        return items
    }
}
