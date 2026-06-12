import SwiftUI

struct TasksView: View {
    @State private var filter: Filter = .all
    @State private var showAdd = false

    enum Filter: String, CaseIterable {
        case all = "All"
        case open = "Open"
        case overdue = "Overdue"
        case done = "Done"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                PageHeader(
                    title: "Tasks",
                    trailing: AnyView(
                        Button {
                            showAdd = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 36, height: 36)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
                        }
                    )
                )
                .padding(.bottom, 16)

                // Filter pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Filter.allCases, id: \.self) { f in
                            Button {
                                withAnimation(.spring(response: 0.3)) { filter = f }
                            } label: {
                                Text(f.rawValue)
                                    .font(.subheadline.weight(filter == f ? .semibold : .regular))
                                    .foregroundStyle(filter == f ? .black : .white.opacity(0.6))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(filter == f ? .white : .white.opacity(0.08), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 16)

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(allTasks) { task in
                            FullTaskRow(task: task)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }
            }
        }
    }

    var allTasks: [FullTask] {
        FullTask.samples.filter {
            switch filter {
            case .all: return true
            case .open: return !$0.isDone && !$0.isOverdue
            case .overdue: return $0.isOverdue
            case .done: return $0.isDone
            }
        }
    }
}

private struct FullTaskRow: View {
    let task: FullTask
    @State private var isDone: Bool

    init(task: FullTask) {
        self.task = task
        _isDone = State(initialValue: task.isDone)
    }

    var body: some View {
        HStack(spacing: 14) {
            Button {
                withAnimation(.spring(response: 0.3)) { isDone.toggle() }
            } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isDone ? .white.opacity(0.6) : .white.opacity(0.3))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(isDone)
                    .foregroundStyle(isDone ? .secondary : .primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label(task.due, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(task.isOverdue ? .red.opacity(0.7) : .secondary)

                    if let category = task.category {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text(category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            PriorityDot(priority: task.priority)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(task.isOverdue ? .red.opacity(0.2) : .white.opacity(0.06), lineWidth: 0.5)
        )
    }
}

private struct PriorityDot: View {
    let priority: String

    var color: Color {
        switch priority {
        case "High": return .red.opacity(0.7)
        case "Medium": return .white.opacity(0.5)
        default: return .white.opacity(0.25)
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }
}

// MARK: - Model

struct FullTask: Identifiable {
    let id = UUID()
    let title: String
    let due: String
    let priority: String
    let category: String?
    var isOverdue: Bool = false
    var isDone: Bool = false

    static let samples: [FullTask] = [
        FullTask(title: "Replace kitchen faucet", due: "Today", priority: "High", category: "Plumbing", isOverdue: true),
        FullTask(title: "Annual boiler service", due: "Jun 13", priority: "High", category: "Heating"),
        FullTask(title: "Clean gutters", due: "Jun 20", priority: "Medium", category: "Exterior"),
        FullTask(title: "Repaint hallway", due: "Jun 28", priority: "Low", category: "Interior"),
        FullTask(title: "Check smoke detectors", due: "Jun 15", priority: "High", category: "Safety"),
        FullTask(title: "Service AC unit", due: "Jul 1", priority: "Medium", category: "HVAC"),
        FullTask(title: "Fix garden gate", due: "May 30", priority: "Low", category: "Exterior", isDone: true),
    ]
}
