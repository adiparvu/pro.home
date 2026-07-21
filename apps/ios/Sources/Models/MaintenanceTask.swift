import SwiftUI

struct MaintenanceTask: Identifiable, Codable, Equatable {
    let id: UUID
    let propertyId: UUID
    var title: String
    var description: String?
    var category: String
    var priority: String
    var status: String
    var dueDate: String?
    var estimatedCost: Double?
    var costCurrency: String?
    var notes: String?
    var tags: [String]
    let createdAt: String
    var updatedAt: String

    var assigneeIds: [String]
    var assigneeNames: [String]
    var elementId: UUID?
    /// Total seconds banked by the work-session timer. Defaulted so it decodes
    /// whether or not the `worked_seconds` column (migration 136) has shipped —
    /// the local App Group total is the authority until then.
    var workedSeconds: Int = 0
    /// Photos attached to the task (public URLs, documents bucket) and the
    /// place it happens — a free-typed name or an Apple Maps pick (name +
    /// coordinates). All tolerant-decoded: rows predate migration 147.
    var photoUrls: [String] = []
    var locationName: String?
    var locationLat: Double?
    var locationLon: Double?
    /// Repeat interval in days (predictive phase 2); nil = one-off.
    /// Completing a recurring task spawns its next occurrence client-side.
    var recurrenceDays: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, description, category, priority, status, notes, tags
        case propertyId    = "property_id"
        case dueDate       = "due_date"
        case estimatedCost = "estimated_cost"
        case costCurrency  = "cost_currency"
        case createdAt     = "created_at"
        case updatedAt     = "updated_at"
        case assigneeIds   = "assignee_ids"
        case assigneeNames = "assignee_names"
        case elementId     = "element_id"
        case workedSeconds = "worked_seconds"
        case photoUrls     = "photo_urls"
        case locationName  = "location_name"
        case locationLat   = "location_lat"
        case locationLon   = "location_lon"
        case recurrenceDays = "recurrence_days"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(UUID.self,    forKey: .id)
        propertyId     = try c.decode(UUID.self,    forKey: .propertyId)
        title          = try c.decode(String.self,  forKey: .title)
        description    = try c.decodeIfPresent(String.self,  forKey: .description)
        category       = try c.decode(String.self,  forKey: .category)
        priority       = try c.decode(String.self,  forKey: .priority)
        status         = try c.decode(String.self,  forKey: .status)
        dueDate        = try c.decodeIfPresent(String.self,  forKey: .dueDate)
        estimatedCost  = try c.decodeIfPresent(Double.self,  forKey: .estimatedCost)
        costCurrency   = try c.decodeIfPresent(String.self,  forKey: .costCurrency)
        notes          = try c.decodeIfPresent(String.self,  forKey: .notes)
        tags           = (try? c.decode([String].self, forKey: .tags)) ?? []
        createdAt      = try c.decode(String.self,  forKey: .createdAt)
        updatedAt      = try c.decode(String.self,  forKey: .updatedAt)
        assigneeIds    = (try? c.decode([String].self, forKey: .assigneeIds))   ?? []
        assigneeNames  = (try? c.decode([String].self, forKey: .assigneeNames)) ?? []
        elementId      = try c.decodeIfPresent(UUID.self, forKey: .elementId)
        workedSeconds  = (try? c.decode(Int.self, forKey: .workedSeconds)) ?? 0
        photoUrls      = (try? c.decode([String].self, forKey: .photoUrls)) ?? []
        locationName   = try? c.decodeIfPresent(String.self, forKey: .locationName)
        locationLat    = try? c.decodeIfPresent(Double.self, forKey: .locationLat)
        locationLon    = try? c.decodeIfPresent(Double.self, forKey: .locationLon)
        recurrenceDays = try? c.decodeIfPresent(Int.self, forKey: .recurrenceDays)
    }

    var isCompleted: Bool { status == "completed" }

    var isOverdue: Bool {
        guard let ds = dueDate, !isCompleted, status != "cancelled" else { return false }
        guard let d = MaintenanceTask.parseDate(ds) else { return false }
        return d < Calendar.current.startOfDay(for: Date())
    }

    var dueDateDisplay: String {
        guard let ds = dueDate else { return String(localized: "No date") }
        guard let d = MaintenanceTask.parseDate(ds) else { return ds }
        return (ds.count > 10 ? AppDate.monthDayTime : AppDate.monthDay).string(from: d)
    }

    static func parseDate(_ ds: String) -> Date? {
        AppDate.day(from: ds)
    }

    var priorityColor: Color {
        switch priority {
        case "critical": return Color.brandDanger
        case "high":     return .orange
        case "medium":   return Color(red: 1, green: 0.85, blue: 0.25)
        default:         return Color(red: 0.3, green: 0.9, blue: 0.5)
        }
    }

    var statusDisplay: String {
        switch status {
        case "in_progress": return String(localized: "In Progress")
        case "completed":   return String(localized: "Done")
        case "cancelled":   return String(localized: "Cancelled")
        case "overdue":     return String(localized: "Overdue")
        default:            return String(localized: "Pending")
        }
    }
}

struct NewTaskPayload: Encodable {
    let propertyId: UUID
    let title: String
    let description: String?
    let dueDate: String?
    let priority: String
    let category: String
    let status: String = "pending"
    let assigneeIds: [String]
    let assigneeNames: [String]
    // Defaulted so pre-existing call sites (watch quick-add, intents) build on.
    var photoUrls: [String] = []
    var locationName: String? = nil
    var locationLat: Double? = nil
    var locationLon: Double? = nil
    var recurrenceDays: Int? = nil

    enum CodingKeys: String, CodingKey {
        case propertyId    = "property_id"
        case title, description
        case dueDate       = "due_date"
        case priority, category, status
        case assigneeIds   = "assignee_ids"
        case assigneeNames = "assignee_names"
        case photoUrls     = "photo_urls"
        case locationName  = "location_name"
        case locationLat   = "location_lat"
        case locationLon   = "location_lon"
        case recurrenceDays = "recurrence_days"
    }
}

struct TaskStatusUpdate: Encodable {
    let status: String
    let updatedAt: String
    enum CodingKeys: String, CodingKey {
        case status; case updatedAt = "updated_at"
    }
}
