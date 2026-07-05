import Foundation
import Observation
import Supabase

// MARK: - ScheduledMessage model

/// One "Send Later" row. Delivery itself happens server-side (a pg_cron job
/// posts due messages every minute) — the app only creates, lists, and
/// cancels schedules, so the model mirrors the table verbatim.
struct ScheduledMessage: Identifiable, Codable {
    let id: UUID
    let propertyId: UUID
    let authorId: UUID
    let authorName: String
    /// "group" or "dm".
    let target: String
    /// Partner name when `target == "dm"`.
    let dmRecipient: String?
    var body: String
    var nextSendAt: String
    /// "once" | "daily" | "weekly" | "monthly".
    var repeatRule: String
    var repeatUntil: String?
    var active: Bool
    var lastSentAt: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, target, body, active
        case propertyId  = "property_id"
        case authorId    = "author_id"
        case authorName  = "author_name"
        case dmRecipient = "dm_recipient"
        case nextSendAt  = "next_send_at"
        case repeatRule  = "repeat_rule"
        case repeatUntil = "repeat_until"
        case lastSentAt  = "last_sent_at"
        case createdAt   = "created_at"
    }

    var nextSendDate: Date? { ISODate.date(from: nextSendAt) }
    var repeatUntilDate: Date? { repeatUntil.flatMap { ISODate.date(from: $0) } }
    var repeats: Bool { repeatRule != "once" }
}

// MARK: - ScheduledMessageService

/// CRUD for `scheduled_messages`. RLS restricts every operation to the
/// author's own rows, so all queries implicitly mean "my schedules".
@MainActor
@Observable
final class ScheduledMessageService {
    /// Active schedules for the conversation last loaded, ordered by next send.
    var items: [ScheduledMessage] = []
    var isLoading = false
    var error: String?

    /// Loads the caller's active schedules for one conversation:
    /// the property's group chat, or one DM thread when `target == "dm"`.
    func load(propertyId: UUID, target: String, dmRecipient: String?) async {
        isLoading = true
        defer { isLoading = false }
        do {
            var query = supabase
                .from("scheduled_messages")
                .select()
                .eq("property_id", value: propertyId.uuidString)
                .eq("target", value: target)
                .eq("active", value: true)
            if target == "dm", let dmRecipient {
                query = query.eq("dm_recipient", value: dmRecipient)
            }
            items = try await query
                .order("next_send_at", ascending: true)
                .execute()
                .value
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Creates a schedule and reflects it locally (kept sorted by next send).
    /// Throws so the caller can surface the failure in its own alert.
    func schedule(propertyId: UUID, authorId: UUID, authorName: String,
                  target: String, dmRecipient: String?, body: String,
                  firstSendAt: Date, repeatRule: String, repeatUntil: Date?) async throws {
        struct Payload: Encodable {
            let property_id: String
            let author_id: String
            let author_name: String
            let target: String
            let dm_recipient: String?
            let body: String
            let next_send_at: String
            let repeat_rule: String
            let repeat_until: String?
        }
        let created: ScheduledMessage = try await supabase
            .from("scheduled_messages")
            .insert(Payload(
                property_id: propertyId.uuidString,
                author_id: authorId.uuidString,
                author_name: authorName,
                target: target,
                dm_recipient: target == "dm" ? dmRecipient : nil,
                body: body,
                next_send_at: ISODate.plain.string(from: firstSendAt),
                repeat_rule: repeatRule,
                repeat_until: repeatUntil.map { ISODate.plain.string(from: $0) }
            ))
            .select()
            .single()
            .execute()
            .value
        items.append(created)
        items.sort { ($0.nextSendDate ?? .distantFuture) < ($1.nextSendDate ?? .distantFuture) }
    }

    /// Cancels a schedule. The row is deleted outright (not just deactivated):
    /// the cron worker owns `active`, and a cancelled schedule has no value
    /// as history. Local removal only happens after the delete lands.
    func cancel(_ item: ScheduledMessage) async {
        do {
            try await supabase
                .from("scheduled_messages")
                .delete()
                .eq("id", value: item.id.uuidString)
                .execute()
            items.removeAll { $0.id == item.id }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
