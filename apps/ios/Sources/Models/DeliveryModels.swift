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
    var receivedAt: String?

    // Email-import enrichment. Every reference the importer has seen for this
    // parcel (order numbers, AWBs from later emails) lands in `aliases`, the
    // shop name in `merchant`, and the emails themselves in `sourceEmails`.
    // Optional so pre-migration caches decode.
    var aliases: [String]?
    var merchant: String?
    var sourceEmails: [DeliverySourceEmail]?

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
        case receivedAt        = "received_at"
        case aliases, merchant
        case sourceEmails      = "source_emails"
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

    /// Every code that identifies this parcel — the tracking number first,
    /// then the imported aliases. Order-preserving, deduped.
    var allReferences: [String] {
        var seen = Set<String>()
        var refs: [String] = []
        if let tn = trackingNumber, !tn.isEmpty, seen.insert(tn).inserted { refs.append(tn) }
        for alias in aliases ?? [] where !alias.isEmpty && seen.insert(alias).inserted {
            refs.append(alias)
        }
        return refs
    }

    /// Best-effort shape of a reference — distinctive carrier formats and
    /// short digit runs read as AWBs, very long digit runs as merchant order
    /// numbers, anything else stays a plain reference. Labeling only; never
    /// used to reject a code.
    static func referenceKind(_ ref: String) -> DeliveryReferenceKind {
        let t = ref.uppercased().filter { !$0.isWhitespace }
        // UPS "1Z…" and UPU S10 formats are unmistakably tracking codes.
        if t.range(of: "^1Z[0-9A-Z]{16}$", options: .regularExpression) != nil { return .awb }
        if t.range(of: "^[A-Z]{2}\\d{9}[A-Z]{2}$", options: .regularExpression) != nil { return .awb }
        // Plain digit runs: courier AWBs stay under ~14 digits; merchant
        // order numbers (eMAG & co.) run longer.
        if t.range(of: "^\\d{8,14}$", options: .regularExpression) != nil { return .awb }
        if t.range(of: "^\\d{15,}$", options: .regularExpression) != nil { return .order }
        return .other
    }

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

    // MARK: Live journey (progress stepper)
    //
    // Four milestones every parcel passes through, derived from the live
    // tracking status when the aggregator is following it, otherwise from the
    // manual status. The bar fills up to `progressStage`.
    static let journeyStages = 4  // Info received → In transit → Out for delivery → Delivered

    /// 0…3 — how far along the journey this parcel is.
    var progressStage: Int {
        switch liveStatus ?? status {
        case "delivered":                            return 3
        case "out_for_delivery", "available_for_pickup": return 2
        case "in_transit":                           return 1
        default:                                     return 0  // pending / info_received / expected
        }
    }

    /// A problem on the way — the bar turns to a warning instead of progress.
    var hasException: Bool {
        switch liveStatus ?? status {
        case "exception", "failed_attempt", "expired", "missed", "returned": return true
        default: return false
        }
    }

    /// The most precise arrival estimate available: the courier's own ETA when
    /// live-tracked, otherwise the expected date the user entered.
    var etaDisplay: String? {
        if let e = estimatedDelivery, let d = AppDate.day(from: e) {
            if Calendar.current.isDateInToday(d) { return String(localized: "Today") }
            if Calendar.current.isDateInTomorrow(d) { return String(localized: "Tomorrow") }
            return AppDate.monthDay.string(from: d)
        }
        return expectedDisplay
    }

    /// The live status phrase to show while tracked ("In transit", "Out for
    /// delivery"…), or nil to fall back to the manual status pill. The single
    /// source of truth for live-status wording — every screen renders these
    /// labels from here, one localized entry per aggregator status.
    var liveStatusLabel: String? {
        guard let live = liveStatus else { return nil }
        switch live {
        case "pending":              return String(localized: "deliv_live_pending")
        case "info_received":        return String(localized: "deliv_live_info")
        case "in_transit":           return String(localized: "deliv_live_transit")
        case "out_for_delivery":     return String(localized: "Out for delivery")
        case "available_for_pickup": return String(localized: "deliv_live_pickup")
        case "delivered":            return String(localized: "Delivered")
        case "failed_attempt":       return String(localized: "deliv_live_failed")
        case "exception":            return String(localized: "deliv_live_exception")
        case "expired":              return String(localized: "deliv_live_expired")
        default:                     return nil
        }
    }

    var expectedDisplay: String? {
        guard let ds = expectedDate else { return nil }
        guard let d = AppDate.day(from: ds) else { return ds }
        if Calendar.current.isDateInToday(d) { return String(localized: "Today") }
        if Calendar.current.isDateInTomorrow(d) { return String(localized: "Tomorrow") }
        return AppDate.monthDay.string(from: d)
    }

    static var statusOptions: [(id: String, label: String)] {[
        ("expected",         String(localized: "Expected")),
        ("out_for_delivery", String(localized: "Out for delivery")),
        ("delivered",        String(localized: "Delivered")),
        ("missed",           String(localized: "Missed")),
        ("returned",         String(localized: "Returned")),
    ]}

    static let carrierOptions = ["DHL","FedEx","UPS","DPD","GLS","Cargus","Fan Courier","Sameday","Urgent Cargus","Poșta Română","Altul"]

    /// Best-effort carrier from a tracking number's format — but only when the
    /// format is DISTINCTIVE enough to be sure. Ambiguous all-numeric codes
    /// (most Romanian couriers) return nil rather than a wrong guess, so the
    /// prefill never misleads.
    static func detectCarrier(from raw: String) -> String? {
        let t = raw.uppercased().filter { !$0.isWhitespace }
        guard t.count >= 8 else { return nil }
        // UPS: "1Z" + 16 alphanumerics.
        if t.range(of: "^1Z[0-9A-Z]{16}$", options: .regularExpression) != nil { return "UPS" }
        // DHL express / eCommerce prefixes.
        if t.hasPrefix("JJD") || t.hasPrefix("JD") || t.hasPrefix("GM") { return "DHL" }
        // Universal Postal Union S10 ending in RO → Poșta Română.
        if t.range(of: "^[A-Z]{2}[0-9]{9}RO$", options: .regularExpression) != nil { return "Poșta Română" }
        return nil
    }
}

/// What kind of code a parcel reference looks like — drives the label shown
/// next to it, nothing more.
enum DeliveryReferenceKind {
    case awb, order, other

    var label: String {
        switch self {
        case .awb:   return String(localized: "deliv_ref_awb")
        case .order: return String(localized: "deliv_ref_order")
        case .other: return String(localized: "deliv_ref_other")
        }
    }
}

/// One shipping email that mentioned this parcel. Shape matches the JSON the
/// email importer appends to `packages.source_emails`.
struct DeliverySourceEmail: Codable, Hashable, Identifiable {
    var at: String?
    var from: String?
    var subject: String?

    var id: String { "\(at ?? "")-\(subject ?? "")" }
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
