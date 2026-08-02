import Foundation
import Observation

// MARK: - Pantry service
//
// The household's real stock. Receipt scans call `stock(_:propertyId:category:)`
// and the merge engine grows existing rows / creates new ones; the pantry
// page consumes with `adjust`. Hydrates from the offline cache first like
// every other module.

@MainActor
@Observable
final class PantryService {
    var items: [PantryItem] = []
    var isLoading = false
    var error: String?

    // MARK: Computed

    var lowStock: [PantryItem] { items.filter(\.isLow) }

    func items(in category: String) -> [PantryItem] {
        items.filter { $0.category == category }
    }

    // MARK: Load

    func load(propertyId: UUID) async {
        if items.isEmpty, let cached = ServiceCache.load([PantryItem].self, entity: "pantry.items", propertyId: propertyId) {
            items = cached
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched: [PantryItem] = try await PropertyRepo.fetch(
                table: "pantry_items", propertyId: propertyId,
                scope: .strict, ascending: true, limit: 500)
            items = fetched
            ServiceCache.save(items, entity: "pantry.items", propertyId: propertyId)
        } catch {
            self.error = error.recordableDescription
        }
    }

    // MARK: CRUD

    func addItem(_ payload: NewPantryItemPayload) async throws -> PantryItem {
        let inserted: PantryItem = try await supabase
            .from("pantry_items")
            .insert(payload)
            .select().single().execute().value
        items.append(inserted)
        return inserted
    }

    func updateItem(_ item: PantryItem) async {
        let now = ISODate.string(from: Date())
        var updated = item
        updated.updatedAt = now
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = updated }
        let upd = PantryItemUpdate(name: item.name, quantity: max(item.quantity, 0),
                                   unit: item.unit, category: item.category,
                                   minQuantity: item.minQuantity, emoji: item.emoji,
                                   updatedAt: now)
        do {
            try await supabase
                .from("pantry_items").update(upd)
                .eq("id", value: item.id.uuidString).execute()
        } catch { self.error = error.recordableDescription }
    }

    /// Consumption / correction from the pantry page, clamped at zero.
    func adjust(_ item: PantryItem, by delta: Double) async {
        var updated = item
        updated.quantity = max(0, ((item.quantity + delta) * 10).rounded() / 10)
        await updateItem(updated)
    }

    func deleteItem(_ item: PantryItem) async {
        items.removeAll { $0.id == item.id }
        do {
            try await supabase
                .from("pantry_items").delete()
                .eq("id", value: item.id.uuidString).execute()
        } catch { self.error = error.recordableDescription }
    }

    // MARK: Inferred consumption (display-layer only)

    /// Purchase events per lowercased normalized product name, read off the
    /// loaded receipts. Never persisted and never written back — the
    /// server's stored quantities stay authoritative; this only informs
    /// what pantry rows DISPLAY.
    private var purchaseHistory: [String: [PantryConsumptionModel.PurchaseEvent]] = [:]

    /// Rebuilds the purchase-event index from the loaded receipt history.
    /// Receipt items persist under their lexicon-normalized name — the same
    /// string the merge engine keys on when a scan stocks the pantry — so a
    /// lowercased-name join reproduces `PantryMerge`'s matching exactly.
    /// O(receipts + items); call when the receipt history (re)loads, not
    /// per row.
    func indexConsumption(receipts: [Receipt], receiptItems: [ReceiptItem]) {
        var dates: [UUID: Date] = [:]
        dates.reserveCapacity(receipts.count)
        for receipt in receipts {
            dates[receipt.id] = AppDate.day(from: receipt.date)
        }
        var history: [String: [PantryConsumptionModel.PurchaseEvent]] = [:]
        for item in receiptItems {
            guard item.quantity > 0, let date = dates[item.receiptId] else { continue }
            let key = item.name.lowercased()
            guard !key.isEmpty else { continue }
            history[key, default: []].append(.init(date: date, quantity: item.quantity))
        }
        purchaseHistory = history
    }

    /// The full inference for one row — compute once per row render. The
    /// item's `updatedAt` outranks the last purchase as the depletion
    /// anchor: a manual −/+ or sheet edit restarts the clock, because the
    /// household's own numbers beat the model.
    func consumption(for item: PantryItem,
                     asOf now: Date = Date()) -> PantryConsumptionModel.Estimate {
        let events = (purchaseHistory[item.normalizedName.lowercased()] ?? [])
            .map { PantryConsumptionModel.PurchaseEvent(
                date: $0.date,
                quantity: PantryConsumptionModel.baseQuantity($0.quantity,
                                                              pantryUnit: item.unit)) }
        return PantryConsumptionModel.estimate(
            storedQuantity: item.quantity,
            purchases: events,
            asOf: now,
            restockedAt: ISODate.date(from: item.updatedAt))
    }

    /// Stored quantity minus inferred consumption since the last restock —
    /// what the pantry row shows, never what the server stores.
    func effectiveQuantity(for item: PantryItem) -> Double {
        consumption(for: item).effectiveQuantity
    }

    /// Whole days until the effective quantity hits zero; nil when the
    /// purchase history is too thin to infer a pace.
    func daysUntilEmpty(for item: PantryItem) -> Int? {
        consumption(for: item).daysUntilEmpty
    }

    // MARK: Receipt intake

    /// Lands a scanned batch in the pantry: merged by normalized name,
    /// unit-safe, conflicts skipped (never guessed). Returns how many
    /// products were stocked.
    @discardableResult
    func stock(_ additions: [PantryMerge.Addition], propertyId: UUID,
               category: String = "food") async -> Int {
        let plan = PantryMerge.plan(additions: additions, existing: items)
        for inc in plan.increments {
            guard let item = items.first(where: { $0.id == inc.itemId }) else { continue }
            var updated = item
            updated.quantity = ((item.quantity + inc.add) * 10).rounded() / 10
            await updateItem(updated)
        }
        for ins in plan.inserts {
            let payload = NewPantryItemPayload(
                propertyId: propertyId, name: ins.name,
                normalizedName: ins.normalizedName,
                quantity: ins.quantity, unit: ins.unit,
                category: category, minQuantity: nil, emoji: nil)
            _ = try? await addItem(payload)
        }
        if let pid = items.first?.propertyId ?? (plan.inserts.isEmpty ? nil : propertyId) {
            ServiceCache.save(items, entity: "pantry.items", propertyId: pid)
        }
        return plan.increments.count + plan.inserts.count
    }
}
