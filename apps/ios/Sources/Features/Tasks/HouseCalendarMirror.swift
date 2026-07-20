import Foundation
import EventKit
import CoreLocation
import UIKit

// MARK: - House calendar → Apple Calendar mirror
//
// A ONE-WAY mirror of the house agenda into a dedicated "PRVIO" calendar in
// EventKit. The app is the source of truth (the deadlines are shared family
// data in Supabase); each device mirrors them into its own Apple Calendar so
// they sit next to the owner's personal appointments and ride iCloud to their
// other devices. Using a dedicated calendar means the user can hide/show it
// with one tap and removing it is a clean uninstall — we never touch their
// personal calendars.
//
// Identity: each event stores its agenda occurrence key (base64url) in
// `event.url`, so reconciliation matches, updates and prunes precisely without
// ever creating duplicates.

@MainActor
enum HouseCalendarMirror {
    private static let calIdKey  = "prvio.mirrorCalendarId"
    static let enabledKey        = "prvio.calendarMirrorEnabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    private static var store: EKEventStore { TaskCalendarSync.store }

    // MARK: Dedicated calendar

    /// The "PRVIO" calendar (created on demand) — also the task form's
    /// DEFAULT sync target (IMG_8677), so house events land under the PRVIO
    /// name instead of whatever the user's default calendar happens to be.
    static func dedicatedCalendar() -> EKCalendar? { mirrorCalendar() }

    /// The "PRVIO" calendar, created on first use in a writable source
    /// (iCloud preferred, then local). nil if no source can host it.
    private static func mirrorCalendar() -> EKCalendar? {
        if let id = UserDefaults.standard.string(forKey: calIdKey),
           let cal = store.calendar(withIdentifier: id) { return cal }
        let source = store.sources.first { $0.sourceType == .calDAV && $0.title == "iCloud" }
            ?? store.sources.first { $0.sourceType == .local }
            ?? store.defaultCalendarForNewEvents?.source
        guard let source else { return nil }
        let cal = EKCalendar(for: .event, eventStore: store)
        cal.title = "PRVIO"
        cal.source = source
        cal.cgColor = UIColor.systemIndigo.cgColor
        do {
            try store.saveCalendar(cal, commit: true)
            UserDefaults.standard.set(cal.calendarIdentifier, forKey: calIdKey)
            return cal
        } catch { return nil }
    }

    // MARK: Occurrence key ⇄ event.url (base64url)

