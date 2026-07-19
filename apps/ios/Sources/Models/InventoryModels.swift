import Foundation
import SwiftUI
import CoreLocation

// Used by InventoryItem.qrContent.
// Points at the web app's public item page (https://xparvu.com/i/<id>) rather
// than a Supabase Edge Function: functions on the shared *.supabase.co domain
// are forced to text/plain with a sandbox CSP, so their HTML shows as source
// instead of rendering. The web page renders normally and reads the public
// `public_items` projection.
private let itemFoundBaseURL = "https://xparvu.com/i"

// MARK: - PublicProfile

struct PublicProfile: Codable {
    var ownerName: String = ""
    var ownerPhone: String = ""
    var ownerAddress: String = ""
    var propertyName: String = ""
    var isEnabled: Bool = true
}

// MARK: - LoanRecord

struct LoanRecord: Identifiable, Codable {
    var id: UUID = UUID()
    var borrowerName: String
    var loanedAt: Date = Date()
    var expectedReturnDate: Date?
    var returnedAt: Date?
    var isReturned: Bool { returnedAt != nil }
    var daysOut: Int { Calendar.current.dateComponents([.day], from: loanedAt, to: returnedAt ?? Date()).day ?? 0 }
}

extension LoanRecord {
    /// Seconds past the promised return DAY — the promised date itself is
    /// grace (the list's long-standing convention: overdue starts the
    /// following midnight). nil = returned / on time / no promise made.
    var overdueInterval: TimeInterval? {
        guard returnedAt == nil, let due = expectedReturnDate else { return nil }
        let deadline = Calendar.current.startOfDay(for: due).addingTimeInterval(86_400)
        let elapsed = Date().timeIntervalSince(deadline)
        return elapsed > 0 ? elapsed : nil
    }
}

/// The escalating overdue ladder (user-decreed buckets, IMG_8635):
/// 1h · 1d · 3d · 7d · 14d · 30d · 90d · 180d · 1y — the longer a loan
/// sits past its promised return, the hotter its row reads.
enum LoanOverdueTier: Int, CaseIterable {
    case justPassed, hours, oneDay, threeDays, oneWeek, twoWeeks
    case oneMonth, threeMonths, sixMonths, oneYear

    init(overdueBy interval: TimeInterval) {
        let hour: TimeInterval = 3_600, day: TimeInterval = 86_400
        switch interval {
        case ..<hour:        self = .justPassed
        case ..<day:         self = .hours
        case ..<(3 * day):   self = .oneDay
        case ..<(7 * day):   self = .threeDays
        case ..<(14 * day):  self = .oneWeek
        case ..<(30 * day):  self = .twoWeeks
        case ..<(90 * day):  self = .oneMonth
        case ..<(180 * day): self = .threeMonths
        case ..<(365 * day): self = .sixMonths
        default:             self = .oneYear
        }
    }

    /// Yellow → amber → oranges → reds → deep crimson → violet: one hue
    /// ramp, hotter with every bucket, legible on both schemes.
    var color: Color {
        switch self {
        case .justPassed:  Color(red: 0.93, green: 0.78, blue: 0.10)
        case .hours:       Color(red: 1.00, green: 0.70, blue: 0.00)
        case .oneDay:      Color(red: 1.00, green: 0.55, blue: 0.00)
        case .threeDays:   Color(red: 1.00, green: 0.40, blue: 0.10)
        case .oneWeek:     Color(red: 0.95, green: 0.27, blue: 0.20)
        case .twoWeeks:    Color(red: 0.88, green: 0.12, blue: 0.15)
        case .oneMonth:    Color(red: 0.75, green: 0.05, blue: 0.12)
        case .threeMonths: Color(red: 0.62, green: 0.00, blue: 0.16)
        case .sixMonths:   Color(red: 0.50, green: 0.00, blue: 0.28)
        case .oneYear:     Color(red: 0.38, green: 0.00, blue: 0.42)
        }
    }
}

// MARK: - InventoryItem

