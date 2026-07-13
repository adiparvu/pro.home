import Foundation
import Supabase

// MARK: - The year's story, synthesized from this home's own data
//
// Everything in `YearStory` is computed from rows the household actually
// created — tasks, receipts, photos, documents, plants, evaluations, rent.
// The honesty law of the page: a chapter whose data doesn't exist is nil /
// empty here, and the UI simply never renders it. Nothing is estimated,
// nothing is invented.

// MARK: - One month of the year (the activity strip's bar)

struct YearMonthActivity: Identifiable, Equatable {
    /// 1...12
    let month: Int
    var tasksDone = 0
    var photos = 0
    var expenseCount = 0
    /// Sum of this month's expenses in the year's dominant expense currency
    /// only — amounts in other currencies are counted (expenseCount) but
    /// never silently added into a mixed total.
    var expenseTotal: Double = 0

    var id: Int { month }
    var total: Int { tasksDone + photos + expenseCount }

    enum Kind { case tasks, photos, expenses }

    /// The month's loudest activity — tints its bar in the strip.
    var dominant: Kind {
        if tasksDone >= photos && tasksDone >= expenseCount { return .tasks }
        if photos >= expenseCount { return .photos }
        return .expenses
    }
}

// MARK: - The assembled story

struct YearStory {
    let year: Int

    // Headline numbers (the stat grid / wrapped pages)
    let photosCount: Int
    let tasksDoneCount: Int
    let documentsCount: Int
    /// Dominant-currency expense total + code; `otherExpenseTotals` carries
    /// any further currencies separately (never summed together).
    let expenseCurrency: String?
    let expenseTotal: Double
    let otherExpenseTotals: [(code: String, total: Double)]

    // Story chapters (each nil/zero ⇒ the chapter does not render)
    let firstMemory: PhotoJournalEntry?
    let busiestMonth: (month: Int, count: Int)?
    let biggestExpense: FinancialRecord?
    /// Seconds banked by the work-session timer on tasks completed this year.
    let workedSeconds: Int
    /// The completed task with the most timed work this year.
    let projectOfYear: MaintenanceTask?
    /// The member with the most completed assigned tasks this year.
    let topMember: (member: FamilyMember, count: Int)?
    let plantsAdded: Int
    /// Watering events logged this year (plant care history).
    let waterings: Int
    /// First and last property evaluation of the year — present only when
    /// the year holds ≥ 2 evaluations in the same currency.
    let valueFirst: PropertyValueEntry?
    let valueLast: PropertyValueEntry?
    /// Rent recorded this year, per currency (income records, category "rent").
    let rentTotals: [(code: String, total: Double)]
    let rentPaymentsCount: Int
    /// The live house streak — only carried for the current calendar year.
    let streak: Int

    // The 12-month activity spine
    let months: [YearMonthActivity]

    // vs. previous year — nil whenever the previous year has no such data
    let photosDeltaPct: Int?
    let tasksDeltaPct: Int?
    let expensesDeltaPct: Int?

    var hasAnyData: Bool {
        photosCount > 0 || tasksDoneCount > 0 || documentsCount > 0
            || expenseTotal > 0 || !otherExpenseTotals.isEmpty
            || plantsAdded > 0 || waterings > 0
            || !rentTotals.isEmpty || valueLast != nil
    }

    var valueDelta: Double? {
        guard let first = valueFirst, let last = valueLast else { return nil }
        return last.valueAmount - first.valueAmount
    }
}

// MARK: - Builder

/// Pure synthesis over the already-loaded service arrays — no fetching, no
/// side effects, cheap enough to run per body evaluation (a few thousand
/// string-prefix filters at most).
struct YearStoryBuilder {
    let tasks: [MaintenanceTask]
    let records: [FinancialRecord]
    let photos: [PhotoJournalEntry]
    let documents: [DocumentModel]
    let plants: [Plant]
    let valueEntries: [PropertyValueEntry]
    let members: [FamilyMember]
    /// Watering-event counts per year (fetched once per page visit).
    let wateringsByYear: [Int: Int]
    /// The live house streak (SharedDataStore) — attributed to the current
    /// calendar year only.
    let currentStreak: Int

