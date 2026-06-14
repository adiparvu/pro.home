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

    enum CodingKeys: String, CodingKey {
        case id, title, amount, currency, type, category, date, description
        case propertyId = "property_id"
        case createdAt = "created_at"
    }

    var dateFormatted: String {
        let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"
        guard let d = iso.date(from: date) else { return date }
        let out = DateFormatter(); out.dateFormat = "MMM d"
        return out.string(from: d)
    }

    var isIncome: Bool { type == "income" }
    var amountDisplay: String {
        let sym = currency == "EUR" ? "€" : currency == "USD" ? "$" : currency
        return String(format: "\(sym)%.0f", amount)
    }
}
