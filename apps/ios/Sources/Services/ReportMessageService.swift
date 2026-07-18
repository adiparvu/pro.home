import Foundation
import Supabase

// MARK: - UGC message reporting (App Store Guideline 1.2)
//
// A chat with user-generated content must let people REPORT a message.
// Reports land in `content_reports` (migration 162): write-only from the
// API — reporters insert their own row, and nothing can read the table
// without the service role, so reports are visible exclusively to the
// moderation side. The body snapshot is captured at report time so
// moderation sees what was reported even if the message is later edited
// or deleted for everyone.

enum ReportMessageService {
    /// Files a report. Throws so callers surface failure honestly —
    /// a report that silently vanishes is worse than none.
    static func report(messageId: UUID,
                       propertyId: UUID?,
                       kind: String,
                       reason: String,
                       snapshot: String?) async throws {
        guard let uid = supabase.auth.currentSession?.user.id else {
            throw NSError(domain: "ReportMessage", code: 1, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "report_failed")])
        }
        struct Row: Encodable {
            let message_id: String
            let property_id: String?
            let message_kind: String
            let reported_by: String
            let reason: String
            let body_snapshot: String?
        }
        try await supabase.from("content_reports").insert(Row(
            message_id: messageId.uuidString,
            property_id: propertyId?.uuidString,
            message_kind: kind,
            reported_by: uid.uuidString,
            reason: reason,
            body_snapshot: snapshot.map { String($0.prefix(500)) }
        )).execute()
    }
}
