import Foundation

/// Lease/contract details for a tenant (a `family_members` row with role
/// "tenant"). Kept in its own table so the people table stays lean.
struct TenantLease: Codable, Identifiable, Hashable {
    let id: UUID
    let propertyId: UUID
    let memberId: UUID
    var leaseStart: String?
    var leaseEnd: String?
    var monthlyRent: Double?
    var currency: String
    var deposit: Double?
    var paymentDay: Int?
    var occupants: Int?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case id, currency, deposit, occupants, notes
        case propertyId  = "property_id"
        case memberId    = "member_id"
        case leaseStart  = "lease_start"
        case leaseEnd    = "lease_end"
        case monthlyRent = "monthly_rent"
        case paymentDay  = "payment_day"
    }

    /// "1.200 EUR / month" style summary, or nil when no rent captured.
    var rentDisplay: String? {
        guard let rent = monthlyRent else { return nil }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = rent.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        let amount = f.string(from: NSNumber(value: rent)) ?? "\(rent)"
        return "\(amount) \(currency)"
    }

    var endDisplay: String? {
        guard let end = leaseEnd else { return nil }
        let inFmt = DateFormatter(); inFmt.dateFormat = "yyyy-MM-dd"
        guard let d = inFmt.date(from: end) else { return end }
        let out = DateFormatter(); out.dateStyle = .medium; out.timeStyle = .none
        return out.string(from: d)
    }
}
