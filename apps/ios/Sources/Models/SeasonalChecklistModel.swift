import SwiftUI
import Observation

enum Season: String, CaseIterable, Codable {
    case spring
    case summer
    case fall
    case winter

    var displayName: String {
        switch self {
        case .spring: return String(localized: "Spring")
        case .summer: return String(localized: "Summer")
        case .fall:   return String(localized: "Fall")
        case .winter: return String(localized: "Winter")
        }
    }

    /// Definite-article form for history rows — "Primăvara 2025" reads like a
    /// season's name, not a label ("Primăvară 2025" would not).
    var definiteName: String {
        switch self {
        case .spring: return String(localized: "seasonal_def_spring")
        case .summer: return String(localized: "seasonal_def_summer")
        case .fall:   return String(localized: "seasonal_def_fall")
        case .winter: return String(localized: "seasonal_def_winter")
        }
    }

    /// Season-start notification title ("A început primăvara").
    var startNudgeTitle: String {
        switch self {
        case .spring: return String(localized: "seasonal_notif_title_spring")
        case .summer: return String(localized: "seasonal_notif_title_summer")
        case .fall:   return String(localized: "seasonal_notif_title_fall")
        case .winter: return String(localized: "seasonal_notif_title_winter")
        }
    }

    var icon: String {
        switch self {
        case .spring: return "leaf.fill"
        case .summer: return "sun.max.fill"
        case .fall:   return "wind"
        case .winter: return "snowflake"
        }
    }

    var color: Color {
        switch self {
        case .spring: return Color(red: 0.30, green: 0.80, blue: 0.45)
        case .summer: return Color(red: 1.00, green: 0.75, blue: 0.10)
        case .fall:   return Color(red: 0.90, green: 0.45, blue: 0.15)
        case .winter: return Color.brandSkyBlue
        }
    }

    /// First month of the season (meteorological; winter starts in December
    /// and runs into January–February of the next calendar year).
    var startMonth: Int {
        switch self {
        case .spring: return 3
        case .summer: return 6
        case .fall:   return 9
        case .winter: return 12
        }
    }

    var monthRange: ClosedRange<Int> {
        switch self {
        case .spring: return 3...5
        case .summer: return 6...8
        case .fall:   return 9...11
        case .winter: return 12...12
        }
    }

    static var current: Season {
        let month = Calendar.current.component(.month, from: Date())
        if (1...2).contains(month) { return .winter }
        for season in Season.allCases {
            if season.monthRange.contains(month) { return season }
        }
        return .winter
    }

    // MARK: Yearly cycle

    /// The cycle year a check made at `date` belongs to for THIS season.
    /// Convention: the calendar year in which the season's occurrence starts —
    /// so "Iarna 2025" is Dec 2025 – Feb 2026, and a winter check made in
    /// January 2026 still belongs to winter 2025. For every other season the
    /// cycle year is simply the calendar year.
    func cycleYear(containing date: Date = Date(), calendar: Calendar = .current) -> Int {
        let year  = calendar.component(.year,  from: date)
        let month = calendar.component(.month, from: date)
        if self == .winter && month <= 2 { return year - 1 }
        return year
    }

    /// Half-open [start, end) window of this season's occurrence in `year`.
    func window(cycleYear year: Int, calendar: Calendar = .current) -> (start: Date, end: Date)? {
        var comps = DateComponents()
        comps.year = year; comps.month = startMonth; comps.day = 1
        guard let start = calendar.date(from: comps),
              let end = calendar.date(byAdding: .month, value: 3, to: start) else { return nil }
        return (start: start, end: end)
    }

    /// A task due date honestly inside the season: about two weeks out when
    /// the season is running (clamped before its end), otherwise two weeks
    /// into the season's next occurrence.
    func suggestedTaskDueDate(from now: Date = Date(), calendar: Calendar = .current) -> Date {
        let year = cycleYear(containing: now, calendar: calendar)
        guard let window = window(cycleYear: year, calendar: calendar) else { return now }
        if now < window.start {
            return calendar.date(byAdding: .day, value: 14, to: window.start) ?? window.start
        }
        if now < window.end {
            let idea = calendar.date(byAdding: .day, value: 14, to: now) ?? now
            let lastDay = calendar.date(byAdding: .day, value: -1, to: window.end) ?? window.end
            return min(idea, lastDay)
        }
        guard let next = window(cycleYear: year + 1, calendar: calendar) else { return now }
        return calendar.date(byAdding: .day, value: 14, to: next.start) ?? next.start
    }
}

