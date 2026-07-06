import Foundation

/// Shared ISO8601 formatters for server timestamps.
///
/// `ISO8601DateFormatter()` is expensive to initialize, and it was being created
/// fresh on every call across message/timestamp parsing — which runs on every
/// SwiftUI body re-evaluation (every composer keystroke re-filters the whole
/// message list). Reusing these read-only instances removes that allocation
/// from the hot render path. All call sites run on the main actor and never
/// mutate the formatters after configuration, so sharing is safe.
enum ISODate {
    static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Timestamps repeat across renders (every bubble, separator and list row
    /// re-parses its ISO string on each body pass), and ISO8601 parsing is
    /// expensive — memoize. NSCache is thread-safe and drops entries under
    /// memory pressure; ISO strings are immutable so entries never go stale.
    private static let parseCache: NSCache<NSString, NSDate> = {
        let c = NSCache<NSString, NSDate>()
        c.countLimit = 4096
        return c
    }()

    static func date(from s: String) -> Date? {
        if let hit = parseCache.object(forKey: s as NSString) { return hit as Date }
        guard let d = fractional.date(from: s)
                ?? plain.date(from: s)
                ?? normalized(s).flatMap({ fractional.date(from: $0) ?? plain.date(from: $0) })
        else { return nil }
        parseCache.setObject(d as NSDate, forKey: s as NSString)
        return d
    }

    /// Postgres emits shapes `ISO8601DateFormatter` refuses: microsecond
    /// fractions ("…10:00:00.123456+00:00") and offset-less timestamps from
    /// `timestamp without time zone` columns. Trim the fraction to
    /// milliseconds and anchor missing offsets to UTC so every server
    /// timestamp parses through the same door.
    private static func normalized(_ s: String) -> String? {
        var head = s
        var tail = ""
        if let dot = s.firstIndex(of: ".") {
            var idx = s.index(after: dot)
            var fraction = ""
            while idx < s.endIndex, s[idx].isNumber {
                fraction.append(s[idx])
                idx = s.index(after: idx)
            }
            guard !fraction.isEmpty else { return nil }
            head = String(s[..<dot])
            tail = String(s[idx...])
            head += "." + String(fraction.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
        }
        if tail.isEmpty { tail = "Z" }
        let candidate = head + tail
        return candidate == s ? nil : candidate
    }

    /// "HH:mm" — the bubble/row timestamp shown throughout chat (WhatsApp-style).
    static let timeOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

/// The app's one calendar-date authority.
///
/// Every plain-date column in the schema ("yyyy-MM-dd" due dates, lease ends,
/// warranties, record dates) must be parsed and written through these
/// formatters. They pin `en_US_POSIX` + the Gregorian calendar so a device
/// set to a Buddhist, Japanese or Hebrew calendar still round-trips the
/// wire format correctly — a bare `DateFormatter()` silently interprets
/// "yyyy" in the device's era and shifts dates by centuries. The timezone
/// stays the device's own because a due date is a wall-clock day (as in
/// Reminders), not an instant.
///
/// Display formatters live here too: they follow the user's locale via
/// localized templates, and being shared they remove the per-row
/// `DateFormatter()` allocations that previously ran during scrolling.
enum AppDate {
    private static func wireFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = format
        return f
    }

    /// Wire format "yyyy-MM-dd" (Postgres `date` columns).
    static let day = wireFormatter("yyyy-MM-dd")
    /// Legacy task due-dates that carry a wall-clock time.
    static let dayTime = wireFormatter("yyyy-MM-dd HH:mm")
    /// "yyyy-MM" month bucket keys (grouping, dedup keys, chart buckets).
    static let monthKey = wireFormatter("yyyy-MM")
    /// "yyyy" year keys.
    static let yearKey = wireFormatter("yyyy")
    /// "yyyy-ww" week keys (deterministic weekly dedup).
    static let weekKey = wireFormatter("yyyy-ww")

    /// Parses any stored day string: "yyyy-MM-dd", "yyyy-MM-dd HH:mm",
    /// or a full ISO timestamp (falls back to its calendar day).
    static func day(from s: String) -> Date? {
        if s.count > 10 {
            if let d = dayTime.date(from: s) { return d }
            if let d = ISODate.date(from: s) { return d }
        }
        return day.date(from: String(s.prefix(10)))
    }

    static func dayString(from date: Date) -> String { day.string(from: date) }

    /// Server timestamps (`timestamptz`/`timestamp`) in any PostgREST shape.
    static func timestamp(from s: String) -> Date? { ISODate.date(from: s) }

    // MARK: Display (locale-aware, allocation-free on hot paths)

    private static func displayFormatter(template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale.autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    /// "Jul 6" / "6 iul."
    static let monthDay = displayFormatter(template: "MMMd")
    /// "Jul 6, 14:30" / "6 iul., 14:30"
    static let monthDayTime = displayFormatter(template: "MMMd HHmm")
    /// "Jul 6, 2026" / "6 iul. 2026"
    static let monthDayYear = displayFormatter(template: "yMMMd")
    /// "Jul" / "iul." — chart axis month labels.
    static let monthLabel = displayFormatter(template: "MMM")

    /// Medium date, no time ("Jul 6, 2026") — the standard document/lease style.
    static let medium: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.autoupdatingCurrent
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}
