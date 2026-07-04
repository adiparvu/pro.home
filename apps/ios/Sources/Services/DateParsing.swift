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

    static func date(from s: String) -> Date? {
        fractional.date(from: s) ?? plain.date(from: s)
    }

    /// "HH:mm" — the bubble/row timestamp shown throughout chat (WhatsApp-style).
    static let timeOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
