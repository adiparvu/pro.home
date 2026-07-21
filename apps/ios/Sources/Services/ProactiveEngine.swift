import Foundation
import Observation
import BackgroundTasks
import UserNotifications

// MARK: - Proactive Insight

struct ProactiveInsight: Identifiable, Codable {
    let id: UUID
    let title: String
    let body: String
    let category: InsightCategory
    let createdAt: Date
    var isDismissed: Bool

    enum InsightCategory: String, Codable {
        case warranty, maintenance, seasonal, financial, age
        var icon: String {
            switch self {
            case .warranty:    return "shield.slash.fill"
            case .maintenance: return "wrench.fill"
            case .seasonal:    return "calendar.badge.clock"
            case .financial:   return "banknote.fill"
            case .age:         return "clock.badge.exclamationmark.fill"
            }
        }
    }
}

// MARK: - ProactiveEngine

@MainActor
@Observable
final class ProactiveEngine {
    var insights: [ProactiveInsight] = []

    @MainActor static var shared: ProactiveEngine?

    static let bgTaskId = "com.prvio.app.proactive"
    private static let insightsKey        = "prvio.proactive.insights_v1"
    private static let appliancesCacheKey = "prvio.proactive.appliances_v1"
    private static let elementsCacheKey   = "prvio.proactive.elements_v1"

    init() {
        load()
        ProactiveEngine.shared = self
    }

    // MARK: - Analysis

