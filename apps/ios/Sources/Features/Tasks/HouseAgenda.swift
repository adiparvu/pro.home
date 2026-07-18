import SwiftUI

// MARK: - House agenda (the one deadline aggregator)
//
// Every dated thing the property knows about, normalized into one list so the
// in-app calendar AND the EventKit mirror read from a single source of truth
// instead of each re-deriving from six services. Recurring items (birthdays,
// recurring bills, plant care) are PROJECTED across the requested range so a
// yearly birthday or a monthly bill shows on every occurrence in view.

enum AgendaCategory: String, CaseIterable, Identifiable {
    // `event` first: it's the user's own events (Calendar C2) and reads as the
    // primary category, ahead of the derived deadlines.
    case event, task, document, warranty, birthday, financial, plant, lease
    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .event:     return "agenda_cat_events"
        case .task:      return "agenda_cat_tasks"
        case .document:  return "agenda_cat_documents"
        case .warranty:  return "agenda_cat_warranties"
        case .birthday:  return "agenda_cat_birthdays"
        case .financial: return "agenda_cat_financial"
        case .plant:     return "agenda_cat_plants"
        case .lease:     return "agenda_cat_leases"
        }
    }

    var icon: String {
        switch self {
        case .event:     return "calendar"
        case .task:      return "checklist"
        case .document:  return "doc.text.fill"
        case .warranty:  return "checkmark.seal.fill"
        case .birthday:  return "gift.fill"
        case .financial: return "creditcard.fill"
        case .plant:     return "leaf.fill"
        case .lease:     return "key.fill"
        }
    }

    var color: Color {
        switch self {
        // The only hue not already taken by the seven derived categories.
        case .event:     return .orange
        case .task:      return .brandPrimaryBlue
        case .document:  return .brandWarning
        case .warranty:  return .brandSuccess
        case .birthday:  return .pink
        case .financial: return .brandPurple
        case .plant:     return .green
        case .lease:     return .brandSkyBlue
        }
    }
}

/// One normalized agenda entry. `sourceId` keys the origin row so a deep-link
/// and the EventKit mirror's dedup can both find it; `occurrenceKey` is unique
/// per DAY so a recurring item mirrors as distinct events, never collides.
struct AgendaItem: Identifiable {
    let category: AgendaCategory
    let date: Date
    /// True when the source carries a wall-clock time (only tasks currently).
    let hasTime: Bool
    let title: String
    let subtitle: String
    let sourceId: String
    /// Completable items (tasks) carry their state so the calendar can strike
    /// them through and the Reminders mirror can reflect the checkbox.
    let isCompleted: Bool
    /// prvio:// deep link back to the item's own screen (nil = no destination).
    let deepLink: String?

    var id: String { occurrenceKey }
    /// Stable per-occurrence identity: category + source + the specific day.
    var occurrenceKey: String {
        "\(category.rawValue):\(sourceId):\(AppDate.dayString(from: date))"
    }
}

