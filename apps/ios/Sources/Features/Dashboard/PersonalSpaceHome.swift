import SwiftUI

// MARK: - Personal space (outsider home)
//
// The home tab for non-family roles (tenant today). The family dashboard is
// built from surfaces RLS now empties for outsiders — presence, family chat,
// household modules — so instead of a broken family UI, an outsider gets a
// calm personal page scoped to exactly what the backend lets them read:
// their tasks, their line to the owner, and the documents shared with them.

struct PersonalSpaceHome: View {
    @Environment(PropertyService.self) private var propertyService
    @Environment(TaskService.self) private var taskService
    @Environment(AppRouter.self) private var router

    /// The three most pressing open tasks — the page is a glance, not a list.
    private var openTasks: [MaintenanceTask] {
        Array(taskService.tasks.filter { !$0.isCompleted }.prefix(3))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: AppSpacing.lg) {
                header
                tasksCard
                messagesCard
                documentsCard
                Spacer(minLength: 120)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.lg)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationBarHidden(true)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text("personal_home_title")
                .font(AppFont.title)
                .foregroundStyle(.primary)
            if let name = propertyService.primary?.name, !name.isEmpty {
                Text(verbatim: name)
                    .font(AppFont.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, AppSpacing.sm)
        .accessibilityElement(children: .combine)
    }

    // MARK: My tasks

    private var tasksCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack {
                    Text("personal_home_tasks")
                        .font(AppFont.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Button {
                        HapticFeedback.impact(.light)
                        router.navigate(to: .tasks(id: nil))
                    } label: {
                        Text("personal_home_all_tasks")
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }

                if openTasks.isEmpty {
                    Text("personal_home_no_tasks")
                        .font(AppFont.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, AppSpacing.xs)
                } else {
                    VStack(spacing: 0) {
                        ForEach(openTasks) { task in
                            taskRow(task)
                            if task.id != openTasks.last?.id {
                                Divider().overlay(Color.hairline)
                            }
                        }
                    }
                }
            }
        }
    }

    private func taskRow(_ task: MaintenanceTask) -> some View {
        Button {
            HapticFeedback.impact(.light)
            router.navigate(to: .tasks(id: task.id))
        } label: {
            HStack(spacing: AppSpacing.md) {
                Circle()
                    .fill(task.priorityColor)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: task.title)
                        .font(AppFont.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if task.dueDate != nil {
                        Text(verbatim: task.dueDateDisplay)
                            .font(AppFont.caption)
                            .foregroundStyle(task.isOverdue ? Color.brandDanger : .secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
            }
            .padding(.vertical, AppSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Messages

    private var messagesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("personal_home_messages")
                    .font(AppFont.headline)
                    .foregroundStyle(.primary)
                Button {
                    HapticFeedback.impact(.light)
                    router.navigate(to: .chat)
                } label: {
                    HStack(spacing: AppSpacing.md) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(AppFont.scaled(16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .glassCircle()
                        Text("personal_home_contact")
                            .font(AppFont.body)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(AppFont.captionEmphasis)
                            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Documents

    private var documentsCard: some View {
        GlassCard {
            Button {
                HapticFeedback.impact(.light)
                router.navigate(to: .documents(id: nil))
            } label: {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: "doc.text.fill")
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .glassCircle()
                    Text("personal_home_documents")
                        .font(AppFont.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AppFont.captionEmphasis)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