struct InventoryItem: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var category: String = "tools"
    var location: String = "garage"
    var brand: String = ""
    var serialNumber: String = ""
    var purchaseDate: Date?
    var purchasePrice: Double = 0
    var warrantyExpiresAt: Date?
    var condition: String = "good"
    var notes: String = ""
    var currentLoan: LoanRecord?
    var loanHistory: [LoanRecord] = []
    var publicProfile: PublicProfile?
    var latitude: Double?
    var longitude: Double?
    var trackerType: String = ""
    var trackerIdentifier: String = ""
    var elementId: UUID? = nil

    var hasLocation: Bool { latitude != nil && longitude != nil }
    var isLoaned: Bool { currentLoan != nil }
    var qrContent: String { "\(itemFoundBaseURL)/\(id.uuidString)" }

    var warrantyStatus: WarrantyStatus {
        guard let exp = warrantyExpiresAt else { return .none }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: exp).day ?? 0
        if days < 0 { return .expired }
        if days <= 30 { return .expiringSoon }
        return .valid
    }

    enum WarrantyStatus { case none, valid, expiringSoon, expired }

    var categoryIcon: String { InventoryCatalog.icon(for: category) }
    var categoryColor: Color { InventoryCatalog.color(for: category) }
}

// MARK: - Category / location vocabulary
//
// The canonical value lists the add form, the filter chips and the PDF report
// all share — one source of truth instead of per-view copies.

enum InventoryCatalog {
    static let categories = ["tools", "garden", "outdoor", "appliances", "electronics",
                             "furniture", "vehicles", "sports", "security", "other"]
    static let locations = ["garage", "garden", "basement", "attic", "shed",
                            "balcony", "kitchen", "living room", "bedroom", "storage"]
    static let conditions = ["excellent", "good", "fair", "poor"]

    static func icon(for category: String) -> String {
        switch category {
        case "tools":       return "wrench.and.screwdriver.fill"
        case "garden":      return "leaf.fill"
        case "outdoor":     return "sun.max.fill"
        case "appliances":  return "washer.fill"
        case "electronics": return "tv.fill"
        case "furniture":   return "sofa.fill"
        case "vehicles":    return "car.fill"
        case "sports":      return "figure.run"
        case "security":    return "lock.shield.fill"
        default:            return "cube.fill"
        }
    }

    static func color(for category: String) -> Color {
        switch category {
        case "tools":       return .orange
        case "garden":      return Color(red: 0.2, green: 0.8, blue: 0.3)
        case "outdoor":     return .yellow
        case "appliances":  return .blue
        case "electronics": return .purple
        case "furniture":   return Color(red: 0.7, green: 0.5, blue: 0.3)
        case "vehicles":    return .red
        case "sports":      return .cyan
        case "security":    return Color.brandSuccess
        default:            return .gray
        }
    }
}

// MARK: - Localized labels for stored raw values
//
// Categories localize through their capitalized catalog key ("tools" →
// "Tools"). Locations only uppercase the first letter — `.capitalized` would
// turn "living room" into the key "Living Room", which doesn't exist.

enum InventoryLabels {
    static func category(_ raw: String) -> String {
        String(localized: String.LocalizationValue(raw.capitalized))
    }

    static func location(_ raw: String) -> String {
        guard let first = raw.first else { return raw }
        return String(localized: String.LocalizationValue(first.uppercased() + raw.dropFirst()))
    }
}

extension [InventoryItem] {
    /// Distinct borrower names from every loan on record (current first,
    /// then history), newest data first — real names the household actually
    /// lends to, offered as one-tap suggestions.
    var recentBorrowers: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for item in self {
            let names = (item.currentLoan.map { [$0] } ?? []) + item.loanHistory.reversed()
            for loan in names {
                let name = loan.borrowerName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { continue }
                out.append(name)
            }
        }
        return out
    }
}

// MARK: - DB-mapped types

struct InventoryMetadata: Codable {
    var location: String = "garage"
    var currentLoan: LoanRecord? = nil
    var loanHistory: [LoanRecord] = []
    var publicProfile: PublicProfile? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
    var trackerType: String = ""
    var trackerIdentifier: String = ""
    var elementId: UUID? = nil
}

struct DBInventoryRecord: Codable {
    var id: UUID
    var name: String
    var brand: String?
    var serialNumber: String?
    var category: String?
    var condition: String?
    var purchaseDate: String?
    var purchasePrice: Double?
    var warrantyExpires: String?
    var notes: String?
    var metadata: InventoryMetadata

    enum CodingKeys: String, CodingKey {
        case id, name, brand, category, condition, notes, metadata
        case serialNumber  = "serial_number"
        case purchaseDate  = "purchase_date"
        case purchasePrice = "purchase_price"
        case warrantyExpires = "warranty_expires"
    }