// MARK: - Contextual applicability
//
// Which homes a template check honestly applies to. The mapping (enforced by
// `SeasonalPropertyContext.isApplicable`):
//
// - `.always` — any home: HVAC filters, detectors, water heater, pests,
//   dryer vent, extinguisher, window seals/screens, heating service,
//   weatherstripping, indoor pipes, emergency kit.
// - `.privateExterior` — the home owns its envelope (roof, gutters, chimney,
//   attic, deck, outdoor plumbing, exterior sealing, ice dams). Hidden for
//   `apartment` and `studio` — a unit in a shared building has none of these
//   of its own. Every other kind (house, villa, cabin, land, commercial,
//   other, unknown) keeps them: absence of evidence is not evidence of absence.
// - `.garden` — irrigation. Shown when a garden/greenhouse zone is mapped on
//   the Digital Twin; hidden for apartment/studio without one, and for ANY
//   home whose zones are mapped but include no garden/greenhouse. A house
//   with no zones mapped keeps it (unmapped ≠ nonexistent).
// - `.garage` — garage door checks. Shown when a garage zone is mapped;
//   hidden for apartment/studio without one; house-like homes keep them
//   (no reliable negative signal exists).
//
// Hidden-by-context is always reversible in the UI ("Arată toate verificările").

enum SeasonalContextRequirement: String, Codable {
    case always
    case privateExterior
    case garden
    case garage
}

struct SeasonalPropertyContext: Equatable {
    /// Parsed `properties.property_type`; nil when the stored string is not a
    /// known `PropertyKind` (treated as unknown → nothing exterior is hidden).
    var kind: PropertyKind?
    /// Resolved `SpaceKind`s of the property's mapped Digital Twin zones.
    var mappedSpaceKinds: Set<SpaceKind> = []
    /// Whether ANY zone is mapped — distinguishes "no garden zone among the
    /// mapped zones" (a real signal) from "zones never mapped" (no signal).
    var hasMappedZones = false

    static let unknown = SeasonalPropertyContext()

    /// Apartment or studio: a unit inside a shared building.
    private var isSharedBuildingUnit: Bool { kind == .apartment || kind == .studio }

    func isApplicable(_ requirement: SeasonalContextRequirement) -> Bool {
        switch requirement {
        case .always:
            return true
        case .privateExterior:
            return !isSharedBuildingUnit
        case .garden:
            if mappedSpaceKinds.contains(.garden) || mappedSpaceKinds.contains(.greenhouse) { return true }
            if isSharedBuildingUnit { return false }
            return !hasMappedZones
        case .garage:
            if mappedSpaceKinds.contains(.garage) { return true }
            return !isSharedBuildingUnit
        }
    }
}

// MARK: - Template item

struct SeasonalCheckItem: Identifiable {
    // Stable English keys for IDs and xcstrings lookup
    private let titleKey: String
    private let descriptionKey: String
    private let categoryKey: String
    var season: Season
    /// Which homes this check applies to (see the mapping above).
    let requirement: SeasonalContextRequirement

    // Deterministic ID — stable across locales and app restarts
    var id: String { "\(season.rawValue):\(titleKey)" }

    var title: String { String(localized: String.LocalizationValue(titleKey)) }
    var description: String { String(localized: String.LocalizationValue(descriptionKey)) }
    var category: String { String(localized: String.LocalizationValue(categoryKey)) }

    init(title: String, description: String, category: String, season: Season,
         requirement: SeasonalContextRequirement = .always) {
        self.titleKey = title
        self.descriptionKey = description
        self.categoryKey = category
        self.season = season
        self.requirement = requirement
    }
}

// MARK: - Custom Item

struct CustomSeasonalItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var description: String
    var category: String
    var season: Season

    init(id: UUID = UUID(), title: String, description: String = "", category: String = "Custom", season: Season) {
        self.id = id
        self.title = title
        self.description = description
        self.category = category
        self.season = season
    }
}

