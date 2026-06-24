import SwiftUI

struct Delivery: Identifiable, Codable, Hashable {
    var id: UUID
    var carrier: String?
    var trackingNumber: String?
    var description: String
    var status: String   // expected / out_for_delivery / delivered / missed / returned
    var expectedDate: String?
    var notes: String?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, description, notes, status
        case carrier
        case trackingNumber = "tracking_number"
        case expectedDate   = "expected_date"
        case createdAt      = "created_at"
    }

    // MARK: Computed

    var statusIcon: String {
        switch status {
        case "expected":         return "shippingbox.fill"
        case "out_for_delivery": return "bicycle"
        case "delivered":        return "checkmark.seal.fill"
        case "missed":           return "exclamationmark.triangle.fill"
        case "returned":         return "arrow.uturn.left.circle.fill"
        default:                 return "shippingbox"
        }
    }

    var statusColor: Color {
        switch status {
        case "expected":         return .blue
        case "out_for_delivery": return .orange
        case "delivered":        return Color(red: 0.2, green: 0.80, blue: 0.4)
        case "missed":           return .red
        case "returned":         return .gray
        default:                 return .gray
        }
    }

    var statusLabel: String {
        switch status {
        case "expected":         return String(localized: "Expected")
        case "out_for_delivery": return String(localized: "Out for delivery")
        case "delivered":        return String(localized: "Delivered")
        case "missed":           return String(localized: "Missed")
        case "returned":         return String(localized: "Returned")
        default:                 return status
        }
    }

    var isActive: Bool {
        status == "expected" || status == "out_for_delivery"
    }

    var expectedDisplay: String? {
        guard let ds = expectedDate else { return nil }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        guard let d = fmt.date(from: ds) else { return ds }
        let out = DateFormatter()
        if Calendar.current.isDateInToday(d) { return String(localized: "Today") }
        if Calendar.current.isDateInTomorrow(d) { return String(localized: "Tomorrow") }
        out.dateFormat = "d MMM"
        return out.string(from: d)
    }

    static var statusOptions: [(id: String, label: String)] {[
        ("expected",         String(localized: "Expected")),
        ("out_for_delivery", String(localized: "Out for delivery")),
        ("delivered",        String(localized: "Delivered")),
        ("missed",           String(localized: "Missed")),
        ("returned",         String(localized: "Returned")),
    ]}

    static let carrierOptions = ["DHL","FedEx","UPS","DPD","GLS","Cargus","Fan Courier","Sameday","Urgent Cargus","Altul"]
}

struct NewDelivery: Encodable {
    let propertyId: UUID
    let description: String
    let carrier: String?
    let trackingNumber: String?
    let status: String
    let expectedDate: String?
    let notes: String?
    enum CodingKeys: String, CodingKey {
        case description, carrier, status, notes
        case propertyId     = "property_id"
        case trackingNumber = "tracking_number"
        case expectedDate   = "expected_date"
    }
}
