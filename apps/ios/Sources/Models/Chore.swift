import SwiftUI

// MARK: - Chores & allowance ("Corvezi & alocație")
//
// Small household jobs with a money reward, run as an honest ledger between
// parent and child: the child (or a parent on their behalf) logs a completion,
// a parent approves it, and the approved-but-unpaid rows form the child's
// live balance. A payout stamps the rows paid and writes ONE real expense
// record (tag "allowance") into the family ledger — no invented numbers,
// every leu on the reward chart traces back to an approved completion.

enum ChoreRecurrence: String, CaseIterable, Identifiable {
    case once, daily, weekly
    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .once:   return "chore_rec_once"
        case .daily:  return "chore_rec_daily"
        case .weekly: return "chore_rec_weekly"
        }
    }
}

struct Chore: Identifiable, Codable, Hashable {
    let id: UUID
    let propertyId: UUID
    var title: String
    var icon: String?
    var reward: Double
    var currency: String
    var assignedMemberId: String?
    var assignedMemberName: String?
    var recurrence: String
    var active: Bool
    var createdBy: UUID?
    let createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, icon, reward, currency, recurrence, active
        case propertyId         = "property_id"
        case assignedMemberId   = "assigned_member_id"
        case assignedMemberName = "assigned_member_name"
        case createdBy          = "created_by"
        case createdAt          = "created_at"
        case updatedAt          = "updated_at"
    }

    var recurrenceKind: ChoreRecurrence { ChoreRecurrence(rawValue: recurrence) ?? .weekly }
    var iconName: String { icon ?? "sparkles" }
}

struct ChoreCompletion: Identifiable, Codable, Hashable {
    let id: UUID
    let choreId: UUID
    let propertyId: UUID
    var memberId: String?
    var memberName: String?
    var reward: Double
    var currency: String
    var completedAt: String        // "YYYY-MM-DD"
    var approvedBy: UUID?
    var approvedAt: String?
    var paidAt: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, reward, currency
        case choreId     = "chore_id"
        case propertyId  = "property_id"
        case memberId    = "member_id"
        case memberName  = "member_name"
        case completedAt = "completed_at"
        case approvedBy  = "approved_by"
        case approvedAt  = "approved_at"
        case paidAt      = "paid_at"
        case createdAt   = "created_at"
    }

    var date: Date? { AppDate.day(from: completedAt) }
    var isApproved: Bool { approvedAt != nil }
    var isPaid: Bool { paidAt != nil }

    /// One identity per child across id/name — assigned children may not have
    /// their own account yet, so the name is the honest fallback key.
    var memberKey: String { memberId ?? memberName ?? "?" }
}

// MARK: - Derived balances (pure, testable)

/// A child's live allowance balance: everything approved and not yet paid,
/// kept per currency so mixed-currency rewards never get silently summed.
struct ChoreBalance: Identifiable {
    let memberKey: String
    let memberName: String
    let totals: [(currency: String, amount: Double)]
    let count: Int
    var id: String { memberKey }

    static func balances(from completions: [ChoreCompletion]) -> [ChoreBalance] {
        let unpaid = completions.filter { $0.isApproved && !$0.isPaid }
        let grouped = Dictionary(grouping: unpaid, by: { $0.memberKey })
        return grouped.map { key, rows in
            let perCurrency = Dictionary(grouping: rows, by: { $0.currency })
                .map { (currency: $0.key, amount: $0.value.reduce(0) { $0 + $1.reward }) }
                .sorted { $0.currency < $1.currency }
            return ChoreBalance(memberKey: key,
                                memberName: rows.first?.memberName ?? "—",
                                totals: perCurrency,
                                count: rows.count)
        }
        .sorted { $0.memberName < $1.memberName }
    }
}
