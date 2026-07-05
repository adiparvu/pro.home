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

    // Live courier tracking (aggregator-driven). All normalized + provider-
    // agnostic: the app never sees Ship24/AfterShip payloads, only these fields
    // written by the tracking webhook. Optional so decoding is safe whether or
    // not the tracking migration has been applied yet.
    var trackerId: String?
    var courierCode: String?
    var liveStatus: String?          // pending / info_received / in_transit / out_for_delivery / available_for_pickup / delivered / exception / failed_attempt / expired
    var estimatedDelivery: String?
    var checkpoints: [TrackingCheckpoint]?
    var lastEventAt: String?
    var trackingEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case id, description, notes, status
        case carrier
        case trackingNumber    = "tracking_number"
        case expectedDate      = "expected_date"
        case createdAt         = "created_at"
        case trackerId         = "tracker_id"
        case courierCode       = "courier_code"
        case liveStatus        = "live_status"
        case estimatedDelivery = "estimated_delivery"
        case checkpoints
        case lastEventAt       = "last_event_at"
        case trackingEnabled   = "tracking_enabled"
    }

    /// Event timeline, newest first (empty until the webhook fills it).
    var liveCheckpoints: [TrackingCheckpoint] { checkpoints ?? [] }

    /// True once the aggregator is tracking this parcel.
    var isLiveTracked: Bool { trackerId != nil }

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
        case "delivered":        return Color.brandSuccess
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

/// One normalized event in a parcel's tracking history. Shape matches the JSON
/// the tracking webhook writes into `packages.checkpoints` — never a courier's
/// own format, so the provider can change without touching this.
struct TrackingCheckpoint: Codable, Hashable, Identifiable {
    var time: String?
    var status: String?
    var message: String?
    var location: String?
    var milestone: String?

    var id: String { "\(time ?? "")-\(status ?? "")-\(location ?? "")" }

    var date: Date? { time.flatMap { ISODate.date(from: $0) } }
}

/// Per-property forwarding address for auto-importing deliveries from shipping
/// emails. The token is the local-part of the address (`<token>@<domain>`).
struct ParcelInbox: Identifiable, Codable, Hashable {
    var id: UUID
    var propertyId: UUID
    var token: String
    var active: Bool

    enum CodingKeys: String, CodingKey {
        case id, token, active
        case propertyId = "property_id"
    }
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
