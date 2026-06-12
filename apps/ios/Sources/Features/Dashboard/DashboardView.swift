import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var taskService: TaskService
    @EnvironmentObject private var propertyService: PropertyService

    private var healthScore: Int {
        if let score = propertyService.primary?.healthScore { return Int(score) }
        guard !taskService.tasks.isEmpty else { return 100 }
        let over = taskService.overdueCount
        let open = taskService.openCount
        return max(min(100 - over * 12 - open * 2, 100), 0)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                header
                HealthScoreCard(score: healthScore, isLoading: taskService.isLoading)
                statsRow
                if !taskService.tasks.isEmpty { recentSection }
                FinancesSnapshotCard()
                Spacer(minLength: 110)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarHidden(true)
        .refreshable { await taskService.load() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Good \(greeting())")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.5))
                Text(displayName)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
            }
            Spacer()
            ZStack {
                Circle()
                    .fill(.white.opacity(0.07))
                    .frame(width: 44, height: 44)
                Image(systemName: "bell.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 12) {
            DashStatCard(
                value: "\(taskService.openCount)",
                label: "Open",
                color: .blue
            )
            DashStatCard(
                value: "\(taskService.overdueCount)",
                label: "Overdue",
                color: taskService.overdueCount > 0 ? .red : Color(red: 0.3, green: 0.9, blue: 0.5)
            )
            DashStatCard(
                value: "\(taskService.completedThisWeek)",
                label: "Done / week",
                color: Color(red: 0.3, green: 0.88, blue: 0.55)
            )
        }
    }

    // MARK: - Recent tasks

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Tasks")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
            }
            VStack(spacing: 8) {
                ForEach(taskService.tasks.prefix(3)) { task in
                    DashTaskRow(task: task)
                }
            }
        }
    }

    // MARK: - Helpers

    private var displayName: String {
        auth.session?.user.email?
            .components(separatedBy: "@").first?
            .capitalized ?? "there"
    }

    private func greeting() -> String {
        let h = Calendar.current.component(.hour, from: Date())
        if h < 12 { return "morning" }
        if h < 18 { return "afternoon" }
        return "evening"
    }
}

// MARK: - Health Score Card

struct HealthScoreCard: View {
    let score: Int
    let isLoading: Bool

    private var color: Color {
        score >= 80 ? Color(red: 0.25, green: 0.88, blue: 0.55)
            : score >= 55 ? .orange
            : .red
    }
    private var label: String {
        score >= 80 ? "Excellent" : score >= 60 ? "Good" : score >= 40 ? "Fair" : "Needs Attention"
    }

    var body: some View {
        GlassCard {
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.08), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: isLoading ? 0 : CGFloat(score) / 100)
                        .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 1.1, dampingFraction: 0.8), value: score)
                    VStack(spacing: 1) {
                        Text(isLoading ? "–" : "\(score)")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.white)
                        Text("/ 100")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .frame(width: 88, height: 88)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Property Health")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(isLoading ? "Loading…" : label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(color)
                    Text(isLoading ? " " : score >= 80
                         ? "Everything looks on track."
                         : "Some tasks need attention.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(2)
                }
                Spacer()
            }
        }
    }
}

// MARK: - Stat Card

struct DashStatCard: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        GlassCard(padding: 14) {
            VStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Dash Task Row

struct DashTaskRow: View {
    let task: MaintenanceTask

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(task.priorityColor)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(task.isCompleted ? .white.opacity(0.38) : .white)
                    .strikethrough(task.isCompleted, color: .white.opacity(0.35))
                    .lineLimit(1)
                Text(task.dueDateDisplay)
                    .font(.system(size: 11))
                    .foregroundStyle(task.isOverdue ? .red.opacity(0.8) : .white.opacity(0.38))
            }

            Spacer()

            Text(task.statusDisplay)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.white.opacity(0.07), in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Finances Snapshot

struct FinancesSnapshotCard: View {
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Finances")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("This month")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                }
                HStack(spacing: 0) {
                    FinStat(label: "Income", value: "€3,200", color: Color(red: 0.25, green: 0.88, blue: 0.55))
                    Rectangle().fill(.white.opacity(0.08)).frame(width: 0.5, height: 34)
                    FinStat(label: "Expenses", value: "€890", color: .orange)
                    Rectangle().fill(.white.opacity(0.08)).frame(width: 0.5, height: 34)
                    FinStat(label: "Net", value: "€2,310", color: .white)
                }
            }
        }
    }
}

private struct FinStat: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Shared bg

var appBackground: Color { Color(red: 0.06, green: 0.06, blue: 0.08) }