    private static func url(for key: String) -> URL? {
        let b64 = Data(key.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return URL(string: "prvio://agenda/\(b64)")
    }

    private static func key(from url: URL?) -> String? {
        guard let url, url.scheme == "prvio", url.host == "agenda" else { return nil }
        var b64 = url.lastPathComponent
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    // MARK: Reconcile

    /// Make the PRVIO calendar exactly match `items` over the sync window:
    /// create missing events, update changed ones, delete those whose source
    /// occurrence is gone. No-op unless the mirror is enabled and the user has
    /// granted FULL calendar access (write-only can't read back to reconcile).
    static func sync(_ items: [AgendaItem]) async {
        guard isEnabled,
              EKEventStore.authorizationStatus(for: .event) == .fullAccess,
              let cal = mirrorCalendar() else { return }

        // 1 month back → 12 months ahead, matching the agenda projection window.
        let now = Date()
        let start = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
        let end   = Calendar.current.date(byAdding: .month, value: 12, to: now) ?? now

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [cal])
        var byKey: [String: EKEvent] = [:]
        for e in store.events(matching: predicate) {
            if let k = key(from: e.url) { byKey[k] = e }
        }

        // Backstop against the wipe-and-recreate storm: an entirely empty
        // agenda while the calendar still holds mirrored events is far more
        // likely a snapshot taken before the services loaded than a house
        // that truly emptied its whole agenda at once. Pruning on it would
        // delete every event and recreate them on the next sync — and on a
        // shared PRVIO calendar every participant gets a "Deleted by …"
        // notification per event, every launch. The world-loaded gate at the
        // call sites is the real fix; this keeps any future caller honest.
        if items.isEmpty && !byKey.isEmpty { return }

        var wanted = Set<String>()
        for item in items where item.date >= start && item.date <= end {
            wanted.insert(item.occurrenceKey)
            let event = byKey[item.occurrenceKey] ?? EKEvent(eventStore: store)
            apply(item, to: event, calendar: cal)
            try? store.save(event, span: .thisEvent, commit: false)
        }
        for (k, e) in byKey where !wanted.contains(k) {
            try? store.remove(e, span: .thisEvent, commit: false)
        }
        try? store.commit()
    }

    private static func apply(_ item: AgendaItem, to event: EKEvent, calendar: EKCalendar) {
        event.calendar = calendar
        event.title = item.title
        event.url = url(for: item.occurrenceKey)
        event.notes = item.subtitle
        if item.hasTime {
            event.isAllDay = false
            event.startDate = item.date
            event.endDate = Calendar.current.date(byAdding: .hour, value: 1, to: item.date) ?? item.date
        } else {
            event.isAllDay = true
            event.startDate = Calendar.current.startOfDay(for: item.date)
            event.endDate = event.startDate
        }
    }

    // MARK: Standalone chat events

    /// Saves a chat-composed event into the dedicated PRVIO calendar
    /// (created on first use). Standalone events intentionally carry NO
    /// agenda occurrence key in `event.url`, so `sync`'s reconciliation —
    /// which only matches, updates and prunes keyed events — never touches
    /// them. Requires full access: resolving/creating the dedicated calendar
    /// reads sources, which write-only access hides. Returns false when
    /// access was denied or the save failed, so callers can be honest about
    /// the outcome.
    @discardableResult
    static func addChatEvent(title: String, notes: String?, location: String?,
                             lat: Double? = nil, lon: Double? = nil,
                             start: Date, end: Date, isAllDay: Bool) async -> Bool {
        guard await TaskCalendarSync.requestEventAccess() == .full,
              let cal = mirrorCalendar() else { return false }
        let event = EKEvent(eventStore: store)
        event.calendar = cal
        event.title = title
        event.notes = notes
        // location first: assigning it resets any structuredLocation to a
        // title-only one, so the geocoded pin must be applied after it.
        event.location = location
        if let lat, let lon {
            // Coordinates from the composer's map pick — a structured
            // location makes Apple Calendar show the map and travel-time.
            let place = EKStructuredLocation(title: location ?? title)
            place.geoLocation = CLLocation(latitude: lat, longitude: lon)
            event.structuredLocation = place
        }
        if isAllDay {
            let day = Calendar.current.startOfDay(for: start)
            event.isAllDay = true
            event.startDate = day
            event.endDate = max(day, Calendar.current.startOfDay(for: end))
        } else {
            event.startDate = start
            event.endDate = max(end, start)
            event.addAlarm(EKAlarm(relativeOffset: -3600))
        }
        do {
            try store.save(event, span: .thisEvent, commit: true)
            return true
        } catch { return false }
    }

    // MARK: Enable / disable

    /// Requests full access, enables the mirror and does a first sync. Returns
    /// false if access was denied (so the UI can revert the toggle).
    @discardableResult
    static func enable(with items: [AgendaItem]) async -> Bool {
        guard await TaskCalendarSync.requestEventAccess() == .full else { return false }
        isEnabled = true
        await sync(items)
        return true
    }

    /// Turn the mirror off and remove the PRVIO calendar entirely — a clean
    /// uninstall that leaves the user's personal calendars untouched.
    static func disableAndRemove() {
        isEnabled = false
        if let id = UserDefaults.standard.string(forKey: calIdKey),
           let cal = store.calendar(withIdentifier: id) {
            try? store.removeCalendar(cal, commit: true)
        }
        UserDefaults.standard.removeObject(forKey: calIdKey)
    }
}
