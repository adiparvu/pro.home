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

    var categoryIcon: String {
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

    var categoryColor: Color {
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
    static let isoDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
