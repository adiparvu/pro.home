import Foundation

// MARK: - Server notification localization
//
// Rows in the `notifications` table are written by DB triggers with text
// baked in at insert time — the old triggers (004/006/013) and the weekly
// digest (014) write English, the app-wide generator (111) writes Romanian.
// The device's language can be either, and history can't be rewritten, so
// display-time is the only honest place to localize: the template set is
// finite and known, and anything unrecognized passes through untouched.

enum ServerNotificationLocalizer {

    static func title(_ raw: String) -> String {
        // "Overdue: <task title>" (old English trigger)
        if raw.hasPrefix("Overdue: ") {
            return String(format: String(localized: "srvnotif_overdue_prefix"),
                          String(raw.dropFirst("Overdue: ".count)))
        }
        if let key = exactTitles[raw] { return String(localized: String.LocalizationValue(key)) }
        return raw
    }

    static func body(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return raw }
        // "This task was due Jun 07 and is now overdue."
        if let match = raw.wholeMatch(of: #/This task was due (.+) and is now overdue\./# ) {
            return String(format: String(localized: "srvnotif_overdue_body"), String(match.1))
        }
        if raw.contains("Spent so far this month:") || raw.hasPrefix("All clear") {
            return digestBody(raw)
        }
        return raw
    }

    /// Titles written verbatim by the triggers, in either source language.
    private static let exactTitles: [String: String] = [
        "Your week at a glance":  "srvnotif_digest_title",
        "Task restant":           "srvnotif_task_overdue",
        "Task scadent azi":       "srvnotif_task_due",
        "Plantă de udat":         "srvnotif_plant_water",
        "Colet livrat":           "srvnotif_pkg_delivered",
        "Colet în livrare azi":   "srvnotif_pkg_out",
        "Document care expiră":   "srvnotif_doc_expiring",
        "Garanție care expiră":   "srvnotif_warranty_expiring",
        "Invitație care expiră":  "srvnotif_invite_expiring",
        "Zi de naștere azi":      "srvnotif_birthday",
        "Chiria scadentă azi":    "srvnotif_rent_due",
        "Chiria lunară":          "srvnotif_rent_monthly",
    ]

    /// The digest body is a concatenation of known segments — translate each,
    /// pass anything unrecognized through unchanged.
    private static func digestBody(_ raw: String) -> String {
        var out = raw
        if out.hasPrefix("All clear — no overdue tasks, expiring documents or thirsty plants. ") {
            out = String(localized: "srvnotif_digest_allclear") + " "
                + String(out.dropFirst("All clear — no overdue tasks, expiring documents or thirsty plants. ".count))
        }
        out = replaceCount(in: out, pattern: #/(\d+) tasks? overdue\. /#,
                           one: "srvnotif_digest_overdue_one", many: "srvnotif_digest_overdue_many")
        out = replaceCount(in: out, pattern: #/(\d+) tasks? due this week\. /#,
                           one: "srvnotif_digest_due_one", many: "srvnotif_digest_due_many")
        out = replaceCount(in: out, pattern: #/(\d+) documents? expiring within 30 days\. /#,
                           one: "srvnotif_digest_docs_one", many: "srvnotif_digest_docs_many")
        out = replaceCount(in: out, pattern: #/(\d+) plants? need water\. /#,
                           one: "srvnotif_digest_plants_one", many: "srvnotif_digest_plants_many")
        if let match = out.firstMatch(of: #/Spent so far this month: ([A-Z]{3}) ([\d.,]+)\./# ) {
            out = out.replacingCharacters(
                in: match.range,
                with: String(format: String(localized: "srvnotif_digest_spend"),
                             String(match.1), String(match.2)))
        }
        return out
    }

    private static func replaceCount(in text: String,
                                     pattern: Regex<(Substring, Substring)>,
                                     one: String, many: String) -> String {
        guard let match = text.firstMatch(of: pattern), let n = Int(match.1) else { return text }
        let key = n == 1 ? one : many
        let rendered = String(format: String(localized: String.LocalizationValue(key)), n) + " "
        return text.replacingCharacters(in: match.range, with: rendered)
    }
}