    func analyze(appliances: [Appliance], elements: [PropertyElement],
                 records: [FinancialRecord] = [], tasks: [MaintenanceTask] = [],
                 sensors: [IoTSensor] = []) {
        var fresh: [ProactiveInsight] = []

        // The butler speaks from YOUR numbers, not generic tips: the biggest
        // month-over-month expense swing, and task momentum when work piles up.
        if let money = financialDeltaInsight(records) { fresh.append(money) }
        if let momentum = taskMomentumInsight(tasks) { fresh.append(momentum) }

        // Predictive maintenance from the property's own records: element
        // condition/warranty, appliance repair economics, sensor thresholds.
        fresh.append(contentsOf: elementCareInsights(elements))
        fresh.append(contentsOf: repairCostInsights(appliances, records: records))
        fresh.append(contentsOf: sensorRangeInsights(sensors))

        // Warranties expiring within 30 days
        let expiringSoon = appliances.filter { $0.isWarrantyExpiringSoon }
        for a in expiringSoon {
            let days = daysUntil(a.warrantyUntil)
            fresh.append(ProactiveInsight(
                id: deterministicID("warranty-\(a.id)"),
                title: String(format: String(localized: "Warranty expiring: %@"), a.name),
                body: String(format: days == 1
                    ? String(localized: "Warranty expires in 1 day. Check if extension is available.")
                    : String(localized: "Warranty expires in %d days. Check if extension is available."),
                    days),
                category: .warranty,
                createdAt: Date(),
                isDismissed: false
            ))
        }

        // Appliance age against the curated NAHB lifespan table — the same
        // per-category ranges the appliance pages already show, instead of
        // the old ad-hoc name-keyword guesses. Spoken only once the age
        // enters the typical range; the id keeps the legacy "age-" seed so
        // earlier dismissals survive the upgrade.
        for appliance in appliances {
            guard let years = appliance.ageYears,
                  let range = ApplianceLifespan.typicalYears(for: appliance.category),
                  Int(years) >= range.lowerBound else { continue }
            fresh.append(ProactiveInsight(
                id: deterministicID("age-\(appliance.id)"),
                title: String(format: String(localized: "%@ may need replacement"), appliance.name),
                body: String(format: String(localized: "About %d years old — typical service life for its category is ~%d–%d years. Plan an inspection or budget for a replacement."),
                             Int(years), range.lowerBound, range.upperBound),
                category: .age,
                createdAt: Date(),
                isDismissed: false
            ))
        }

        // Seasonal maintenance hints (by current month)
        let month = Calendar.current.component(.month, from: Date())
        let seasonal = seasonalHints(for: month)
        for hint in seasonal {
            fresh.append(ProactiveInsight(
                id: deterministicID("seasonal-\(month)-\(hint.title)"),
                title: hint.title,
                body: hint.body,
                category: .seasonal,
                createdAt: Date(),
                isDismissed: false
            ))
        }

        // Merge: keep existing dismissed state, drop stale
        let existingById = Dictionary(insights.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        insights = fresh.map { insight in
            var copy = insight
            if let existing = existingById[insight.id] {
                copy.isDismissed = existing.isDismissed
            }
            return copy
        }
        persist()
    }

    // MARK: - Notifications

    func scheduleNotifications(for insights: [ProactiveInsight]) {
        // Per-category gates: warranty warnings ride the warranty toggle,
        // predictive-maintenance ones the task-reminders toggle.
        let warrantyOn = NotificationScheduler.prefEnabled(NotificationScheduler.Keys.warrantyAlerts)
        let maintenanceOn = NotificationScheduler.prefEnabled(NotificationScheduler.Keys.taskReminders)
        guard warrantyOn || maintenanceOn else { return }
        let center = UNUserNotificationCenter.current()
        // Insight ids are deterministic and analyze() reruns on every launch
        // and background refresh — without this ledger the same warranty
        // warnings re-fired (5s trigger) at every single app open.
        let ledgerKey = "prvio.proactive.notified"
        var notified = Set(UserDefaults.standard.stringArray(forKey: ledgerKey) ?? [])
        defer {
            // Prune to the current generation so the ledger can't grow
            // unbounded; a vanished insight that ever returns may alert again.
            let live = Set(insights.map { $0.id.uuidString })
            UserDefaults.standard.set(Array(notified.intersection(live)), forKey: ledgerKey)
        }
        for insight in insights.filter({
            !$0.isDismissed && !notified.contains($0.id.uuidString)
                && (($0.category == .warranty && warrantyOn)
                    || ($0.category == .maintenance && maintenanceOn))
        }) {
            notified.insert(insight.id.uuidString)
            let content = UNMutableNotificationContent()
            content.title = insight.title
            content.body = insight.body
            content.sound = .default
            content.categoryIdentifier = "PROACTIVE"
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            let request = UNNotificationRequest(
                identifier: "proactive-\(insight.id)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    func dismiss(_ insight: ProactiveInsight) {
        if let idx = insights.firstIndex(where: { $0.id == insight.id }) {
            insights[idx].isDismissed = true
            persist()
        }
    }

    var activeInsights: [ProactiveInsight] { insights.filter { !$0.isDismissed } }

    // MARK: - Background Cache

    static func cacheForBackground(appliances: [Appliance], elements: [PropertyElement]) {
        if let data = try? JSONEncoder().encode(appliances) {
            UserDefaults.standard.set(data, forKey: appliancesCacheKey)
        }
        if let data = try? JSONEncoder().encode(elements) {
            UserDefaults.standard.set(data, forKey: elementsCacheKey)
        }
    }

    func runAnalysisFromCache() {
        let appliances = (try? JSONDecoder().decode(
            [Appliance].self,
            from: UserDefaults.standard.data(forKey: Self.appliancesCacheKey) ?? Data()
        )) ?? []
        let elements = (try? JSONDecoder().decode(
            [PropertyElement].self,
            from: UserDefaults.standard.data(forKey: Self.elementsCacheKey) ?? Data()
        )) ?? []
        analyze(appliances: appliances, elements: elements)
        scheduleNotifications(for: activeInsights)
    }

    // MARK: - Background Task Registration

    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: bgTaskId, using: nil) { bgTask in
            let work = Task { @MainActor in
                ProactiveEngine.shared?.runAnalysisFromCache()
                scheduleBackgroundRefresh()
                bgTask.setTaskCompleted(success: true)
            }
            bgTask.expirationHandler = { work.cancel() }
        }
    }

    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: bgTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600 * 6)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Data-driven insights

    /// The expense category that moved the most vs last month — only spoken
    /// when the swing is meaningful (≥20% and ≥50 in currency), so it reads
    /// as intelligence, not noise.
    private func financialDeltaInsight(_ records: [FinancialRecord]) -> ProactiveInsight? {
        guard !records.isEmpty else { return nil }
        let cal = Calendar.current
        let now = Date()
        guard let lastMonth = cal.date(byAdding: .month, value: -1, to: now) else { return nil }
        let thisKey = AppDate.monthKey.string(from: now)
        let lastKey = AppDate.monthKey.string(from: lastMonth)

        var thisMonth: [String: Double] = [:]
        var prevMonth: [String: Double] = [:]
        for r in records where r.type == "expense" {
            if r.date.hasPrefix(thisKey) { thisMonth[r.category, default: 0] += r.amount }
            else if r.date.hasPrefix(lastKey) { prevMonth[r.category, default: 0] += r.amount }
        }

        var best: (category: String, delta: Double, pct: Int)? = nil
        for (category, previous) in prevMonth where previous > 0 {
            let current = thisMonth[category] ?? 0
            let delta = current - previous
            let pct = Int((delta / previous) * 100)
            guard abs(pct) >= 20, abs(delta) >= 50 else { continue }
            if abs(delta) > abs(best?.delta ?? 0) { best = (category, delta, pct) }
        }
        guard let best else { return nil }

        let rising = best.delta > 0
        return ProactiveInsight(
            id: deterministicID("fin-\(thisKey)-\(best.category)"),
            title: String(format: rising
                ? String(localized: "%@ spending up %d%%")
                : String(localized: "%@ spending down %d%%"),
                best.category.capitalized, abs(best.pct)),
            body: String(format: rising
                ? String(localized: "You've spent %d more on %@ than last month. Worth a look at the entries.")
                : String(localized: "You've spent %d less on %@ than last month. Whatever changed — it's working."),
                Int(abs(best.delta)), best.category),
            category: .financial,
            createdAt: Date(),
            isDismissed: false
        )
    }

