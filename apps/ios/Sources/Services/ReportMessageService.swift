import Foundation
import SwiftUI
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

/// What the long-press action captures for the reason dialog.
struct ReportTarget: Identifiable {
    let id = UUID()
    let messageId: UUID
    let propertyId: UUID?
    /// "group" | "dm"
    let kind: String
    let snapshot: String?
}

// MARK: - The reason dialog + outcome alert, as ONE cheap modifier
//
// Both chat surfaces attach this instead of inlining the dialogs: their
// bodies already sit at the edge of what the type-checker will take, and
// the inline version pushed ChatView/DirectMessageView over it (the 1076
// "unable to type-check in reasonable time" red).

struct ReportMessageDialogs: ViewModifier {
    @Binding var target: ReportTarget?
    @Binding var outcome: String?

    private static let reasons = ["report_spam", "report_abuse", "report_other"]

    func body(content: Content) -> some View {
        content
            .confirmationDialog("report_reason_title",
                                isPresented: presented,
                                titleVisibility: .visible) {
                reasonButtons
            }
            .alert(outcome ?? "", isPresented: outcomePresented) {
                Button("OK", role: .cancel) { outcome = nil }
            }
    }

    private var presented: Binding<Bool> {
        Binding(get: { target != nil },
                set: { if !$0 { target = nil } })
    }

    private var outcomePresented: Binding<Bool> {
        Binding(get: { outcome != nil },
                set: { if !$0 { outcome = nil } })
    }

    @ViewBuilder private var reasonButtons: some View {
        ForEach(Self.reasons, id: \.self) { key in
            Button(LocalizedStringKey(key)) { file(reasonKey: key) }
        }
        Button("Cancel", role: .cancel) { target = nil }
    }

    private func file(reasonKey: String) {
        guard let t = target else { return }
        target = nil
        Task { @MainActor in
            do {
                try await ReportMessageService.report(
                    messageId: t.messageId,
                    propertyId: t.propertyId,
                    kind: t.kind,
                    reason: String(localized: String.LocalizationValue(reasonKey)),
                    snapshot: t.snapshot)
                outcome = String(localized: "report_sent")
            } catch {
                outcome = String(localized: "report_failed")
            }
        }
    }
}

extension View {
    /// UGC report flow (Guideline 1.2): reason picker + honest outcome alert.
    func reportMessageDialogs(target: Binding<ReportTarget?>,
                              outcome: Binding<String?>) -> some View {
        modifier(ReportMessageDialogs(target: target, outcome: outcome))
    }
}
