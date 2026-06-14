import AppIntents
import Foundation

// MARK: - Task Entity

struct TaskEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Sarcină"
    static var defaultQuery = TaskEntityQuery()

    var id: UUID
    var title: String
    var priority: String

    var displayRepresentation: DisplayRepresentation {
        let icon: String = priority == "high" ? "🔴" : priority == "medium" ? "🟡" : "🟢"
        return DisplayRepresentation(title: "\(icon) \(title)")
    }
}

struct TaskEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [TaskEntity] {
        SharedDataStore.readTaskCatalog()
            .filter { identifiers.contains($0.id) }
            .map { TaskEntity(id: $0.id, title: $0.title, priority: $0.priority) }
    }

    func suggestedEntities() async throws -> [TaskEntity] {
        SharedDataStore.readTaskCatalog()
            .filter { !$0.isCompleted }
            .prefix(8)
            .map { TaskEntity(id: $0.id, title: $0.title, priority: $0.priority) }
    }
}

// MARK: - Plant Entity

struct PlantEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Plantă"
    static var defaultQuery = PlantEntityQuery()

    var id: UUID
    var name: String
    var emoji: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(emoji) \(name)")
    }
}

struct PlantEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [PlantEntity] {
        SharedDataStore.readPlantCatalog()
            .filter { identifiers.contains($0.id) }
            .map { PlantEntity(id: $0.id, name: $0.name, emoji: $0.emoji) }
    }

    func suggestedEntities() async throws -> [PlantEntity] {
        let all = SharedDataStore.readPlantCatalog()
        let needsWater = all.filter { $0.needsWatering }
        return (needsWater.isEmpty ? all : needsWater)
            .prefix(6)
            .map { PlantEntity(id: $0.id, name: $0.name, emoji: $0.emoji) }
    }
}
