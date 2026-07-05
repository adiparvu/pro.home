import Foundation
import EventKit

// MARK: - Calendar & Reminders sync for tasks
//
// One shared EKEventStore for listing writable calendars (iCloud, Google,
// Exchange… — any account configured on the device shows up as a source),
// creating events in a chosen calendar, and creating Apple Reminders.
// With full access we can offer a calendar picker; if the user only grants
// write-only access we still save silently to the default calendar.

@MainActor
enum TaskCalendarSync {

    enum EventAccess {
        case full
        case writeOnly
        case denied
    }

    static let store = EKEventStore()

    // MARK: Access

    static func requestEventAccess() async -> EventAccess {
        if (try? await store.requestFullAccessToEvents()) == true { return .full }
        if (try? await store.requestWriteOnlyAccessToEvents()) == true { return .writeOnly }
        return .denied
    }

    static func requestReminderAccess() async -> Bool {
        (try? await store.requestFullAccessToReminders()) ?? false
    }

    // MARK: Calendars

    /// All calendars the user can write to, sorted by account then name —
    /// e.g. "iCloud · Personal", "Google · adrian@gmail.com".
    static func writableCalendars() -> [EKCalendar] {
        store.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .sorted {
                let a = ($0.source?.title ?? "", $0.title)
                let b = ($1.source?.title ?? "", $1.title)
                return a < b
            }
    }

    static var defaultCalendarId: String? {
        store.defaultCalendarForNewEvents?.calendarIdentifier
    }

    // MARK: Events

    /// Creates a calendar event for a task's due date. All-day when no time
    /// is set, otherwise a one-hour block with an alert one hour before.
    @discardableResult
    static func addEvent(title: String, notes: String?, date: Date,
                         hasTime: Bool, calendarId: String?) -> Bool {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.notes = notes
        if hasTime {
            event.startDate = date
            event.endDate = Calendar.current.date(byAdding: .hour, value: 1, to: date) ?? date
            event.addAlarm(EKAlarm(relativeOffset: -3600))
        } else {
            event.isAllDay = true
            event.startDate = date
            event.endDate = date
            // All-day events start at midnight — alert at 09:00 that day.
            event.addAlarm(EKAlarm(relativeOffset: 9 * 3600))
        }
        if let calendarId, let calendar = store.calendar(withIdentifier: calendarId) {
            event.calendar = calendar
        } else {
            event.calendar = store.defaultCalendarForNewEvents
        }
        guard event.calendar != nil else { return false }
        do {
            try store.save(event, span: .thisEvent)
            return true
        } catch {
            return false
        }
    }

    // MARK: Reminders

    /// Creates a reminder in the default Reminders list, due on the task's
    /// date (with an absolute-time alarm when a time is set).
    @discardableResult
    static func addReminder(title: String, notes: String?, date: Date, hasTime: Bool) -> Bool {
        guard let list = store.defaultCalendarForNewReminders() else { return false }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = list
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        if hasTime {
            let time = Calendar.current.dateComponents([.hour, .minute], from: date)
            comps.hour = time.hour
            comps.minute = time.minute
            reminder.addAlarm(EKAlarm(absoluteDate: date))
        }
        reminder.dueDateComponents = comps
        do {
            try store.save(reminder, commit: true)
            return true
        } catch {
            return false
        }
    }
}
