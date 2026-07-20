import Foundation

struct FinancialRecord: Identifiable, Codable {
    let id: UUID
    let propertyId: UUID
    var title: String
    var amount: Double
    var currency: String
    var type: String        // "income" | "expense" | "budget"
    var category: String
    var date: String        // "YYYY-MM-DD"
    var description: String?
    let createdAt: String
    var sharedMemberIds: [String] = []   // family_members.id shared this row with (see migration 094)
    /// Free-form labels. The appliance service book rides here:
    /// ["service", "appliance:<uuid>"] links a repair expense to its appliance.
    var tags: [String] = []
    /// Recurring template flag (migration 015): rows with `is_recurring` are
    /// cloned server-side on `next_occurrence` by a daily pg_cron job.
    /// Optional so cached rows written before the columns existed still decode.
    var isRecurring: Bool?
    var recurrenceInterval: String?   // "monthly" | "yearly"
    var nextOccurrence: String?       // "YYYY-MM-DD"

    enum CodingKeys: String, CodingKey {
        case id, title, amount, currency, type, category, date, description, tags
        case propertyId = "property_id"
        case createdAt = "created_at"
        case sharedMemberIds = "shared_member_ids"
        case isRecurring = "is_recurring"
        case recurrenceInterval = "recurrence_interval"
        case nextOccurrence = "next_occurrence"
    }

    var dateFormatted: String {
        guard let d = AppDate.day(from: date) else { return date }
        return AppDate.monthDay.string(from: d)
    }

    var isIncome: Bool { type == "income" }
    var amountDisplay: String {
        CurrencyService.money(amount, code: currency)
    }
}
