import Foundation
import Observation

@MainActor
@Observable
final class SupplyService {
    var lists: [SupplyList] = []
    var items: [SupplyItem] = []
    var isLoading = false
    var error: String?

    // MARK: Computed

    func items(for listId: UUID) -> [SupplyItem] {
        items.filter { $0.listId == listId }
    }

    func pendingCount(for listId: UUID) -> Int {
        items(for: listId).filter { !$0.isCompleted }.count
    }

    func completedCount(for listId: UUID) -> Int {
        items(for: listId).filter { $0.isCompleted }.count
    }

    var totalPending: Int { items.filter { !$0.isCompleted }.count }
    var totalCompleted: Int { items.filter { $0.isCompleted }.count }

    // MARK: Load

    func load(propertyId: UUID) async {
        // Paint the last known state instantly; the network refresh follows.
        if lists.isEmpty, let cached = ServiceCache.load([SupplyList].self, entity: "supplies.lists", propertyId: propertyId) {
            lists = cached
        }
        if items.isEmpty, let cached = ServiceCache.load([SupplyItem].self, entity: "supplies.items", propertyId: propertyId) {
            items = cached
        }
        isLoading = true
        defer { isLoading = false }
        do {
            async let fetchedLists: [SupplyList] = PropertyRepo.fetch(
                table: "supply_lists", propertyId: propertyId,
                scope: .strict, ascending: true, limit: 500)
            async let fetchedItems: [SupplyItem] = PropertyRepo.fetch(
                table: "supply_items", propertyId: propertyId,
                scope: .strict, ascending: true, limit: 1000)
            lists = try await fetchedLists
            items = try await fetchedItems
            ServiceCache.save(lists, entity: "supplies.lists", propertyId: propertyId)
            ServiceCache.save(items, entity: "supplies.items", propertyId: propertyId)
        } catch {
            self.error = error.recordableDescription
        }
    }

    // MARK: Lists

    func addList(_ payload: NewSupplyListPayload) async throws -> SupplyList {
        let inserted: SupplyList = try await supabase
            .from("supply_lists")
            .insert(payload)
            .select()
            .single()
            .execute().value
        lists.append(inserted)
        return inserted
    }

    func updateList(_ list: SupplyList) async {
        let now = ISODate.string(from: Date())
        let upd = SupplyListUpdate(name: list.name, icon: list.icon,
                                   color: list.color, note: list.note, updatedAt: now)
        do {
            let updated: SupplyList = try await supabase
                .from("supply_lists")
                .update(upd)
                .eq("id", value: list.id.uuidString)
                .select().single().execute().value
            if let i = lists.firstIndex(where: { $0.id == list.id }) { lists[i] = updated }
        } catch { self.error = error.recordableDescription }
    }

    func deleteList(_ list: SupplyList) async {
        lists.removeAll { $0.id == list.id }
        items.removeAll { $0.listId == list.id }
        do {
            try await supabase
                .from("supply_lists").delete()
                .eq("id", value: list.id.uuidString).execute()
        } catch { self.error = error.recordableDescription }
    }

    // MARK: Items

    func addItem(_ payload: NewSupplyItemPayload) async throws -> SupplyItem {
        let inserted: SupplyItem = try await supabase
            .from("supply_items")
            .insert(payload)
            .select().single().execute().value
        items.insert(inserted, at: 0)
        return inserted
    }

    func updateItem(_ item: SupplyItem) async {
        let now = ISODate.string(from: Date())
        let upd = SupplyItemUpdate(name: item.name, quantity: item.quantity,
                                   category: item.category, priority: item.priority,
                                   notes: item.notes, isCompleted: item.isCompleted,
                                   location: item.location, updatedAt: now)
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item }
        do {
            try await supabase
                .from("supply_items").update(upd)
                .eq("id", value: item.id.uuidString).execute()
        } catch { self.error = error.recordableDescription }
    }

    func toggleComplete(_ item: SupplyItem) async {
        var updated = item
        updated.isCompleted.toggle()
        updated.updatedAt = ISODate.string(from: Date())
        await updateItem(updated)
        // Checking OFF (never unchecking) is donated so Siri Suggestions
        // learn the shopping rhythm.
        if updated.isCompleted {
            SiriDonations.supplyChecked(id: item.id, name: item.name)
        }
        // Keep the shopping Live Activity in sync with this list's progress.
        let listId = item.listId
        let listName = lists.first { $0.id == listId }?.name ?? String(localized: "Shopping list")
        // Publish the next still-unbought item so the island's check-off button
        // acts on a real, list-scoped id (the shared catalog isn't list-scoped).
        let next = items(for: listId).first { !$0.isCompleted }
        LiveActivityService.shared.syncShopping(
            listName: listName,
            bought: completedCount(for: listId),
            total: items(for: listId).count,
            nextItemId: next?.id,
            nextItemName: next?.name)
    }

    func deleteItem(_ item: SupplyItem) async {
        items.removeAll { $0.id == item.id }
        do {
            try await supabase
                .from("supply_items").delete()
                .eq("id", value: item.id.uuidString).execute()
        } catch { self.error = error.recordableDescription }
    }
}
