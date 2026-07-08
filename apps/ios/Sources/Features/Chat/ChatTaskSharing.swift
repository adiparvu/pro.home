import SwiftUI

// MARK: - Task sharing, the PRVIO way
//
// A task dropped into a conversation is a live card, not a pasted string:
// it rides the messages pipeline as attachmentType "task" with a small JSON
// payload, renders as a tappable card, and opens the real task in Tasks.
// The payload snapshots title/due at send time so the bubble stays readable
// even if the task is later deleted.

struct SharedTaskPayload: Codable {
    var id: UUID
    var title: String
    var due: String?
    var priority: String

    static func encode(_ payload: SharedTaskPayload) -> String? {
        (try? JSONEncoder().encode(payload)).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func decode(_ body: String?) -> SharedTaskPayload? {
        guard let data = body?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SharedTaskPayload.self, from: data)
    }

    var priorityColor: Color {
        switch priority {
        case "high", "urgent": return Color.brandDanger
        case "low":            return Color.brandSuccess
        default:               return Color.brandWarning
        }
    }
}

extension Message {
    var isTaskShare: Bool { attachmentType == "task" }
}

// MARK: - The card bubble

struct TaskCardBubble: View {
    let payload: SharedTaskPayload
    let isOwn: Bool
    let bubbleColor: Color
    var hasTail: Bool = true

    @Environment(AppRouter.self) private var router

    private var onBubble: Color { isOwn ? bubbleColor.readableText : .primary }

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            // Works from the main chat and from the Communities sheet alike:
            // the route lands, and any open local presentation is asked to
            // clear the stage.
            router.navigate(to: .tasks(id: payload.id))
            router.closeAllPresentations()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checklist")
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isOwn ? onBubble : payload.priorityColor)
                    .frame(width: 38, height: 38)
                    .background((isOwn ? onBubble.opacity(0.15) : payload.priorityColor.opacity(0.14)),
                                in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(payload.title)
                        .font(AppFont.subheadline)
                        .foregroundStyle(isOwn ? onBubble : .primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(payload.due?.isEmpty == false
                         ? payload.due ?? ""
                         : String(localized: "task_card_no_due"))
                        .font(.system(size: 12))
                        .foregroundStyle((isOwn ? onBubble : Color.primary).opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(AppFont.captionStrong)
                    .foregroundStyle((isOwn ? onBubble : Color.primary).opacity(0.4))
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, 10)
            .frame(minWidth: 200, maxWidth: 250, alignment: .leading)
            .background(isOwn ? bubbleColor : Color.primary.opacity(0.08),
                        in: ChatBubbleShape(isOwn: isOwn, hasTail: hasTail))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(payload.title))
        .accessibilityHint(Text("task_card_open"))
    }
}

// MARK: - Picker (which task to share)

struct TaskSharePicker: View {
    @Environment(TaskService.self) private var taskService
    @Environment(\.dismiss) private var dismiss
    let onShare: (MaintenanceTask) -> Void

    private var openTasks: [MaintenanceTask] {
        taskService.tasks.filter { !$0.isCompleted }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    if openTasks.isEmpty {
                        EmptyStateView(icon: "checklist",
                                       title: "task_share_empty",
                                       message: "task_share_empty_hint")
                            .padding(.top, AppSpacing.xxl)
                    }
                    ForEach(openTasks) { task in
                        Button {
                            HapticFeedback.selection()
                            let picked = task
                            dismiss()
                            onShare(picked)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "checklist")
                                    .font(AppFont.footnote)
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(Color.brandPrimaryBlue)
                                    .frame(width: 34, height: 34)
                                    .glassCircle()
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title)
                                        .font(AppFont.body)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(task.dueDateDisplay)
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.primary.opacity(0.45))
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "paperplane.fill")
                                    .font(AppFont.caption)
                                    .foregroundStyle(Color.accentColor)
                            }
                            .padding(.horizontal, AppSpacing.lg).padding(.vertical, 10)
                            .liquidGlass(cornerRadius: 14)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(AppSpacing.lg)
            }
            .background(appBackground.ignoresSafeArea())
            .navigationTitle(Text("task_share_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationBackground(.thinMaterial)
        .presentationDetents([.medium, .large])
    }
}
