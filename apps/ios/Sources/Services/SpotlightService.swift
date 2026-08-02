import Foundation
import CoreSpotlight

@MainActor
final class SpotlightService {
    static let shared = SpotlightService()
    private init() {}

    func indexAll(
        tasks: [MaintenanceTask],
        plants: [Plant],
        lists: [SupplyList],
        items: [SupplyItem],
        docs: [DocumentModel]
    ) async {
        var searchableItems: [CSSearchableItem] = []

        for task in tasks where !task.isCompleted {
            let attrs = CSSearchableItemAttributeSet(contentType: .item)
            attrs.title = task.title
            let priorityLabel = task.priority == "high" ? String(localized: "High") : task.priority == "medium" ? String(localized: "Medium") : String(localized: "Low")
            attrs.contentDescription = "\(priorityLabel) · \(task.dueDateDisplay)"
            attrs.keywords = [task.title, task.category, task.priority]
            let item = CSSearchableItem(
                uniqueIdentifier: "task-\(task.id.uuidString)",
                domainIdentifier: "com.prvio.tasks",
                attributeSet: attrs
            )
            item.expirationDate = .distantFuture
            searchableItems.append(item)
        }

        for plant in plants {
            let attrs = CSSearchableItemAttributeSet(contentType: .item)
            attrs.title = "\(plant.emoji) \(plant.name)"
            var descParts: [String] = []
            if let species = plant.species, !species.isEmpty { descParts.append(species) }
            if let location = plant.location, !location.isEmpty { descParts.append(location) }
            if plant.needsWatering { descParts.append(String(localized: "Needs watering")) }
            attrs.contentDescription = descParts.isEmpty ? String(localized: "Plant") : descParts.joined(separator: " · ")
            attrs.keywords = ([plant.name] + [plant.species, plant.location].compactMap { $0 }).filter { !$0.isEmpty }
            let item = CSSearchableItem(
                uniqueIdentifier: "plant-\(plant.id.uuidString)",
                domainIdentifier: "com.prvio.plants",
                attributeSet: attrs
            )
            item.expirationDate = .distantFuture
            searchableItems.append(item)
        }

        for list in lists {
            let attrs = CSSearchableItemAttributeSet(contentType: .item)
            attrs.title = list.name
            let pendingCount = items.filter { $0.listId == list.id && !$0.isCompleted }.count
            attrs.contentDescription = pendingCount > 0 ? String(format: String(localized: "%lld items remaining"), pendingCount) : String(localized: "Complete list")
            attrs.keywords = [list.name]
            let item = CSSearchableItem(
                uniqueIdentifier: "supply-\(list.id.uuidString)",
                domainIdentifier: "com.prvio.supplies",
                attributeSet: attrs
            )
            item.expirationDate = .distantFuture
            searchableItems.append(item)
        }

        for doc in docs {
            let attrs = CSSearchableItemAttributeSet(contentType: .item)
            attrs.title = doc.name
            var descParts: [String] = [doc.category]
            if let expires = doc.expiresAt {
                let f = ISO8601DateFormatter()
                if let d = f.date(from: expires) {
                    let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .none
                    descParts.append(String(format: String(localized: "Expires %@"), df.string(from: d)))
                }
            }
            attrs.contentDescription = descParts.joined(separator: " · ")
            // Search reaches inside scanned documents: the OCR text captured at
            // add time feeds the index — capped keyword terms (folded + original
            // forms, via the same normalization in-app search uses) plus the
            // full body as textContent for Spotlight's own full-text matching.
            // contentDescription stays the curated category/expiry summary so
            // results never surface raw OCR noise as the visible subtitle.
            attrs.keywords = ([doc.name, doc.category] + doc.tags
                              + DocumentSearch.spotlightKeywords(from: doc.ocrText))
            if let ocr = doc.ocrText, !ocr.isEmpty {
                attrs.textContent = ocr
            }
            let item = CSSearchableItem(
                uniqueIdentifier: "doc-\(doc.id.uuidString)",
                domainIdentifier: "com.prvio.documents",
                attributeSet: attrs
            )
            item.expirationDate = .distantFuture
            searchableItems.append(item)
        }

        guard !searchableItems.isEmpty else { return }
        try? await CSSearchableIndex.default().indexSearchableItems(searchableItems)
    }

    func deindexAll() async {
        try? await CSSearchableIndex.default().deleteAllSearchableItems()
    }
}
