// Subject-line support for chat messages — the iMessage "Show Subject Field"
// feature (Settings → Messages → Show Subject Field), for the family chat and
// DMs only (AI surfaces never see it).
//
// A message with a subject travels INSIDE the existing plain-text `body`
// column — no schema change — as:
//
//     {subject}\u{1E}{text}
//
// U+001E is the ASCII *record separator*: a control character no keyboard can
// type and no font renders, so it can never collide with anything a person
// writes (unlike "**…**\n" or a dash rule, which are typeable). Messages
// without the marker — every message ever sent before this feature — parse to
// (subject: nil, text: body) and render exactly as before. Any surface that
// shows a raw body in a single line (previews, snippets, copy, export) must
// pass it through `strip(_:)` so the control character never reaches a label.
import Foundation

enum MessageSubject {
    /// U+001E, the ASCII record separator — untypeable, invisible, safe.
    static let separator: Character = "\u{1E}"

    /// UserDefaults key for the "Show Subject Field" toggle (Chat Settings).
    /// Default OFF. Shared by ChatSettingsView, ChatView and DirectMessageView.
    static let showFieldDefaultsKey = "prvio.chat.showSubjectField"

    /// Encodes a subject + message text into one body. A blank subject yields
    /// the text unchanged (no marker) — a plain message, like today.
    static func encode(subject: String, text: String) -> String {
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        return trimmed + String(separator) + text
    }

    /// Splits a body into its subject and text. Marker-free bodies (all
    /// pre-existing messages) come back as (nil, body), unchanged.
    static func parse(_ body: String) -> (subject: String?, text: String) {
        guard let idx = body.firstIndex(of: separator) else { return (nil, body) }
        let subject = String(body[..<idx])
        let text = String(body[body.index(after: idx)...])
        // A degenerate leading marker is treated as plain text, not a subject.
        guard !subject.isEmpty else { return (nil, text) }
        return (subject, text)
    }

    /// One-line rendering for previews, reply/pin snippets, copy and export:
    /// the marker becomes "subject — text" so no content is lost and the
    /// control character never reaches a label. Marker-free bodies come back
    /// unchanged (the overwhelmingly common case — one contains() and out).
    static func strip(_ body: String) -> String {
        guard body.contains(separator) else { return body }
        let (subject, text) = parse(body)
        guard let subject else { return text }
        guard !text.isEmpty else { return subject }
        return "\(subject) — \(text)"
    }
}
