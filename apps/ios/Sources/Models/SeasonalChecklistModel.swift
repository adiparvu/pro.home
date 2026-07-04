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
}

struct SeasonalCheckItem: Identifiable {
    // Stable English keys for IDs and xcstrings lookup
    private let titleKey: String
    private let descriptionKey: String
    private let categoryKey: String
    var season: Season

    // Deterministic ID — stable across locales and app restarts
    var id: String { "\(season.rawValue):\(titleKey)" }

    var title: String { String(localized: String.LocalizationValue(titleKey)) }
    var description: String { String(localized: String.LocalizationValue(descriptionKey)) }
    var category: String { String(localized: String.LocalizationValue(categoryKey)) }

    init(title: String, description: String, category: String, season: Season) {
        self.titleKey = title
        self.descriptionKey = description
        self.categoryKey = category
        self.season = season
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

// MARK: - Unified list item (built-in + custom)

enum SeasonalListItem: Identifiable {
    case builtin(SeasonalCheckItem)
    case custom(CustomSeasonalItem)

    var id: String {
        switch self {
        case .builtin(let i): return i.id
        case .custom(let i):  return "custom:\(i.id.uuidString)"
        }
    }
    var title: String {
        switch self { case .builtin(let i): return i.title; case .custom(let i): return i.title }
    }
    var description: String {
        switch self { case .builtin(let i): return i.description; case .custom(let i): return i.description }
    }
    var category: String {
        switch self { case .builtin(let i): return i.category; case .custom(let i): return i.category }
    }
    var isCustom: Bool {
        if case .custom = self { return true }; return false
    }
    var customItem: CustomSeasonalItem? {
        if case .custom(let i) = self { return i }; return nil
    }
}

// MARK: - Static data

struct SeasonalChecklistData {
    static let allItems: [SeasonalCheckItem] = [
        // Spring
        SeasonalCheckItem(title: "Replace HVAC filters", description: "Swap out filters after winter heating season.", category: "HVAC", season: .spring),
        SeasonalCheckItem(title: "Clean gutters and downspouts", description: "Remove debris left from winter and early spring leaves.", category: "Exterior", season: .spring),
        SeasonalCheckItem(title: "Inspect roof for winter damage", description: "Check for missing or damaged shingles and flashing.", category: "Roof", season: .spring),
        SeasonalCheckItem(title: "Test smoke and CO detectors", description: "Replace batteries and verify alarms function correctly.", category: "Safety", season: .spring),
        SeasonalCheckItem(title: "Service AC before summer", description: "Schedule professional tune-up and clean condenser coils.", category: "HVAC", season: .spring),
        SeasonalCheckItem(title: "Check windows and door seals", description: "Inspect weatherstripping and caulking for gaps.", category: "Windows & Doors", season: .spring),
        SeasonalCheckItem(title: "Inspect attic ventilation", description: "Ensure vents are clear and insulation is intact.", category: "Attic", season: .spring),
        SeasonalCheckItem(title: "Flush water heater", description: "Drain sediment to improve efficiency and extend lifespan.", category: "Plumbing", season: .spring),

        // Summer
        SeasonalCheckItem(title: "Replace HVAC filters", description: "Change filters mid-summer during peak AC usage.", category: "HVAC", season: .summer),
        SeasonalCheckItem(title: "Check for pests", description: "Inspect for signs of ants, termites, or rodents.", category: "Pest Control", season: .summer),
        SeasonalCheckItem(title: "Inspect deck and patio", description: "Check for rot, loose boards, and structural integrity.", category: "Exterior", season: .summer),
        SeasonalCheckItem(title: "Clean dryer vent", description: "Remove lint buildup to prevent fire hazards.", category: "Laundry", season: .summer),
        SeasonalCheckItem(title: "Test fire extinguisher", description: "Verify pressure gauge is in the green and unit is accessible.", category: "Safety", season: .summer),
        SeasonalCheckItem(title: "Inspect garage door springs", description: "Check for wear, rust, and proper balance.", category: "Garage", season: .summer),
        SeasonalCheckItem(title: "Check irrigation system", description: "Inspect sprinkler heads and adjust coverage as needed.", category: "Landscaping", season: .summer),
        SeasonalCheckItem(title: "Clean window screens", description: "Remove and rinse screens to improve airflow and visibility.", category: "Windows & Doors", season: .summer),

        // Fall
        SeasonalCheckItem(title: "Replace HVAC filters", description: "Prepare the heating system for winter use.", category: "HVAC", season: .fall),
        SeasonalCheckItem(title: "Clean gutters after leaf fall", description: "Clear gutters to prevent ice dams in winter.", category: "Exterior", season: .fall),
        SeasonalCheckItem(title: "Inspect and clean chimney", description: "Schedule a professional chimney sweep before first fire.", category: "Chimney", season: .fall),
        SeasonalCheckItem(title: "Drain outdoor hoses and pipes", description: "Prevent frozen pipes by disconnecting and draining hoses.", category: "Plumbing", season: .fall),
        SeasonalCheckItem(title: "Check attic insulation", description: "Ensure adequate insulation before heating season.", category: "Attic", season: .fall),
        SeasonalCheckItem(title: "Service heating system", description: "Schedule furnace or boiler inspection and tune-up.", category: "HVAC", season: .fall),
        SeasonalCheckItem(title: "Test smoke and CO detectors", description: "Replace batteries at daylight saving time change.", category: "Safety", season: .fall),
        SeasonalCheckItem(title: "Seal cracks and gaps", description: "Caulk exterior gaps to prevent cold air intrusion.", category: "Exterior", season: .fall),

        // Winter
        SeasonalCheckItem(title: "Check for ice dams", description: "Monitor roof edges and remove snow buildup as needed.", category: "Roof", season: .winter),
        SeasonalCheckItem(title: "Replace HVAC filters", description: "Change filters mid-winter during peak heating usage.", category: "HVAC", season: .winter),
        SeasonalCheckItem(title: "Inspect pipes for freezing", description: "Insulate exposed pipes and keep cabinet doors open in cold snaps.", category: "Plumbing", season: .winter),
        SeasonalCheckItem(title: "Test garage door sensors", description: "Check auto-reverse safety feature and lubricate moving parts.", category: "Garage", season: .winter),
        SeasonalCheckItem(title: "Check water heater temperature", description: "Set to 120°F for efficiency and scalding prevention.", category: "Plumbing", season: .winter),
        SeasonalCheckItem(title: "Test fire extinguisher", description: "Verify accessibility and pressure gauge reading.", category: "Safety", season: .winter),
        SeasonalCheckItem(title: "Inspect weatherstripping", description: "Replace worn seals on doors and windows to reduce heating costs.", category: "Windows & Doors", season: .winter),
        SeasonalCheckItem(title: "Check emergency kit", description: "Replenish supplies including flashlights, batteries, and blankets.", category: "Safety", season: .winter),
    ]
}

@MainActor
@Observable
final class SeasonalChecklistService {
    var completedItemIds: Set<String> = []
    var customItems: [CustomSeasonalItem] = []

    private let defaultsKey  = "seasonal_checklist_completed_v2"
    private let customKey    = "seasonal_checklist_custom_v1"

    init() { load(); loadCustom() }

    // MARK: - Completion

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return }
        completedItemIds = Set(ids)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(Array(completedItemIds)) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    func toggleItem(_ id: String) {
        if completedItemIds.contains(id) { completedItemIds.remove(id) }
        else { completedItemIds.insert(id) }
        persist()
    }

    func isCompleted(_ id: String) -> Bool { completedItemIds.contains(id) }

    // MARK: - Built-in items

    func builtinItems(for season: Season) -> [SeasonalCheckItem] {
        SeasonalChecklistData.allItems.filter { $0.season == season }
    }

    // MARK: - Custom item CRUD

    private func loadCustom() {
        guard let data = UserDefaults.standard.data(forKey: customKey),
              let items = try? JSONDecoder().decode([CustomSeasonalItem].self, from: data) else { return }
        customItems = items
    }

    private func persistCustom() {
        if let data = try? JSONEncoder().encode(customItems) {
            UserDefaults.standard.set(data, forKey: customKey)
        }
    }

    func customItems(for season: Season) -> [CustomSeasonalItem] {
        customItems.filter { $0.season == season }
    }

    func addCustomItem(_ item: CustomSeasonalItem) {
        customItems.append(item)
        persistCustom()
    }

    func updateCustomItem(_ item: CustomSeasonalItem) {
        if let idx = customItems.firstIndex(where: { $0.id == item.id }) {
            customItems[idx] = item
            persistCustom()
        }
    }

    func deleteCustomItem(_ item: CustomSeasonalItem) {
        completedItemIds.remove("custom:\(item.id.uuidString)")
        customItems.removeAll { $0.id == item.id }
        persist()
        persistCustom()
    }

    // MARK: - Unified list

    func allListItems(for season: Season) -> [SeasonalListItem] {
        builtinItems(for: season).map { .builtin($0) } +
        customItems(for: season).map { .custom($0) }
    }

    func completedCount(for season: Season) -> Int {
        allListItems(for: season).filter { isCompleted($0.id) }.count
    }

    func totalCount(for season: Season) -> Int {
        allListItems(for: season).count
    }

    // Legacy alias kept for compatibility
    func items(for season: Season) -> [SeasonalCheckItem] { builtinItems(for: season) }
}