    /// When overdue work piles up, name it — with the oldest task as the
    /// concrete place to start.
    private func taskMomentumInsight(_ tasks: [MaintenanceTask]) -> ProactiveInsight? {
        let overdue = tasks.filter { $0.isOverdue && !$0.isCompleted }
        guard overdue.count >= 3 else { return nil }
        let oldest = overdue.min { ($0.dueDate ?? "") < ($1.dueDate ?? "") }
        let weekKey = AppDate.weekKey.string(from: Date())
        return ProactiveInsight(
            id: deterministicID("momentum-\(weekKey)"),
            title: String(format: String(localized: "%d tasks are overdue"), overdue.count),
            body: String(format: String(localized: "Start with the oldest: \"%@\". Clearing one gets the streak going."),
                         oldest?.title ?? ""),
            category: .maintenance,
            createdAt: Date(),
            isDismissed: false
        )
    }

    // MARK: - Predictive maintenance rules

    /// Element-level care: a warranty about to lapse, or a technical
    /// condition the household itself recorded as poor/critical. Both are
    /// facts already in the element rows — the engine only surfaces them.
    private func elementCareInsights(_ elements: [PropertyElement]) -> [ProactiveInsight] {
        var out: [ProactiveInsight] = []
        for el in elements {
            if let until = parseDateStr(el.warrantyUntil) {
                let days = Calendar.current.dateComponents([.day], from: Date(), to: until).day ?? 0
                if (0...30).contains(days) {
                    out.append(ProactiveInsight(
                        id: deterministicID("elem-warranty-\(el.id)"),
                        title: String(format: String(localized: "Warranty expiring: %@"), el.name),
                        body: String(format: days == 1
                            ? String(localized: "Warranty expires in 1 day. Check if extension is available.")
                            : String(localized: "Warranty expires in %d days. Check if extension is available."),
                            days),
                        category: .warranty,
                        createdAt: Date(),
                        isDismissed: false
                    ))
                }
            }
            if el.technicalCondition == .poor || el.technicalCondition == .critical {
                out.append(ProactiveInsight(
                    id: deterministicID("elem-care-\(el.id)"),
                    title: String(format: String(localized: "%@ needs attention"), el.name),
                    body: String(format: String(localized: "Its recorded condition is \"%@\". Schedule a service visit before it worsens."),
                                 el.technicalCondition.displayName),
                    category: .maintenance,
                    createdAt: Date(),
                    isDismissed: false
                ))
            }
            // Service cadence (phase 2): the household set an interval — speak
            // when the predicted date is within 30 days or already behind.
            if let due = el.nextServiceDue {
                let days = Calendar.current.dateComponents(
                    [.day], from: Calendar.current.startOfDay(for: Date()),
                    to: Calendar.current.startOfDay(for: due)).day ?? 0
                if days <= 30 {
                    out.append(ProactiveInsight(
                        id: deterministicID("elem-service-\(el.id)"),
                        title: String(format: String(localized: "Service due: %@"), el.name),
                        body: days < 0
                            ? String(format: String(localized: "Its service was predicted for %@ — it's behind schedule."),
                                     due.formatted(date: .abbreviated, time: .omitted))
                            : String(format: String(localized: "Based on the cadence you set, the next service lands around %@."),
                                     due.formatted(date: .abbreviated, time: .omitted)),
                        category: .maintenance,
                        createdAt: Date(),
                        isDismissed: false
                    ))
                }
            }
        }
        return out
    }

