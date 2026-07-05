import Foundation

/// Shared ISO8601 formatters for chat timestamps.
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
        guard let d = fractional.date(from: s) ?? plain.date(from: s) else { return nil }
        parseCache.setObject(d as NSDate, forKey: s as NSString)
        return d
    }

    /// "HH:mm" — the bubble/row timestamp shown throughout chat (WhatsApp-style).
    static let timeOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
