import SwiftUI

struct Delivery: Identifiable, Codable, Hashable {
    var id: UUID
    var carrier: String
    var trackingNumber: String
    var description: String
    var status: String   // ordered / in_transit / out_for_delivery / delivered
    var expectedDate: String?
    var notes: String?
    var createdAt: String

    // MARK: Computed

    var statusIcon: String {
        switch status {
        case "ordered":          return "shippingbox.fill"
        case "in_transit":       return "airplane"
        case "out_for_delivery": return "bicycle"
        case "delivered":        return "checkmark.seal.fill"
        default:                 return "shippingbox"
        }
    }

    var statusColor: Color {
        switch status {
        case "ordered":          return .gray
        case "in_transit":       return .blue
        case "out_for_delivery": return .orange
        case "delivered":        return Color(red: 0.2, green: 0.80, blue: 0.4)
        default:                 return .gray
        }
    }

    var statusLabel: String {
        switch status {
        case "ordered":          return "Ordered"
        case "in_transit":       return "In transit"
        case "out_for_delivery": return "Out for delivery"
        case "delivered":        return "Delivered"
        default:                 return status
        }
    }

    var isActive: Bool { status != "delivered" }

    var expectedDisplay: String? {
        guard let ds = expectedDate else { return nil }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        guard let d = fmt.date(from: ds) else { return ds }
        let out = DateFormatter()
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInTomorrow(d) { return "Tomorrow" }
        out.dateFormat = "d MMM"
        return out.string(from: d)
    }

    static let statusOptions: [(id: String, label: String)] = [
        ("ordered",          "Ordered"),
        ("in_transit",       "In transit"),
        ("out_for_delivery", "Out for delivery"),
        ("delivered",        "Delivered"),
    ]

    static let carrierOptions = ["DHL","FedEx","UPS","DPD","GLS","Cargus","Fan Courier","Sameday","Urgent Cargus","Altul"]
}
