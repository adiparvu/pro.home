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

    enum CodingKeys: String, CodingKey {
        case id, title, amount, currency, type, category, date, description
        case propertyId = "property_id"
        case createdAt = "created_at"
        case sharedMemberIds = "shared_member_ids"
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