// MARK: - Template override (user-edited built-in)

/// User-edited text for a template item. Stored raw (it is the user's own
/// wording); the original localized template stays recoverable via "revert".
struct SeasonalTemplateOverride: Codable, Equatable {
    var title: String
    var description: String
    var category: String
}

// MARK: - Row model (what the list renders)

struct SeasonalRow: Identifiable {
    enum Source {
        case template(SeasonalCheckItem, edited: Bool)
        case custom(CustomSeasonalItem)
    }
    enum HiddenReason {
        /// The user hid this template check.
        case byUser
        /// The check does not apply to this home (property type / zones).
        case byContext
    }

    let id: String
    let title: String
    let description: String
    let category: String
    let source: Source
    let hiddenReason: HiddenReason?

    var isVisible: Bool { hiddenReason == nil }
    var isCustom: Bool { if case .custom = source { return true }; return false }
    var isEditedTemplate: Bool {
        if case .template(_, let edited) = source { return edited }; return false
    }
    var customItem: CustomSeasonalItem? {
        if case .custom(let item) = source { return item }; return nil
    }
}

// MARK: - History

struct SeasonHistoryEntry: Identifiable {
    let season: Season
    let year: Int
    let done: Int
    /// Applicable-item count snapshotted at the last toggle in that season-
    /// year — nil for data migrated from the un-yeared format (no honest
    /// denominator exists for it).
    let total: Int?
    var id: String { "\(season.rawValue):\(year)" }
}

// MARK: - Static data

