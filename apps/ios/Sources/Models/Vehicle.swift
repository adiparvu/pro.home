import SwiftUI

// MARK: - Vehicles ("Garajul familiei")
//
// The household's cars as first-class citizens: identity, the three deadlines
// every RO/BE owner juggles (ITP/inspection, insurance, vignette), a market
// value that folds into net worth, and expenses linked through the ledger's
// tags ("vehicle:<uuid>") — the same anchoring pattern the appliance service
// book uses.

struct Vehicle: Identifiable, Codable, Hashable {
    let id: UUID
    let propertyId: UUID
    var name: String
    var make: String?
    var model: String?
    var plate: String?
    var year: Int?
    var vin: String?
    var fuelType: String?
    var value: Double?
    var currency: String
    var itpExpires: String?         // "YYYY-MM-DD"
    var insuranceExpires: String?
    var vignetteExpires: String?
    var notes: String?
    var createdBy: UUID?
    let createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, make, model, plate, year, vin, value, currency, notes
        case propertyId       = "property_id"
        case fuelType         = "fuel_type"
        case itpExpires       = "itp_expires"
        case insuranceExpires = "insurance_expires"
        case vignetteExpires  = "vignette_expires"
        case createdBy        = "created_by"
        case createdAt        = "created_at"
        case updatedAt        = "updated_at"
    }

    /// "Dacia Duster · B 123 ABC" — the compact identity line.
    var subtitle: String {
        [
            [make, model].compactMap { $0 }.joined(separator: " "),
            plate ?? ""
        ].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The tag that anchors ledger rows (fuel, service, parts) to this car.
    var ledgerTag: String { "vehicle:\(id.uuidString)" }
}

/// The three dated obligations, in the order an owner checks them.
enum VehicleDeadline: String, CaseIterable, Identifiable {
    case itp, insurance, vignette
    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .itp:       return "vehicle_itp"
        case .insurance: return "vehicle_insurance"
        case .vignette:  return "vehicle_vignette"
        }
    }

    var icon: String {
        switch self {
        case .itp:       return "checkmark.seal.fill"
        case .insurance: return "shield.fill"
        case .vignette:  return "road.lanes"
        }
    }

    func date(of vehicle: Vehicle) -> Date? {
        let raw: String?
        switch self {
        case .itp:       raw = vehicle.itpExpires
        case .insurance: raw = vehicle.insuranceExpires
        case .vignette:  raw = vehicle.vignetteExpires
        }
        return raw.flatMap { AppDate.day(from: $0) }
    }

    /// Urgency tint from real days-left: red inside a week, orange inside a
    /// month, calm otherwise.
    static func tint(daysLeft: Int) -> Color {
        if daysLeft < 0 { return .brandDanger }
        if daysLeft <= 7 { return .brandDanger }
        if daysLeft <= 30 { return .brandWarning }
        return .brandSuccess
    }
}
