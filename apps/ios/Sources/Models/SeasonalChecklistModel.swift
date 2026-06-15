import SwiftUI

enum Season: String, CaseIterable, Codable {
    case spring
    case summer
    case fall
    case winter

    var displayName: String {
        switch self {
        case .spring: return "Spring"
        case .summer: return "Summer"
        case .fall:   return "Fall"
        case .winter: return "Winter"
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
        case .winter: return Color(red: 0.40, green: 0.70, blue: 0.95)
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

struct SeasonalCheckItem: Identifiable, Codable {
    var id: UUID
    var title: String
    var description: String
    var category: String
    var season: Season
}

struct SeasonalChecklistData {
    static let allItems: [SeasonalCheckItem] = [
        // Spring
        SeasonalCheckItem(id: UUID(), title: "Replace HVAC filters", description: "Swap out filters after winter heating season.", category: "HVAC", season: .spring),
        SeasonalCheckItem(id: UUID(), title: "Clean gutters and downspouts", description: "Remove debris left from winter and early spring leaves.", category: "Exterior", season: .spring),
        SeasonalCheckItem(id: UUID(), title: "Inspect roof for winter damage", description: "Check for missing or damaged shingles and flashing.", category: "Roof", season: .spring),
        SeasonalCheckItem(id: UUID(), title: "Test smoke and CO detectors", description: "Replace batteries and verify alarms function correctly.", category: "Safety", season: .spring),
        SeasonalCheckItem(id: UUID(), title: "Service AC before summer", description: "Schedule professional tune-up and clean condenser coils.", category: "HVAC", season: .spring),
        SeasonalCheckItem(id: UUID(), title: "Check windows and door seals", description: "Inspect weatherstripping and caulking for gaps.", category: "Windows & Doors", season: .spring),
        SeasonalCheckItem(id: UUID(), title: "Inspect attic ventilation", description: "Ensure vents are clear and insulation is intact.", category: "Attic", season: .spring),
        SeasonalCheckItem(id: UUID(), title: "Flush water heater", description: "Drain sediment to improve efficiency and extend lifespan.", category: "Plumbing", season: .spring),

        // Summer
        SeasonalCheckItem(id: UUID(), title: "Replace HVAC filters", description: "Change filters mid-summer during peak AC usage.", category: "HVAC", season: .summer),
        SeasonalCheckItem(id: UUID(), title: "Check for pests", description: "Inspect for signs of ants, termites, or rodents.", category: "Pest Control", season: .summer),
        SeasonalCheckItem(id: UUID(), title: "Inspect deck and patio", description: "Check for rot, loose boards, and structural integrity.", category: "Exterior", season: .summer),
        SeasonalCheckItem(id: UUID(), title: "Clean dryer vent", description: "Remove lint buildup to prevent fire hazards.", category: "Laundry", season: .summer),
        SeasonalCheckItem(id: UUID(), title: "Test fire extinguisher", description: "Verify pressure gauge is in the green and unit is accessible.", category: "Safety", season: .summer),
        SeasonalCheckItem(id: UUID(), title: "Inspect garage door springs", description: "Check for wear, rust, and proper balance.", category: "Garage", season: .summer),
        SeasonalCheckItem(id: UUID(), title: "Check irrigation system", description: "Inspect sprinkler heads and adjust coverage as needed.", category: "Landscaping", season: .summer),
        SeasonalCheckItem(id: UUID(), title: "Clean window screens", description: "Remove and rinse screens to improve airflow and visibility.", category: "Windows & Doors", season: .summer),

        // Fall
        SeasonalCheckItem(id: UUID(), title: "Replace HVAC filters", description: "Prepare the heating system for winter use.", category: "HVAC", season: .fall),
        SeasonalCheckItem(id: UUID(), title: "Clean gutters after leaf fall", description: "Clear gutters to prevent ice dams in winter.", category: "Exterior", season: .fall),
        SeasonalCheckItem(id: UUID(), title: "Inspect and clean chimney", description: "Schedule a professional chimney sweep before first fire.", category: "Chimney", season: .fall),
        SeasonalCheckItem(id: UUID(), title: "Drain outdoor hoses and pipes", description: "Prevent frozen pipes by disconnecting and draining hoses.", category: "Plumbing", season: .fall),
        SeasonalCheckItem(id: UUID(), title: "Check attic insulation", description: "Ensure adequate insulation before heating season.", category: "Attic", season: .fall),
        SeasonalCheckItem(id: UUID(), title: "Service heating system", description: "Schedule furnace or boiler inspection and tune-up.", category: "HVAC", season: .fall),
        SeasonalCheckItem(id: UUID(), title: "Test smoke and CO detectors", description: "Replace batteries at daylight saving time change.", category: "Safety", season: .fall),
        SeasonalCheckItem(id: UUID(), title: "Seal cracks and gaps", description: "Caulk exterior gaps to prevent cold air intrusion.", category: "Exterior", season: .fall),

        // Winter
        SeasonalCheckItem(id: UUID(), title: "Check for ice dams", description: "Monitor roof edges and remove snow buildup as needed.", category: "Roof", season: .winter),
        SeasonalCheckItem(id: UUID(), title: "Replace HVAC filters", description: "Change filters mid-winter during peak heating usage.", category: "HVAC", season: .winter),
        SeasonalCheckItem(id: UUID(), title: "Inspect pipes for freezing", description: "Insulate exposed pipes and keep cabinet doors open in cold snaps.", category: "Plumbing", season: .winter),
        SeasonalCheckItem(id: UUID(), title: "Test garage door sensors", description: "Check auto-reverse safety feature and lubricate moving parts.", category: "Garage", season: .winter),
        SeasonalCheckItem(id: UUID(), title: "Check water heater temperature", description: "Set to 120°F for efficiency and scalding prevention.", category: "Plumbing", season: .winter),
        SeasonalCheckItem(id: UUID(), title: "Test fire extinguisher", description: "Verify accessibility and pressure gauge reading.", category: "Safety", season: .winter),
        SeasonalCheckItem(id: UUID(), title: "Inspect weatherstripping", description: "Replace worn seals on doors and windows to reduce heating costs.", category: "Windows & Doors", season: .winter),
        SeasonalCheckItem(id: UUID(), title: "Check emergency kit", description: "Replenish supplies including flashlights, batteries, and blankets.", category: "Safety", season: .winter),
    ]
}

@MainActor
final class SeasonalChecklistService: ObservableObject {
    @Published var completedItemIds: Set<UUID> = []

    private let defaultsKey = "seasonal_checklist_completed_ids"

    init() {
        load()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let ids = try? JSONDecoder().decode([UUID].self, from: data) else { return }
        completedItemIds = Set(ids)
    }

    private func persist() {
        let ids = Array(completedItemIds)
        if let data = try? JSONEncoder().encode(ids) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    func toggleItem(_ id: UUID) {
        if completedItemIds.contains(id) {
            completedItemIds.remove(id)
        } else {
            completedItemIds.insert(id)
        }
        persist()
    }

    func isCompleted(_ id: UUID) -> Bool {
        completedItemIds.contains(id)
    }

    func completedCount(for season: Season) -> Int {
        items(for: season).filter { isCompleted($0.id) }.count
    }

    func items(for season: Season) -> [SeasonalCheckItem] {
        SeasonalChecklistData.allItems.filter { $0.season == season }
    }
}