enum HouseAgenda {
    /// Build the agenda for a date range (inclusive of both ends by day).
    /// Recurring categories are projected across the range; one-shot dates are
    /// included when they fall inside it. Sorted by date, then category.
    static func items(
        in range: ClosedRange<Date>,
        tasks: [MaintenanceTask],
        documents: [DocumentModel],
        appliances: [Appliance],
        members: [FamilyMember],
        financial: [FinancialRecord],
        plants: [Plant],
        leases: [TenantLease] = [],
        events: [CalendarEvent] = []
    ) -> [AgendaItem] {
        let cal = Calendar.current
        let lo = cal.startOfDay(for: range.lowerBound)
        let hi = cal.startOfDay(for: range.upperBound)
        func inRange(_ d: Date) -> Bool {
            let s = cal.startOfDay(for: d); return s >= lo && s <= hi
        }

        var out: [AgendaItem] = []

        // The household's own calendar events (Calendar C2) — first-class,
        // one-shot dates. `hasTime` follows the all-day flag so a timed event
        // shows its clock time and an all-day one doesn't.
        for e in events {
            guard let d = AppDate.day(from: e.startsAt), inRange(d) else { continue }
            let subtitle = e.location?.isEmpty == false ? (e.location ?? "")
                : (e.notes?.isEmpty == false ? (e.notes ?? "") : "")
            out.append(AgendaItem(
                category: .event, date: d, hasTime: !e.allDay,
                title: e.title, subtitle: subtitle,
                sourceId: e.id.uuidString, isCompleted: false,
                deepLink: nil))
        }

        // Tasks — one-shot due dates (may carry a time).
        for t in tasks {
            guard let raw = t.dueDate, let d = AppDate.day(from: raw), inRange(d) else { continue }
            out.append(AgendaItem(
                category: .task, date: d, hasTime: raw.contains(":"),
                title: t.title, subtitle: t.statusDisplay,
                sourceId: t.id.uuidString, isCompleted: t.isCompleted,
                deepLink: "prvio://tasks/\(t.id.uuidString)"))
        }

        // Documents — expiry, plus the renewal date and the user-chosen custom
        // alert (both were collected and displayed but never reminded). Emitted
        // in priority order with a per-day dedup: same-day duplicates would
        // collide on occurrenceKey and triple-notify for one document.
        for doc in documents {
            var seenDays = Set<String>()
            func emitDocDay(_ raw: String?, subtitle: String) {
                guard let raw, let d = AppDate.day(from: raw), inRange(d),
                      seenDays.insert(AppDate.dayString(from: d)).inserted else { return }
                out.append(AgendaItem(
                    category: .document, date: d, hasTime: false,
                    title: doc.name, subtitle: subtitle,
                    sourceId: doc.id.uuidString, isCompleted: false,
                    deepLink: "prvio://documents/\(doc.id.uuidString)"))
            }
            emitDocDay(doc.expiresAt,
                       subtitle: String(format: String(localized: "cal_expires_fmt"), doc.expiresDisplay ?? ""))
            emitDocDay(doc.renewAt, subtitle: String(localized: "cal_doc_renewal"))
            emitDocDay(doc.notifyAt, subtitle: String(localized: "cal_doc_alert"))
        }

        // Appliance warranty ends.
        for a in appliances {
            guard let raw = a.warrantyUntil, let d = AppDate.day(from: raw), inRange(d) else { continue }
            out.append(AgendaItem(
                category: .warranty, date: d, hasTime: false,
                title: a.name, subtitle: String(localized: "cal_warranty_ends"),
                sourceId: a.id.uuidString, isCompleted: false,
                deepLink: "prvio://appliances/\(a.id.uuidString)"))
        }

        // Birthdays — recur yearly; project the anniversary into every year the
        // range spans.
        let years = Set((cal.component(.year, from: lo))...(cal.component(.year, from: hi)))
        for m in members {
            guard let birth = m.birthdayDate else { continue }
            let mc = cal.dateComponents([.month, .day], from: birth)
            for y in years {
                var comps = DateComponents(); comps.year = y; comps.month = mc.month; comps.day = mc.day
                guard let d = cal.date(from: comps), inRange(d) else { continue }
                out.append(AgendaItem(
                    category: .birthday, date: d, hasTime: false,
                    title: m.name, subtitle: String(localized: "cal_birthday"),
                    sourceId: m.id.uuidString, isCompleted: false,
                    deepLink: nil))
            }
        }

        // Financial — a recurring record projects across the range at ITS
        // OWN cadence: monthly on the day-of-month, yearly once on its
        // month+day (mirroring the server's pg_cron advance in migration
        // 015). The interval was previously ignored, so an annual bill —
        // insurance, road tax — flooded the agenda, the notifications and
        // the Apple Calendar mirror with 12 entries a year (audit fix).
        // A one-shot record is included when it lands inside the range.
        for r in financial {
            guard let base = AppDate.day(from: r.date) else { continue }
            let subtitle = CurrencyService.money(r.amount, code: r.currency)
            if r.isRecurring ?? false {
                let dom = cal.component(.day, from: base)
                let months: [Int] = r.recurrenceInterval == "yearly"
                    ? [cal.component(.month, from: base)]
                    : Array(1...12)
                for y in years {
                    for month in months {
                        var comps = DateComponents(); comps.year = y; comps.month = month; comps.day = dom
                        guard let d = cal.date(from: comps), inRange(d), d >= base else { continue }
                        out.append(AgendaItem(
                            category: .financial, date: d, hasTime: false,
                            title: r.title, subtitle: subtitle,
                            sourceId: r.id.uuidString, isCompleted: false,
                            deepLink: "prvio://finances"))
                    }
                }
            } else if inRange(base) {
                out.append(AgendaItem(
                    category: .financial, date: base, hasTime: false,
                    title: r.title, subtitle: subtitle,
                    sourceId: r.id.uuidString, isCompleted: false,
                    deepLink: "prvio://finances"))
            }
        }

        // Plants — the next watering date derived from the interval; a single
        // upcoming occurrence is enough for the calendar (the plant screen owns
        // the full schedule).
        for p in plants {
            guard p.wateringIntervalDays > 0, let last = p.lastWateredAtDate else { continue }
            var next = cal.date(byAdding: .day, value: p.wateringIntervalDays, to: last) ?? last
            // Advance to the first occurrence at/after the range start.
            var guardCount = 0
            while cal.startOfDay(for: next) < lo, guardCount < 400 {
                next = cal.date(byAdding: .day, value: p.wateringIntervalDays, to: next) ?? next
                guardCount += 1
            }
            guard inRange(next) else { continue }
            out.append(AgendaItem(
                category: .plant, date: next, hasTime: false,
                title: p.name, subtitle: String(localized: "agenda_plant_water"),
                sourceId: p.id.uuidString, isCompleted: false,
                deepLink: "prvio://plants/\(p.id.uuidString)"))
        }

        // Leases — the contract END (one-shot) and RENT DUE (recurring monthly
        // on the payment day). Titled with the tenant's name.
        let nameById = Dictionary(members.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        for lease in leases {
            let tenant = nameById[lease.memberId] ?? String(localized: "agenda_lease_tenant")
            if let raw = lease.leaseEnd, let d = AppDate.day(from: raw), inRange(d) {
                out.append(AgendaItem(
                    category: .lease, date: d, hasTime: false,
                    title: String(format: String(localized: "agenda_lease_ends"), tenant),
                    subtitle: lease.endDisplay ?? "",
                    sourceId: "\(lease.id.uuidString):end", isCompleted: false,
                    deepLink: "prvio://members/\(lease.memberId.uuidString)"))
            }
            if let dom = lease.paymentDay, dom >= 1, dom <= 31 {
                let rent = lease.rentDisplay ?? ""
                let startBound = lease.leaseStart.flatMap { AppDate.day(from: $0) } ?? lo
                for y in years {
                    for month in 1...12 {
                        var comps = DateComponents(); comps.year = y; comps.month = month; comps.day = dom
                        guard let d = cal.date(from: comps), inRange(d), d >= startBound else { continue }
                        // Stop projecting rent once the lease has ended.
                        if let end = lease.leaseEnd, let ed = AppDate.day(from: end), d > ed { continue }
                        out.append(AgendaItem(
                            category: .lease, date: d, hasTime: false,
                            title: String(format: String(localized: "agenda_lease_rent"), tenant),
                            subtitle: rent,
                            sourceId: "\(lease.id.uuidString):rent", isCompleted: false,
                            deepLink: "prvio://members/\(lease.memberId.uuidString)"))
                    }
                }
            }
        }

        return out.sorted {
            if cal.isDate($0.date, inSameDayAs: $1.date) {
                return $0.category.rawValue < $1.category.rawValue
            }
            return $0.date < $1.date
        }
    }

    /// The standard planning window — one month back to a year ahead — shared
    /// by the in-app calendar, the Apple Calendar mirror and the notification
    /// scheduler, so all three reason over exactly the same set of deadlines.
    static func upcomingYear(
        tasks: [MaintenanceTask],
        documents: [DocumentModel],
        appliances: [Appliance],
        members: [FamilyMember],
        financial: [FinancialRecord],
        plants: [Plant],
        leases: [TenantLease],
        events: [CalendarEvent] = []
    ) -> [AgendaItem] {
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(byAdding: .month, value: -1, to: now) ?? now
        let end = cal.date(byAdding: .month, value: 12, to: now) ?? now
        return items(
            in: start...end,
            tasks: tasks, documents: documents, appliances: appliances,
            members: members, financial: financial, plants: plants,
            leases: leases, events: events)
    }
}
