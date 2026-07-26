import SwiftUI

// MARK: - Shared savings goals ("Obiective comune")
//
// A family savings target with per-member manual contributions. Honesty law:
// "collected", percent and the ~N-months estimate are computed from the real
// contribution ledger and the household's monthly pace — never a fabricated
// figure. A goal without a monthly rate shows the target without an ETA.

struct SavingsGoal: Identifiable, Codable, Hashable {
    let id: UUID
    let propertyId: UUID
    var title: String
    var icon: String?
    var color: String?               // brand token name (see `tint`)
    var targetAmount: Double
    var currency: String
    var monthlyPerMember: Double?
    var deadline: String?            // "YYYY-MM-DD"
    var sharedMemberIds: [String]
    var createdBy: UUID?
    let createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, icon, color, currency, deadline
        case propertyId        = "property_id"
        case targetAmount      = "target_amount"
        case monthlyPerMember  = "monthly_per_member"
        case sharedMemberIds   = "shared_member_ids"
        case createdBy         = "created_by"
        case createdAt         = "created_at"
        case updatedAt         = "updated_at"
    }

    /// Resolved accent — a brand token name maps to its color, else a hex,
    /// else the app accent. Keeps the DB free of raw color literals.
    var tint: Color { SavingsGoal.tint(forToken: color) }

    /// Token → color, shared by the model and the goal editor's swatches.
    static func tint(forToken token: String?) -> Color {
        switch token {
        case "brandPurple":      return .brandPurple
        case "brandSuccess":     return .brandSuccess
        case "brandPrimaryBlue": return .brandPrimaryBlue
        case "brandWarning":     return .brandWarning
        case "brandDanger":      return .brandDanger
        case "brandSkyBlue":     return .brandSkyBlue
        default:
            if let t = token, t.hasPrefix("#") { return Color(hex: t) ?? .accentColor }
            return .accentColor
        }
    }

    var iconName: String { icon?.isEmpty == false ? icon! : "target" }

    var deadlineDate: Date? { deadline.flatMap { AppDate.day(from: $0) } }
}

struct GoalContribution: Identifiable, Codable, Hashable {
    let id: UUID
    let goalId: UUID
    let propertyId: UUID
    var memberId: String?
    var memberName: String?
    var amount: Double
    var note: String?
    var contributedAt: String       // "YYYY-MM-DD"
    var createdBy: UUID?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, amount, note
        case goalId          = "goal_id"
        case propertyId      = "property_id"
        case memberId        = "member_id"
        case memberName      = "member_name"
        case contributedAt   = "contributed_at"
        case createdBy       = "created_by"
        case createdAt       = "created_at"
    }

    var date: Date? { AppDate.day(from: contributedAt) }
}

// MARK: - Derived progress (pure, testable)

/// Everything the UI needs about one goal, computed from its contributions.
/// No stored aggregates — the ledger is the single source of truth.
struct SavingsGoalProgress {
    let goal: SavingsGoal
    let collected: Double
    /// Per-member totals, largest first — powers the "per member" breakdown.
    let byMember: [(name: String, amount: Double)]

    var target: Double { goal.targetAmount }
    var remaining: Double { max(0, target - collected) }
    /// 0…1, clamped — a goal can be over-funded without overflowing the bar.
    var fraction: Double { target > 0 ? min(1, collected / target) : 0 }
    var percent: Int { Int((fraction * 100).rounded()) }
    var isComplete: Bool { collected >= target && target > 0 }

    /// Estimated months left, from the honest monthly pace: the per-member
    /// pledge × contributing members when set, else the household's average
    /// monthly inflow over the last 6 months. Nil when no pace can be proven.
    var monthsRemaining: Int? {
        guard remaining > 0 else { return 0 }
        let pace = monthlyPace
        guard pace > 0 else { return nil }
        return Int((remaining / pace).rounded(.up))
    }

    /// The monthly rate used for the estimate (see `monthsRemaining`).
    let monthlyPace: Double

    init(goal: SavingsGoal, contributions: [GoalContribution]) {
        self.goal = goal
        let mine = contributions.filter { $0.goalId == goal.id }
        self.collected = mine.reduce(0) { $0 + $1.amount }

        // Per-member rollup keyed by display name (fallback "—").
        var totals: [String: Double] = [:]
        for c in mine {
            let key = (c.memberName?.isEmpty == false ? c.memberName! : "—")
            totals[key, default: 0] += c.amount
        }
        self.byMember = totals.sorted { $0.value > $1.value }
            .map { (name: $0.key, amount: $0.value) }

        // Pace: explicit pledge × distinct contributing members (min 1), else
        // the average of the last 6 calendar months of real contributions.
        if let pledge = goal.monthlyPerMember, pledge > 0 {
            let members = max(1, Set(mine.compactMap { $0.memberId ?? $0.memberName }).count)
            self.monthlyPace = pledge * Double(members)
        } else {
            let cal = Calendar.current
            let now = Date()
            guard let sixAgo = cal.date(byAdding: .month, value: -6, to: now) else {
                self.monthlyPace = 0; return
            }
            let recent = mine.filter { ($0.date ?? .distantPast) >= sixAgo }
            let sum = recent.reduce(0) { $0 + $1.amount }
            self.monthlyPace = sum > 0 ? sum / 6 : 0
        }
    }
}
