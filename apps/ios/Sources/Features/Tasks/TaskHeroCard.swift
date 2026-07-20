import SwiftUI

// MARK: - "Acum" hero card
//
// The assistant's answer to "what should I do next?": one large glass card
// featuring the single most actionable task (ranking lives in TaskTriage).
// A big completion circle, the title, one metadata line, and the same
// "Începe sesiunea" action the task detail uses — WorkSessionStore.shared,
// which drives the Live Activity and the pinned banner. A horizontal swipe
// (or the "Următorul" chip when more candidates wait) advances through the
// shortlist.

struct TaskHeroCard: View {
    @Environment(TaskService.self) private var taskService
    @Environment(FamilyService.self) private var familyService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let task: MaintenanceTask
    /// How many tasks are in today's shortlist (shows the advance affordance
    /// only when there is somewhere to go).
    let candidateCount: Int
    /// Advance the hero by +1 (swipe left / "Următorul") or -1 (swipe right).
    let onAdvance: (Int) -> Void
    /// Tap on the card body = the task's dedicated detail page (where the
    /// Edit button lives).
    let onOpenDetail: () -> Void

    @State private var completing = false
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            heroHeader

            HStack(alignment: .center, spacing: AppSpacing.base) {
                TaskCheckCircle(isOn: completing, ringColor: task.priorityStyle.color, size: 38) {
                    complete()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(task.title)
                        .font(AppFont.title3)
                        .foregroundStyle(completing ? Color.primary.opacity(AppOpacity.disabled) : Color.primary)
                        .strikethrough(completing, color: Color.primary.opacity(0.3))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    TaskMetaLine(task: task, muted: completing)
                        .environment(familyService)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                HapticFeedback.impact(.light)
                onOpenDetail()
            }
            .accessibilityAction(named: Text("task_view_details")) { onOpenDetail() }

            if WorkSessionStore.shared.isTiming(task.id) {
                HStack {
                    SessionRowTimer()
                    Spacer()
                }
            } else if !completing {
                GlassWideButton(icon: "play.fill", label: "session_start") {
                    WorkSessionStore.shared.start(taskId: task.id, title: task.title)
                }
            }
        }
        .padding(AppSpacing.xl)
        .liquidGlass(cornerRadius: AppRadius.xxl, thick: true)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xxl, style: .continuous)
                .strokeBorder(task.priorityStyle.color.opacity(0.22), lineWidth: 1)
        )
        .offset(x: dragOffset)
        .gesture(advanceGesture, including: candidateCount > 1 ? .all : .subviews)
    }

    // MARK: - Header line ("Acum" + next affordance)

    private var heroHeader: some View {
        HStack(spacing: AppSpacing.sm) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(AppFont.scaled(11, weight: .bold))
                Text("task_hero_now")
                    .font(AppFont.label)
            }
            .foregroundStyle(task.isOverdue ? Color.brandDanger : Color.brandPurple)
            .accessibilityElement(children: .combine)

            Spacer()

            if candidateCount > 1 {
                Button {
                    HapticFeedback.selection()
                    onAdvance(1)
                } label: {
                    HStack(spacing: 4) {
                        Text("task_hero_next")
                            .font(AppFont.caption)
                        Image(systemName: "chevron.right")
                            .font(AppFont.scaled(10, weight: .semibold))
                    }
                    .foregroundStyle(Color.secondaryTextColor)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, 5)
                    .glassCapsule()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("task_hero_next"))
            }
        }
    }

    // MARK: - Advance swipe

    private var advanceGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                // Subtle parallax only — the card hints, the release commits.
                dragOffset = reduceMotion ? 0 : max(-36, min(36, value.translation.width * 0.35))
            }
            .onEnded { value in
                withAnimation(.taskSpring) { dragOffset = 0 }
                guard abs(value.translation.width) > abs(value.translation.height),
                      abs(value.translation.width) > 56 else { return }
                HapticFeedback.selection()
                onAdvance(value.translation.width < 0 ? 1 : -1)
            }
    }

    // MARK: - Complete

    private func complete() {
        guard !completing else { return }
        HapticFeedback.success()
        withAnimation(reduceMotion ? .smooth(duration: 0.2) : .taskSpring) { completing = true }
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 550))
            await taskService.toggleComplete(task)
            completing = false
        }
    }
}
