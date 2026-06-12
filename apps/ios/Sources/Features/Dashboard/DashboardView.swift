import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var auth: AuthService

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Good morning")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("PRV House")
                                .font(.title2.weight(.bold))
                        }
                        Spacer()
                        Button {
                        } label: {
                            Image(systemName: "bell")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 40, height: 40)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(Circle().strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    // Health Score Card
                    HealthScoreCard()
                        .padding(.horizontal, 20)

                    // Quick Stats
                    HStack(spacing: 12) {
                        QuickStatCard(icon: "checkmark.circle", label: "Open Tasks", value: "7", trend: "-2")
                        QuickStatCard(icon: "exclamationmark.triangle", label: "Overdue", value: "2", trend: "+1", trendNegative: true)
                        QuickStatCard(icon: "calendar", label: "This Week", value: "5", trend: nil)
                    }
                    .padding(.horizontal, 20)

                    // Recent Tasks
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Recent Tasks")
                                .font(.headline)
                            Spacer()
                            Button("See all") {}
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(TaskItem.samples) { task in
                            TaskRowView(task: task)
                        }
                    }
                    .padding(.horizontal, 20)

                    // Finances snapshot
                    FinancesCard()
                        .padding(.horizontal, 20)

                    Spacer(minLength: 100)
                }
            }
        }
    }
}

private struct HealthScoreCard: View {
    let score = 78

    var body: some View {
        GlassCard {
            HStack(spacing: 20) {
                // Ring
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.1), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: CGFloat(score) / 100)
                        .stroke(.white.opacity(0.8), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(duration: 1.2), value: score)
                    Text("\(score)")
                        .font(.title2.weight(.bold))
                }
                .frame(width: 80, height: 80)

                VStack(alignment: .leading, spacing: 6) {
                    Label("Good", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.08), in: Capsule())

                    Text("Property Health")
                        .font(.headline)

                    Text("Updated 2h ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct QuickStatCard: View {
    let icon: String
    let label: String
    let value: String
    let trend: String?
    var trendNegative: Bool = false

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                IconBadge(icon: icon, size: 32)

                Text(value)
                    .font(.title2.weight(.bold))

                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let trend {
                    Text(trend)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(trendNegative ? .red.opacity(0.7) : .white.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TaskRowView: View {
    let task: TaskItem

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(task.isOverdue ? .red.opacity(0.3) : .white.opacity(0.08))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(task.due)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(task.priority)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.white.opacity(0.06), in: Capsule())
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
    }
}

private struct FinancesCard: View {
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Finances")
                        .font(.headline)
                    Spacer()
                    Text("This month")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 0) {
                    FinanceStat(label: "Income", value: "€3,200", positive: true)
                    Divider().frame(height: 40).overlay(.white.opacity(0.1))
                    FinanceStat(label: "Expenses", value: "€890")
                    Divider().frame(height: 40).overlay(.white.opacity(0.1))
                    FinanceStat(label: "Net", value: "€2,310", positive: true)
                }
            }
        }
    }
}

private struct FinanceStat: View {
    let label: String
    let value: String
    var positive: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(positive ? .white : .white.opacity(0.6))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Models

struct TaskItem: Identifiable {
    let id = UUID()
    let title: String
    let due: String
    let priority: String
    var isOverdue: Bool = false

    static let samples = [
        TaskItem(title: "Replace kitchen faucet", due: "Today", priority: "High", isOverdue: true),
        TaskItem(title: "Annual boiler service", due: "Tomorrow", priority: "High"),
        TaskItem(title: "Clean gutters", due: "Jun 20", priority: "Medium"),
    ]
}