    func toInventoryItem() -> InventoryItem {
        var item = InventoryItem(id: id, name: name)
        item.brand = brand ?? ""
        item.serialNumber = serialNumber ?? ""
        item.category = category ?? "tools"
        item.condition = condition ?? "good"
        item.purchaseDate = purchaseDate.flatMap { DateFormatter.isoDate.date(from: $0) }
        item.purchasePrice = purchasePrice ?? 0
        item.warrantyExpiresAt = warrantyExpires.flatMap { DateFormatter.isoDate.date(from: $0) }
        item.notes = notes ?? ""
        item.location = metadata.location
        item.currentLoan = metadata.currentLoan
        item.loanHistory = metadata.loanHistory
        item.publicProfile = metadata.publicProfile
        item.latitude = metadata.latitude
        item.longitude = metadata.longitude
        item.trackerType = metadata.trackerType
        item.trackerIdentifier = metadata.trackerIdentifier
        item.elementId = metadata.elementId
        return item
    }
}

struct NewInventoryItem: Encodable {
    let propertyId: UUID
    let name: String
    let brand: String?
    let serialNumber: String?
    let category: String?
    let condition: String?
    let purchaseDate: String?
    let purchasePrice: Double?
    let warrantyExpires: String?
    let notes: String?
    let metadata: InventoryMetadata
    let addedBy: UUID?

    enum CodingKeys: String, CodingKey {
        case name, brand, category, condition, notes, metadata
        case propertyId    = "property_id"
        case serialNumber  = "serial_number"
        case purchaseDate  = "purchase_date"
        case purchasePrice = "purchase_price"
        case warrantyExpires = "warranty_expires"
        case addedBy = "added_by"
    }
}

struct UpdateInventoryPayload: Encodable {
    let name: String
    let brand: String?
    let serialNumber: String?
    let category: String?
    let condition: String?
    let purchaseDate: String?
    let purchasePrice: Double?
    let warrantyExpires: String?
    let notes: String?
    let metadata: InventoryMetadata

    enum CodingKeys: String, CodingKey {
        case name, brand, category, condition, notes, metadata
        case serialNumber  = "serial_number"
        case purchaseDate  = "purchase_date"
        case purchasePrice = "purchase_price"
        case warrantyExpires = "warranty_expires"
    }
}

extension InventoryItem {
    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    func toNew(propertyId: UUID, addedBy: UUID?) -> NewInventoryItem {
        NewInventoryItem(
            propertyId: propertyId, name: name,
            brand: brand.isEmpty ? nil : brand,
            serialNumber: serialNumber.isEmpty ? nil : serialNumber,
            category: category, condition: condition,
            purchaseDate: purchaseDate.map { DateFormatter.isoDate.string(from: $0) },
            purchasePrice: purchasePrice > 0 ? purchasePrice : nil,
            warrantyExpires: warrantyExpiresAt.map { DateFormatter.isoDate.string(from: $0) },
            notes: notes.isEmpty ? nil : notes,
            metadata: inventoryMetadata, addedBy: addedBy
        )
    }

    func toUpdatePayload() -> UpdateInventoryPayload {
        UpdateInventoryPayload(
            name: name,
            brand: brand.isEmpty ? nil : brand,
            serialNumber: serialNumber.isEmpty ? nil : serialNumber,
            category: category, condition: condition,
            purchaseDate: purchaseDate.map { DateFormatter.isoDate.string(from: $0) },
            purchasePrice: purchasePrice > 0 ? purchasePrice : nil,
            warrantyExpires: warrantyExpiresAt.map { DateFormatter.isoDate.string(from: $0) },
            notes: notes.isEmpty ? nil : notes,
            metadata: inventoryMetadata
        )
    }

    private var inventoryMetadata: InventoryMetadata {
        InventoryMetadata(location: location, currentLoan: currentLoan, loanHistory: loanHistory,
                          publicProfile: publicProfile, latitude: latitude, longitude: longitude,
                          trackerType: trackerType, trackerIdentifier: trackerIdentifier,
                          elementId: elementId)
    }
}

extension DateFormatter {
    /// The wire-format day formatter — one shared instance via `AppDate`,
    /// so the POSIX locale + Gregorian calendar pinning lives in one place.
    static let isoDate: DateFormatter = AppDate.day
}