struct SeasonalChecklistData {
    static let allItems: [SeasonalCheckItem] = [
        // Spring
        SeasonalCheckItem(title: "Replace HVAC filters", description: "Swap out filters after winter heating season.", category: "HVAC", season: .spring),
        SeasonalCheckItem(title: "Clean gutters and downspouts", description: "Remove debris left from winter and early spring leaves.", category: "Exterior", season: .spring, requirement: .privateExterior),
        SeasonalCheckItem(title: "Inspect roof for winter damage", description: "Check for missing or damaged shingles and flashing.", category: "Roof", season: .spring, requirement: .privateExterior),
        SeasonalCheckItem(title: "Test smoke and CO detectors", description: "Replace batteries and verify alarms function correctly.", category: "Safety", season: .spring),
        SeasonalCheckItem(title: "Service AC before summer", description: "Schedule professional tune-up and clean condenser coils.", category: "HVAC", season: .spring),
        SeasonalCheckItem(title: "Check windows and door seals", description: "Inspect weatherstripping and caulking for gaps.", category: "Windows & Doors", season: .spring),
        SeasonalCheckItem(title: "Inspect attic ventilation", description: "Ensure vents are clear and insulation is intact.", category: "Attic", season: .spring, requirement: .privateExterior),
        SeasonalCheckItem(title: "Flush water heater", description: "Drain sediment to improve efficiency and extend lifespan.", category: "Plumbing", season: .spring),

        // Summer
        SeasonalCheckItem(title: "Replace HVAC filters", description: "Change filters mid-summer during peak AC usage.", category: "HVAC", season: .summer),
        SeasonalCheckItem(title: "Check for pests", description: "Inspect for signs of ants, termites, or rodents.", category: "Pest Control", season: .summer),
        SeasonalCheckItem(title: "Inspect deck and patio", description: "Check for rot, loose boards, and structural integrity.", category: "Exterior", season: .summer, requirement: .privateExterior),
        SeasonalCheckItem(title: "Clean dryer vent", description: "Remove lint buildup to prevent fire hazards.", category: "Laundry", season: .summer),
        SeasonalCheckItem(title: "Test fire extinguisher", description: "Verify pressure gauge is in the green and unit is accessible.", category: "Safety", season: .summer),
        SeasonalCheckItem(title: "Inspect garage door springs", description: "Check for wear, rust, and proper balance.", category: "Garage", season: .summer, requirement: .garage),
        SeasonalCheckItem(title: "Check irrigation system", description: "Inspect sprinkler heads and adjust coverage as needed.", category: "Landscaping", season: .summer, requirement: .garden),
        SeasonalCheckItem(title: "Clean window screens", description: "Remove and rinse screens to improve airflow and visibility.", category: "Windows & Doors", season: .summer),

        // Fall
        SeasonalCheckItem(title: "Replace HVAC filters", description: "Prepare the heating system for winter use.", category: "HVAC", season: .fall),
        SeasonalCheckItem(title: "Clean gutters after leaf fall", description: "Clear gutters to prevent ice dams in winter.", category: "Exterior", season: .fall, requirement: .privateExterior),
        SeasonalCheckItem(title: "Inspect and clean chimney", description: "Schedule a professional chimney sweep before first fire.", category: "Chimney", season: .fall, requirement: .privateExterior),
        SeasonalCheckItem(title: "Drain outdoor hoses and pipes", description: "Prevent frozen pipes by disconnecting and draining hoses.", category: "Plumbing", season: .fall, requirement: .privateExterior),
        SeasonalCheckItem(title: "Check attic insulation", description: "Ensure adequate insulation before heating season.", category: "Attic", season: .fall, requirement: .privateExterior),
        SeasonalCheckItem(title: "Service heating system", description: "Schedule furnace or boiler inspection and tune-up.", category: "HVAC", season: .fall),
        SeasonalCheckItem(title: "Test smoke and CO detectors", description: "Replace batteries at daylight saving time change.", category: "Safety", season: .fall),
        SeasonalCheckItem(title: "Seal cracks and gaps", description: "Caulk exterior gaps to prevent cold air intrusion.", category: "Exterior", season: .fall, requirement: .privateExterior),

        // Winter
        SeasonalCheckItem(title: "Check for ice dams", description: "Monitor roof edges and remove snow buildup as needed.", category: "Roof", season: .winter, requirement: .privateExterior),
        SeasonalCheckItem(title: "Replace HVAC filters", description: "Change filters mid-winter during peak heating usage.", category: "HVAC", season: .winter),
        SeasonalCheckItem(title: "Inspect pipes for freezing", description: "Insulate exposed pipes and keep cabinet doors open in cold snaps.", category: "Plumbing", season: .winter),
        SeasonalCheckItem(title: "Test garage door sensors", description: "Check auto-reverse safety feature and lubricate moving parts.", category: "Garage", season: .winter, requirement: .garage),
        SeasonalCheckItem(title: "Check water heater temperature", description: "Set to 120°F for efficiency and scalding prevention.", category: "Plumbing", season: .winter),
        SeasonalCheckItem(title: "Test fire extinguisher", description: "Verify accessibility and pressure gauge reading.", category: "Safety", season: .winter),
        SeasonalCheckItem(title: "Inspect weatherstripping", description: "Replace worn seals on doors and windows to reduce heating costs.", category: "Windows & Doors", season: .winter),
        SeasonalCheckItem(title: "Check emergency kit", description: "Replenish supplies including flashlights, batteries, and blankets.", category: "Safety", season: .winter),
    ]
}

// MARK: - Service
//
// Storage design (honest and local — the template is compiled in, only the
// user's overlay persists):
//
//   UserDefaults key `seasonal_checklist_store_v3.<propertyId>` → one JSON
//   `OverlayStore`: completion ids keyed per YEAR (season lives inside the
//   item id), per-season-year totals snapshots (history denominators), custom
//   items, hidden template ids, template text overrides, item→task links and
//   the "show all" flag. Scoped per property so two homes never share state.
//
// Backward compatibility: the legacy un-yeared, un-scoped keys
// (`seasonal_checklist_completed_v2`, `seasonal_checklist_custom_v1`) are
// migrated into the first property that opens the checklist — legacy states
// are attributed to the CURRENT cycle year of each item's season — and the
// legacy keys are then removed so a second property starts clean instead of
// inheriting another home's checks.

@MainActor
@Observable
final class SeasonalChecklistService {

    private struct OverlayStore: Codable {
        /// "2026" → completed item ids in that cycle year.
        var completedByYear: [String: [String]] = [:]
        /// "spring:2026" → applicable-item count at the last toggle.
        var totals: [String: Int] = [:]
        var customItems: [CustomSeasonalItem] = []
        var hiddenTemplateIds: [String] = []
        var overrides: [String: SeasonalTemplateOverride] = [:]
        /// "2026:spring:Replace HVAC filters" → created maintenance task id.
        var linkedTasks: [String: String] = [:]
        var showAll = false
    }

