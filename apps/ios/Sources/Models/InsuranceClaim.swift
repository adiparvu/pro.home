import SwiftUI

// MARK: - Damage claims ("Asistent de daune")
//
// One row per incident, tracked from draft to resolution. The claimed and
// approved amounts stay separate columns — hope and money are different
// things, and the ledger only ever sees what the insurer actually paid.

enum ClaimStatus: String, CaseIterable, Identifiable {
    case draft, submitted, inReview = "in_review", resolved
    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .draft:     return "claim_status_draft"
        case .submitted: return "claim_status_submitted"
        case .inReview:  return "claim_status_in_review"
        case .resolved:  return "claim_status_resolved"
        }
    }

    var icon: String {
        switch self {
        case .draft:     return "pencil.circle.fill"
        case .submitted: return "paperplane.circle.fill"
        case .inReview:  return "clock.badge.questionmark.fill"
        case .resolved:  return "checkmark.seal.fill"
        }
    }

    var tint: Color {
        switch self {
        case .draft:     return .secondaryTextColor
        case .submitted: return .brandPrimaryBlue
        case .inReview:  return .brandWarning
        case .resolved:  return .brandSuccess
        }
    }

    /// A claim's natural forward order.
    var order: Int {
        switch self {
        case .draft: return 0
        case .submitted: return 1
        case .inReview: return 2
        case .resolved: return 3
        }
    }
}

struct InsuranceClaim: Identifiable, Codable, Hashable {
    let id: UUID
    let propertyId: UUID
    var title: String
    var description: String?
    var incidentDate: String        // "YYYY-MM-DD"
    var insurer: String?
    var policyNumber: String?
    var status: String
    var claimedAmount: Double?
    var approvedAmount: Double?
    var currency: String
    var photoUrls: [String]
    var notes: String?
    var createdBy: UUID?
    let createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, description, insurer, status, currency, notes
        case propertyId     = "property_id"
        case incidentDate   = "incident_date"
        case policyNumber   = "policy_number"
        case claimedAmount  = "claimed_amount"
        case approvedAmount = "approved_amount"
        case photoUrls      = "photo_urls"
        case createdBy      = "created_by"
        case createdAt      = "created_at"
        case updatedAt      = "updated_at"
    }

    var statusKind: ClaimStatus { ClaimStatus(rawValue: status) ?? .draft }
    var date: Date? { AppDate.day(from: incidentDate) }
}
