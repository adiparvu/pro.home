import Foundation

/// A household's own calendar event (Calendar C2). Dates are the SAME wall-clock
/// wire strings the app already uses for task due dates — "yyyy-MM-dd" for an
/// all-day event, "yyyy-MM-dd HH:mm" for a timed one — so `HouseAgenda` parses
/// them through the one `AppDate` authority with no timezone surprise.
struct CalendarEvent: Identifiable, Codable {
    let id: UUID
    let propertyId: UUID
    var title: String
    var notes: String?
    var startsAt: String
    var endsAt: String?
    var allDay: Bool
    /// Optional brand-token name (e.g. "brandPurple") for a per-event accent.
    var color: String?
    var location: String?
    let createdBy: UUID?
    let createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, notes, color, location
        case propertyId = "property_id"
        case startsAt    = "starts_at"
        case endsAt      = "ends_at"
        case allDay      = "all_day"
        case createdBy   = "created_by"
        case createdAt   = "created_at"
        case updatedAt   = "updated_at"
    }

    /// The parsed start day/time (nil only if the stored string is malformed).
    var startDate: Date? { AppDate.day(from: startsAt) }
}