    private(set) var propertyId: UUID?
    private var store = OverlayStore()

    private enum LegacyKeys {
        static let completed = "seasonal_checklist_completed_v2"
        static let custom    = "seasonal_checklist_custom_v1"
    }
    private var storageKey: String {
        "seasonal_checklist_store_v3.\(propertyId?.uuidString ?? "default")"
    }

    // MARK: Configure / load / persist

    /// Points the service at a property's overlay. Called from the view's
    /// `.task(id:)`, so switching homes re-reads the right store.
    func configure(propertyId: UUID?) {
        self.propertyId = propertyId
        load()
    }

    private func load() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(OverlayStore.self, from: data) {
            store = decoded
            return
        }
        store = OverlayStore()
        migrateLegacyIfNeeded()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(store) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    /// One-time adoption of the pre-v3 global keys (see the class comment).
    private func migrateLegacyIfNeeded() {
        let defaults = UserDefaults.standard
        var migrated = false

        if let data = defaults.data(forKey: LegacyKeys.custom),
           let items = try? JSONDecoder().decode([CustomSeasonalItem].self, from: data) {
            store.customItems = items
            migrated = true
        }
        if let data = defaults.data(forKey: LegacyKeys.completed),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            // Legacy states carry no year — attribute each to the current
            // cycle year of its season (custom ids resolve their season from
            // the migrated custom list; unresolvable ids default to spring's
            // cycle year, i.e. the calendar year).
            let customSeasons = Dictionary(uniqueKeysWithValues:
                store.customItems.map { ("custom:\($0.id.uuidString)", $0.season) })
            for id in ids {
                let season = season(ofItemId: id, customSeasons: customSeasons) ?? .spring
                let year = String(season.cycleYear())
                store.completedByYear[year, default: []].append(id)
            }
            migrated = true
        }
        if migrated {
            persist()
            // Only a real property CONSUMES the legacy keys. The view's
            // `.task(id:)` first runs before properties load (propertyId nil,
            // "default" store) — deleting here would strand the legacy data
            // in that transient store and lose it for the actual home.
            if propertyId != nil {
                defaults.removeObject(forKey: LegacyKeys.completed)
                defaults.removeObject(forKey: LegacyKeys.custom)
            }
        }
    }

    private func season(ofItemId id: String, customSeasons: [String: Season]) -> Season? {
        if let season = customSeasons[id] { return season }
        guard let prefix = id.split(separator: ":").first else { return nil }
        return Season(rawValue: String(prefix))
    }

    // MARK: Rows

    /// Everything the list renders for a season, overrides applied and
    /// visibility resolved against the home's context. Order: template items
    /// first (curated order), then the user's own.
    func rows(for season: Season, context: SeasonalPropertyContext) -> [SeasonalRow] {
        var rows: [SeasonalRow] = SeasonalChecklistData.allItems
            .filter { $0.season == season }
            .map { item in
                let override = store.overrides[item.id]
                let hidden: SeasonalRow.HiddenReason? =
                    store.hiddenTemplateIds.contains(item.id) ? .byUser :
                    (context.isApplicable(item.requirement) ? nil : .byContext)
                return SeasonalRow(
                    id: item.id,
                    title: override?.title ?? item.title,
                    description: override?.description ?? item.description,
                    category: override?.category ?? item.category,
                    source: .template(item, edited: override != nil),
                    hiddenReason: hidden)
            }
        rows += store.customItems
            .filter { $0.season == season }
            .map { item in
                SeasonalRow(
                    id: "custom:\(item.id.uuidString)",
                    title: item.title,
                    description: item.description,
                    category: item.category,
                    source: .custom(item),
                    hiddenReason: nil)
            }
        return rows
    }

    var showAllChecks: Bool {
        get { store.showAll }
        set { store.showAll = newValue; persist() }
    }

    // MARK: Completion (keyed per season's cycle year)

    private func yearKey(for season: Season) -> String { String(season.cycleYear()) }
    private func totalsKey(for season: Season, year: Int) -> String { "\(season.rawValue):\(year)" }

    func isCompleted(_ id: String, season: Season) -> Bool {
        store.completedByYear[yearKey(for: season)]?.contains(id) ?? false
    }

    /// Toggles a check in the season's current cycle year. `applicableTotal`
    /// is the number of visible items right now — snapshotted as the honest
    /// denominator the history row shows once the year has passed.
    func toggleItem(_ id: String, season: Season, applicableTotal: Int) {
        let key = yearKey(for: season)
        var ids = store.completedByYear[key] ?? []
        if let idx = ids.firstIndex(of: id) { ids.remove(at: idx) } else { ids.append(id) }
        store.completedByYear[key] = ids
        store.totals[totalsKey(for: season, year: season.cycleYear())] = applicableTotal
        persist()
    }

    // MARK: Custom item CRUD

    func addCustomItem(_ item: CustomSeasonalItem) {
        store.customItems.append(item)
        persist()
    }

    func updateCustomItem(_ item: CustomSeasonalItem) {
        guard let idx = store.customItems.firstIndex(where: { $0.id == item.id }) else { return }
        store.customItems[idx] = item
        persist()
    }

    func deleteCustomItem(_ item: CustomSeasonalItem) {
        let id = "custom:\(item.id.uuidString)"
        store.customItems.removeAll { $0.id == item.id }
        for (year, ids) in store.completedByYear where ids.contains(id) {
            store.completedByYear[year] = ids.filter { $0 != id }
        }
        persist()
    }

    // MARK: Template personalization

    func hideTemplateItem(_ id: String) {
        guard !store.hiddenTemplateIds.contains(id) else { return }
        store.hiddenTemplateIds.append(id)
        persist()
    }

    func restoreTemplateItem(_ id: String) {
        store.hiddenTemplateIds.removeAll { $0 == id }
        persist()
    }

    func setOverride(_ override: SeasonalTemplateOverride?, forTemplateId id: String) {
        store.overrides[id] = override
        persist()
    }

    // MARK: Item → task links

    private func linkKey(itemId: String, season: Season) -> String {
        "\(season.cycleYear()):\(itemId)"
    }

    func linkTask(_ taskId: UUID, itemId: String, season: Season) {
        store.linkedTasks[linkKey(itemId: itemId, season: season)] = taskId.uuidString
        persist()
    }

    /// The task created from this item in the season's current cycle year.
    /// The link records that a task WAS created ("Task creat") — it does not
    /// claim the task still exists; the view upgrades the label only when the
    /// id resolves in the already-loaded TaskService.
    func linkedTaskId(for itemId: String, season: Season) -> UUID? {
        store.linkedTasks[linkKey(itemId: itemId, season: season)].flatMap(UUID.init(uuidString:))
    }

    // MARK: History

    /// Past season-years with at least one recorded check, newest first.
    /// Custom-item ids resolve their season through the current custom list;
    /// checks of since-deleted custom items are excluded (their season is
    /// unknowable, and `deleteCustomItem` purges them anyway).
    func history(asOf now: Date = Date()) -> [SeasonHistoryEntry] {
        let customSeasons = Dictionary(uniqueKeysWithValues:
            store.customItems.map { ("custom:\($0.id.uuidString)", $0.season) })
        var entries: [SeasonHistoryEntry] = []
        for (yearString, ids) in store.completedByYear {
            guard let year = Int(yearString) else { continue }
            var doneBySeason: [Season: Int] = [:]
            for id in ids {
                guard let season = season(ofItemId: id, customSeasons: customSeasons) else { continue }
                doneBySeason[season, default: 0] += 1
            }
            for (season, done) in doneBySeason where done > 0 {
                guard year < season.cycleYear(containing: now) else { continue }
                let total = store.totals[totalsKey(for: season, year: year)].map { max($0, done) }
                entries.append(SeasonHistoryEntry(season: season, year: year, done: done, total: total))
            }
        }
        let order: [Season: Int] = [.spring: 0, .summer: 1, .fall: 2, .winter: 3]
        return entries.sorted {
            $0.year != $1.year ? $0.year > $1.year
                               : (order[$0.season] ?? 0) > (order[$1.season] ?? 0)
        }
    }
}
