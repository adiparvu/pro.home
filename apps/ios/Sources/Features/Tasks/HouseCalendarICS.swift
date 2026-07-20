import Foundation

// MARK: - iCalendar export for the house calendar
//
// Builds an RFC 5545 .ics file from the property's dated facts so they can
// live inside Apple Calendar (or any calendar app) next to the owner's own
// appointments. Every event is all-day: the house knows dates, not hours,
// and inventing times would violate the honesty law.

enum HouseCalendarICS {
    static func build(tasks: [MaintenanceTask],
                      documents: [DocumentModel],
                      appliances: [Appliance],
                      members: [FamilyMember]) -> String {
        var lines: [String] = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//PRVIO//House Calendar//EN",
            "CALSCALE:GREGORIAN",
            "X-WR-CALNAME:PRVIO",
        ]

        for task in tasks where !task.isCompleted {
            guard let day = compactDay(task.dueDate) else { continue }
            lines += event(uid: "task-\(task.id.uuidString)",
                           day: day,
                           summary: task.title,
                           category: "TASK")
        }
        for doc in documents {
            guard let day = compactDay(doc.expiresAt) else { continue }
            lines += event(uid: "doc-\(doc.id.uuidString)",
                           day: day,
                           summary: String(format: String(localized: "ics_expires_fmt"), doc.name),
                           category: "DOCUMENT")
        }
        for appliance in appliances {
            guard let day = compactDay(appliance.warrantyUntil) else { continue }
            lines += event(uid: "warranty-\(appliance.id.uuidString)",
                           day: day,
                           summary: String(format: String(localized: "ics_warranty_fmt"), appliance.name),
                           category: "WARRANTY")
        }
        for member in members {
            guard let birth = member.birthday, let day = compactDay(birth) else { continue }
            // Anchor the yearly rule on this year's occurrence so calendar
            // apps show upcoming birthdays instead of decades of history.
            let thisYear = String(Calendar.current.component(.year, from: Date())) + String(day.suffix(4))
            lines += event(uid: "bday-\(member.id.uuidString)",
                           day: thisYear,
                           summary: String(format: String(localized: "ics_birthday_fmt"), member.name),
                           category: "BIRTHDAY",
                           extra: ["RRULE:FREQ=YEARLY"])
        }

        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Writes the calendar to a shareable temp file; nil when there is
    /// nothing dated to export (the share button then stays hidden).
    static func writeFile(tasks: [MaintenanceTask],
                          documents: [DocumentModel],
                          appliances: [Appliance],
                          members: [FamilyMember]) -> URL? {
        let ics = build(tasks: tasks, documents: documents,
                        appliances: appliances, members: members)
        guard ics.contains("BEGIN:VEVENT") else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PRVIO-Calendar.ics")
        do {
            try ics.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Pieces

    private static func event(uid: String, day: String, summary: String,
                              category: String, extra: [String] = []) -> [String] {
        var ev = [
            "BEGIN:VEVENT",
            "UID:prvio-\(uid)@prvio.app",
            "DTSTAMP:\(day)T000000Z",
            "DTSTART;VALUE=DATE:\(day)",
            "SUMMARY:\(escape(summary))",
            "CATEGORIES:\(category)",
        ]
        ev += extra
        ev.append("END:VEVENT")
        return ev
    }

    /// "yyyy-MM-dd…" → "yyyyMMdd", nil when the value isn't a real date.
    private static func compactDay(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let day = String(raw.prefix(10)).replacingOccurrences(of: "-", with: "")
        guard day.count == 8, day.allSatisfy(\.isNumber) else { return nil }
        return day
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
