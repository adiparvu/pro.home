import SwiftUI

// MARK: - Detail Tab Bar

struct DetailTabBar: View {
    @Binding var selected: PropertyElementDetailView.DetailTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PropertyElementDetailView.DetailTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.25)) { selected = tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14, weight: selected == tab ? .semibold : .regular))
                        Text(LocalizedStringKey(tab.rawValue))
                            .font(.system(size: 11, weight: selected == tab ? .semibold : .regular))
                    }
                    .foregroundStyle(selected == tab ? Color.white : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(selected == tab ? Color.primary.opacity(0.12) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppSpacing.xxs)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Linked document row

struct LinkedDocumentRow: View {
    let doc: DocumentModel
    let onOpen: () -> Void
    let onUnlink: () -> Void

    var body: some View {
        GlassCard(padding: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 36, height: 36)
                    Image(systemName: doc.categoryIcon)
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(Color.accentColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(doc.name).font(.subheadline.weight(.medium)).lineLimit(1)
                    Text(LocalizedStringKey(doc.category.capitalized)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onOpen) {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 16)).foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onUnlink) {
                Label("Unlink", systemImage: "link.badge.minus")
            }
        }
    }
}

// MARK: - Document link picker

struct DocumentLinkPicker: View {
    let elementId: UUID
    @EnvironmentObject private var documentService: DocumentService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    let available = documentService.documents.filter { $0.elementId == nil }
                    VStack(spacing: 10) {
                        if available.isEmpty {
                            Text("All documents are already linked or no documents exist.")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.top, 40).padding(.horizontal, AppSpacing.xxl)
                        } else {
                            ForEach(available) { doc in
                                Button {
                                    Task {
                                        await documentService.setElement(elementId, for: doc)
                                        dismiss()
                                    }
                                } label: {
                                    GlassCard(padding: 12) {
                                        HStack(spacing: 12) {
                                            Image(systemName: doc.categoryIcon)
                                                .font(.system(size: 15)).foregroundStyle(Color.accentColor).frame(width: 28)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(doc.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                                                Text(LocalizedStringKey(doc.category.capitalized)).font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.sm)
                }
            }
            .navigationTitle("Link document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Linked task row

struct LinkedTaskRow: View {
    let task: MaintenanceTask
    let onToggle: () -> Void
    let onUnlink: () -> Void

    var body: some View {
        GlassCard(padding: 12) {
            HStack(spacing: 12) {
                Button(action: onToggle) {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(task.isCompleted ? Color(red: 0.2, green: 0.8, blue: 0.45) : Color.secondary)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                        .strikethrough(task.isCompleted)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Circle().fill(task.priorityColor).frame(width: 6, height: 6)
                        Text(task.dueDateDisplay).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onUnlink) {
                Label("Unlink", systemImage: "link.badge.minus")
            }
        }
    }
}

// MARK: - Task link picker

struct TaskLinkPicker: View {
    let elementId: UUID
    @EnvironmentObject private var taskService: TaskService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    let available = taskService.tasks.filter { $0.elementId == nil && !$0.isCompleted }
                    VStack(spacing: 10) {
                        if available.isEmpty {
                            Text("No tasks available to link.")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.top, 40).padding(.horizontal, AppSpacing.xxl)
                        } else {
                            ForEach(available) { task in
                                Button {
                                    Task {
                                        await taskService.setElement(elementId, for: task)
                                        dismiss()
                                    }
                                } label: {
                                    GlassCard(padding: 12) {
                                        HStack(spacing: 12) {
                                            Circle().fill(task.priorityColor).frame(width: 8, height: 8)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(task.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                                                Text(task.dueDateDisplay).font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.sm)
                }
            }
            .navigationTitle("Link task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