    /// Replacement economics: when logged service work on an appliance has
    /// cost at least half its purchase price — the same signal the service
    /// book shows — say it here too, where the household actually looks.
    private func repairCostInsights(_ appliances: [Appliance],
                                    records: [FinancialRecord]) -> [ProactiveInsight] {
        var out: [ProactiveInsight] = []
        for appliance in appliances {
            guard let price = appliance.purchasePrice, price > 0 else { continue }
            let repairs = ApplianceServiceLog.totalRepairs(
                ApplianceServiceLog.interventions(in: records, appliance: appliance))
            guard repairs >= price * 0.5 else { continue }
            out.append(ProactiveInsight(
                id: deterministicID("repaircost-\(appliance.id)"),
                title: String(format: String(localized: "Repairs on %@ are adding up"), appliance.name),
                body: String(format: String(localized: "Logged service work has reached %@ — about half its purchase price. A replacement may now be the better economy."),
                             CurrencyService.money(repairs, code: "EUR", whole: true)),
                category: .age,
                createdAt: Date(),
                isDismissed: false
            ))
        }
        return out
    }

    /// Sensor thresholds the household set themselves (alertMin/alertMax):
    /// a live reading outside that band is a fact worth surfacing. No
    /// speculation — sensors without a reading or without thresholds stay
    /// silent.
    private func sensorRangeInsights(_ sensors: [IoTSensor]) -> [ProactiveInsight] {
        var out: [ProactiveInsight] = []
        for sensor in sensors {
            guard let value = sensor.value else { continue }
            let low  = sensor.alertMin.map { value < $0 } ?? false
            let high = sensor.alertMax.map { value > $0 } ?? false
            guard low || high else { continue }
            out.append(ProactiveInsight(
                id: deterministicID("sensor-range-\(sensor.id)"),
                title: String(format: String(localized: "%@ reading out of range"), sensor.name),
                body: String(format: String(localized: "Latest value: %@ %@ — outside the alert range you set. Worth checking."),
                             value.formatted(.number.precision(.fractionLength(0...1))), sensor.unit),
                category: .maintenance,
                createdAt: Date(),
                isDismissed: false
            ))
        }
        return out
    }

    // MARK: - Private

    private func persist() {
        if let data = try? JSONEncoder().encode(insights) {
            UserDefaults.standard.set(data, forKey: Self.insightsKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.insightsKey),
              let decoded = try? JSONDecoder().decode([ProactiveInsight].self, from: data)
        else { return }
        insights = decoded
    }

    private func deterministicID(_ seed: String) -> UUID {
        let data = seed.data(using: .utf8) ?? Data()
        var bytes = [UInt8](repeating: 0, count: 16)
        for (i, byte) in data.prefix(16).enumerated() { bytes[i] = byte }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    private func daysUntil(_ dateStr: String?) -> Int {
        guard let d = parseDateStr(dateStr) else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: Date(), to: d).day ?? 0)
    }

    private func parseDateStr(_ str: String?) -> Date? {
        guard let str else { return nil }
        return AppDate.day(from: str)
    }

    private struct SeasonalHint { let title: String; let body: String }
    private func seasonalHints(for month: Int) -> [SeasonalHint] {
        switch month {
        case 3, 4:  // Spring
            return [
                SeasonalHint(
                    title: String(localized: "Spring HVAC checkup due"),
                    body: String(localized: "Schedule AC service before the warm season to ensure peak efficiency.")),
                SeasonalHint(
                    title: String(localized: "Gutter cleaning season"),
                    body: String(localized: "Clear winter debris from gutters and downspouts to prevent water damage.")),
            ]
        case 9, 10: // Autumn
            return [
                SeasonalHint(
                    title: String(localized: "Heating system checkup"),
                    body: String(localized: "Service your boiler or furnace before winter to avoid cold-weather breakdowns.")),
                SeasonalHint(
                    title: String(localized: "Weatherproofing check"),
                    body: String(localized: "Inspect door/window seals and insulation before temperatures drop.")),
            ]
        case 11, 12: // Winter
            return [
                SeasonalHint(
                    title: String(localized: "Pipe freeze prevention"),
                    body: String(localized: "Insulate exposed pipes in unheated spaces to prevent burst pipes.")),
            ]
        case 6, 7, 8: // Summer
            return [
                SeasonalHint(
                    title: String(localized: "Irrigation system check"),
                    body: String(localized: "Inspect sprinklers and drip lines for leaks before peak watering season.")),
            ]
        default:
            return []
        }
    }
}