    private static func year(of dateString: String) -> Int? {
        Int(dateString.prefix(4))
    }
    private static func month(of dateString: String) -> Int? {
        Int(dateString.dropFirst(5).prefix(2))
    }

    /// Years that actually hold data, newest first; the current year is
    /// always present so the page has an honest (possibly empty) default.
    var availableYears: [Int] {
        var years: Set<Int> = [Calendar.current.component(.year, from: Date())]
        for t in tasks where t.isCompleted { if let y = Self.year(of: t.updatedAt) { years.insert(y) } }
        for r in records { if let y = Self.year(of: r.date) { years.insert(y) } }
        for p in photos { if let y = Self.year(of: p.takenAt) { years.insert(y) } }
        for d in documents { if let y = Self.year(of: d.createdAt) { years.insert(y) } }
        for p in plants { if let y = Self.year(of: p.createdAt) { years.insert(y) } }
        for v in valueEntries { if let y = Self.year(of: v.enteredAt) { years.insert(y) } }
        for y in wateringsByYear.keys { years.insert(y) }
        return years.sorted(by: >)
    }

    func build(year: Int) -> YearStory {
        let prefix = "\(year)-"
        let currentYear = Calendar.current.component(.year, from: Date())

        // ── Photos ────────────────────────────────────────────────────────
        let yearPhotos = photos.filter { $0.takenAt.hasPrefix(prefix) }
        let firstMemory = yearPhotos.min { $0.takenAt < $1.takenAt }

        // ── Tasks (completion = the update that flipped the status; the
        //    schema has no completed_at column, same convention as the
        //    monthly recap) ──────────────────────────────────────────────
        let doneTasks = tasks.filter { $0.isCompleted && $0.updatedAt.hasPrefix(prefix) }
        let workedSeconds = doneTasks.reduce(0) { $0 + $1.workedSeconds }
        let projectOfYear = doneTasks.filter { $0.workedSeconds > 0 }
            .max { $0.workedSeconds < $1.workedSeconds }

        var tasksByMonth: [Int: Int] = [:]
        for t in doneTasks {
            if let m = Self.month(of: t.updatedAt) { tasksByMonth[m, default: 0] += 1 }
        }
        let busiest = tasksByMonth
            .max { a, b in
                if a.value != b.value { return a.value < b.value }
                return a.key > b.key   // ties: the earliest month wins
            }
            .map { (month: $0.key, count: $0.value) }

        // ── Member of the year (completed tasks credited to assignees) ───
        var byAssignee: [String: Int] = [:]
        for t in doneTasks {
            for id in t.assigneeIds { byAssignee[id, default: 0] += 1 }
        }
        let topMember: (member: FamilyMember, count: Int)? = byAssignee
            .compactMap { (id, count) -> (FamilyMember, Int)? in
                guard let m = members.first(where: { $0.id.uuidString == id }) else { return nil }
                return (m, count)
            }
            .max { a, b in
                if a.1 != b.1 { return a.1 < b.1 }
                return a.0.name > b.0.name   // ties: alphabetically first wins
            }
            .map { (member: $0.0, count: $0.1) }

        // ── Money (per currency — amounts are never mixed across codes) ──
        let yearExpenses = records.filter { $0.type == "expense" && $0.date.hasPrefix(prefix) }
        let totalsByCurrency = Dictionary(grouping: yearExpenses, by: \.currency)
            .map { (code: $0.key, total: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }
        let dominant = totalsByCurrency.first
        let biggestExpense = yearExpenses.max { $0.amount < $1.amount }

        let rentRecords = records.filter {
            $0.type == "income" && $0.category == "rent" && $0.date.hasPrefix(prefix)
        }
        let rentTotals = Dictionary(grouping: rentRecords, by: \.currency)
            .map { (code: $0.key, total: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }

        // ── Documents / plants / value ────────────────────────────────────
        let documentsCount = documents.filter { $0.createdAt.hasPrefix(prefix) }.count
        let plantsAdded = plants.filter { $0.createdAt.hasPrefix(prefix) }.count

        let yearValues = valueEntries
            .filter { $0.enteredAt.hasPrefix(prefix) }
            .sorted { $0.enteredAt < $1.enteredAt }
        var valueFirst: PropertyValueEntry?
        var valueLast: PropertyValueEntry?
        if yearValues.count >= 2, let f = yearValues.first, let l = yearValues.last,
           f.currency == l.currency, f.valueAmount != l.valueAmount {
            valueFirst = f
            valueLast = l
        }

        // ── The 12-month spine ────────────────────────────────────────────
        var months = (1...12).map { YearMonthActivity(month: $0) }
        for t in doneTasks {
            if let m = Self.month(of: t.updatedAt), (1...12).contains(m) { months[m - 1].tasksDone += 1 }
        }
        for p in yearPhotos {
            if let m = Self.month(of: p.takenAt), (1...12).contains(m) { months[m - 1].photos += 1 }
        }
        for r in yearExpenses {
            guard let m = Self.month(of: r.date), (1...12).contains(m) else { continue }
            months[m - 1].expenseCount += 1
            if r.currency == dominant?.code { months[m - 1].expenseTotal += r.amount }
        }

        // ── vs. previous year (only when the prior year has data) ────────
        let prevPrefix = "\(year - 1)-"
        let prevPhotos = photos.filter { $0.takenAt.hasPrefix(prevPrefix) }.count
        let prevTasks = tasks.filter { $0.isCompleted && $0.updatedAt.hasPrefix(prevPrefix) }.count
        let prevExpenseTotal = records
            .filter { $0.type == "expense" && $0.date.hasPrefix(prevPrefix) && $0.currency == dominant?.code }
            .reduce(0) { $0 + $1.amount }

        func delta(_ current: Double, _ previous: Double) -> Int? {
            guard previous > 0 else { return nil }
            return Int(((current - previous) / previous * 100).rounded())
        }

        return YearStory(
            year: year,
            photosCount: yearPhotos.count,
            tasksDoneCount: doneTasks.count,
            documentsCount: documentsCount,
            expenseCurrency: dominant?.code,
            expenseTotal: dominant?.total ?? 0,
            otherExpenseTotals: Array(totalsByCurrency.dropFirst()),
            firstMemory: firstMemory,
            busiestMonth: busiest,
            biggestExpense: biggestExpense,
            workedSeconds: workedSeconds,
            projectOfYear: projectOfYear,
            topMember: topMember,
            plantsAdded: plantsAdded,
            waterings: wateringsByYear[year] ?? 0,
            valueFirst: valueFirst,
            valueLast: valueLast,
            rentTotals: rentTotals,
            rentPaymentsCount: rentRecords.count,
            streak: year == currentYear ? currentStreak : 0,
            months: months,
            photosDeltaPct: delta(Double(yearPhotos.count), Double(prevPhotos)),
            tasksDeltaPct: delta(Double(doneTasks.count), Double(prevTasks)),
            expensesDeltaPct: delta(dominant?.total ?? 0, prevExpenseTotal)
        )
    }
}

// MARK: - Plant care history (waterings per year)

/// One lightweight fetch of this property's logged watering events, bucketed
/// by year. The per-plant `PlantEventService` loads a single plant's history;
/// the year page needs the whole property's, so it queries the same table
/// directly (the sanctioned feature-level read pattern, cf. ContractorsView).
/// Best-effort: on failure the garden chapter simply shows less — never a
/// made-up number.
enum YearPlantCare {
    static func wateringCounts(propertyId: UUID) async -> [Int: Int] {
        struct Row: Decodable { let at: String }
        let rows: [Row] = (try? await supabase
            .from("plant_events")
            .select("at")
            .eq("property_id", value: propertyId.uuidString)
            .eq("kind", value: "watered")
            .limit(5000)
            .execute().value) ?? []
        var counts: [Int: Int] = [:]
        for row in rows {
            if let y = Int(row.at.prefix(4)) { counts[y, default: 0] += 1 }
        }
        return counts
    }
}
