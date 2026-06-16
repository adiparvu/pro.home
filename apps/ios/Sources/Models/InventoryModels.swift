import Foundation
import SwiftUI

// Used by InventoryItem.qrContent
private let itemFoundBaseURL = "https://kwcanenheihuylaymwsl.supabase.co/functions/v1/item-found"

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

    var hasLocation: Bool { latitude != nil && longitude != nil }
    var isLoaned: Bool { currentLoan != nil }
    var qrContent: String { "\(itemFoundBaseURL)?id=\(id.uuidString)" }

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
        case "security":    return Color(red: 0.3, green: 0.85, blue: 0.5)
        default:            return .gray
        }
    }
}

// MARK: - InventoryMapPin

struct InventoryMapPin: Identifiable {
    let id = UUID()
    let lat: Double
    let lon: Double
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}
