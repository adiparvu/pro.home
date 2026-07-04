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
        isLoading = true
        defer { isLoading = false }
        do {
            async let fetchedLists: [SupplyList] = supabase
                .from("supply_lists")
                .select()
                .eq("property_id", value: propertyId.uuidString)
                .order("created_at", ascending: true)
                .execute().value
            async let fetchedItems: [SupplyItem] = supabase
                .from("supply_items")
                .select()
                .eq("property_id", value: propertyId.uuidString)
                .order("created_at", ascending: true)
                .execute().value
            lists = try await fetchedLists
            items = try await fetchedItems
        } catch {
            self.error = error.localizedDescription
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
        let now = ISO8601DateFormatter().string(from: Date())
        let upd = SupplyListUpdate(name: list.name, icon: list.icon,
                                   color: list.color, note: list.note, updatedAt: now)
        do {
            let updated: SupplyList = try await supabase
                .from("supply_lists")
                .update(upd)
                .eq("id", value: list.id.uuidString)
                .select().single().execute().value
            if let i = lists.firstIndex(where: { $0.id == list.id }) { lists[i] = updated }
        } catch { self.error = error.localizedDescription }
    }

    func deleteList(_ list: SupplyList) async {
        lists.removeAll { $0.id == list.id }
        items.removeAll { $0.listId == list.id }
        do {
            try await supabase
                .from("supply_lists").delete()
                .eq("id", value: list.id.uuidString).execute()
        } catch { self.error = error.localizedDescription }
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
        let now = ISO8601DateFormatter().string(from: Date())
        let upd = SupplyItemUpdate(name: item.name, quantity: item.quantity,
                                   category: item.category, priority: item.priority,
                                   notes: item.notes, isCompleted: item.isCompleted,
                                   location: item.location, updatedAt: now)
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item }
        do {
            try await supabase
                .from("supply_items").update(upd)
                .eq("id", value: item.id.uuidString).execute()
        } catch { self.error = error.localizedDescription }
    }

    func toggleComplete(_ item: SupplyItem) async {
        var updated = item
        updated.isCompleted.toggle()
        updated.updatedAt = ISO8601DateFormatter().string(from: Date())
        await updateItem(updated)
        // Keep the shopping Live Activity in sync with this list's progress.
        let listId = item.listId
        let listName = lists.first { $0.id == listId }?.name ?? String(localized: "Shopping list")
        LiveActivityService.shared.syncShopping(
            listName: listName,
            bought: completedCount(for: listId),
            total: items(for: listId).count)
    }

    func deleteItem(_ item: SupplyItem) async {
        items.removeAll { $0.id == item.id }
        do {
            try await supabase
                .from("supply_items").delete()
                .eq("id", value: item.id.uuidString).execute()
        } catch { self.error = error.localizedDescription }
    }
}
