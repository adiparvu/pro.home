import Foundation
import Observation
import SwiftUI
import UIKit
import Supabase

@MainActor
@Observable
final class ReceiptService {
    var receipts: [Receipt] = []
    var receiptItems: [ReceiptItem] = []
    var budgets: [HouseholdBudget] = []
    var isLoading = false
    var error: String?

    private let isoDate: DateFormatter = AppDate.day
    private let monthFormatter: DateFormatter = AppDate.monthKey

    // MARK: - Computed

    var currentMonthKey: String { monthFormatter.string(from: Date()) }

    func previousMonthKey(from key: String) -> String {
        guard let date = monthFormatter.date(from: key),
              let prev = Calendar.current.date(byAdding: .month, value: -1, to: date)
        else { return key }
        return monthFormatter.string(from: prev)
    }

    func nextMonthKey(from key: String) -> String {
        guard let date = monthFormatter.date(from: key),
              let next = Calendar.current.date(byAdding: .month, value: 1, to: date)
        else { return key }
        let nextKey = monthFormatter.string(from: next)
        return nextKey <= currentMonthKey ? nextKey : key
    }

    func monthDisplayName(_ key: String) -> String {
        guard let date = monthFormatter.date(from: key) else { return key }
        return AppDateDisplay.fullMonthYear.string(from: date).capitalized
    }

    func receiptsForMonth(_ monthKey: String) -> [Receipt] {
        receipts.filter { $0.date.hasPrefix(monthKey) }
    }

    func totalSpent(in monthKey: String) -> Double {
        receiptsForMonth(monthKey).reduce(0) { $0 + $1.total }
    }

    func spendByDay(in monthKey: String) -> [DailySpend] {
        let monthReceipts = receiptsForMonth(monthKey)
        var grouped: [String: Double] = [:]
        for r in monthReceipts { grouped[r.date, default: 0] += r.total }
        return grouped.compactMap { (dateStr, total) -> DailySpend? in
            guard let date = isoDate.date(from: dateStr) else { return nil }
            return DailySpend(id: dateStr, date: date, total: total)
        }
        .sorted { $0.date < $1.date }
    }

    func spendByCategory(in monthKey: String) -> [CategorySpend] {
        var grouped: [String: Double] = [:]
        for r in receiptsForMonth(monthKey) { grouped[r.category, default: 0] += r.total }
        return grouped.map { CategorySpend(id: $0.key, category: $0.key, total: $0.value) }
            .sorted { $0.total > $1.total }
    }

    func spendByWeek(in monthKey: String) -> [DailySpend] {
        let cal = Calendar.current
        let monthReceipts = receiptsForMonth(monthKey)
        var grouped: [Int: (date: Date, total: Double)] = [:]
        for r in monthReceipts {
            guard let date = isoDate.date(from: r.date) else { continue }
            let week = cal.component(.weekOfYear, from: date)
            grouped[week] = (date: grouped[week]?.date ?? date, total: (grouped[week]?.total ?? 0) + r.total)
        }
        return grouped.map { DailySpend(id: "\($0.key)", date: $0.value.date, total: $0.value.total) }
            .sorted { $0.date < $1.date }
    }

    func spendForYear(_ year: Int) -> [DailySpend] {
        var grouped: [String: (date: Date, total: Double)] = [:]
        let filtered = receipts.filter { $0.date.hasPrefix("\(year)") }
        for r in filtered {
            let key = String(r.date.prefix(7))
            guard let date = AppDate.monthKey.date(from: key) else { continue }
            grouped[key] = (date: grouped[key]?.date ?? date, total: (grouped[key]?.total ?? 0) + r.total)
        }
        return grouped.map { DailySpend(id: $0.key, date: $0.value.date, total: $0.value.total) }
            .sorted { $0.date < $1.date }
    }

    func items(for receiptId: UUID) -> [ReceiptItem] {
        receiptItems.filter { $0.receiptId == receiptId }
    }

    func budget(for category: String, month: String) -> HouseholdBudget? {
        budgets.first { $0.category == category && $0.month == month }
    }

    func spent(for category: String, in monthKey: String) -> Double {
        receiptsForMonth(monthKey).filter { $0.category == category }.reduce(0) { $0 + $1.total }
    }

    func recurringItems(months: Int = 3) -> [RecurringItem] {
        guard let cutoff = Calendar.current.date(byAdding: .month, value: -months, to: Date()) else { return [] }
        let recentItems = receiptItems.filter { item in
            guard let receipt = receipts.first(where: { $0.id == item.receiptId }) else { return false }
            return (isoDate.date(from: receipt.date) ?? Date()) >= cutoff
        }
        var grouped: [String: (prices: [Double], lastDate: Date)] = [:]
        for item in recentItems {
            let key = item.name.lowercased().trimmingCharacters(in: .whitespaces)
            let date = receipts.first(where: { $0.id == item.receiptId }).flatMap { isoDate.date(from: $0.date) } ?? Date()
            var entry = grouped[key] ?? (prices: [], lastDate: date)
            entry.prices.append(item.totalPrice)
            if date > entry.lastDate { entry.lastDate = date }
            grouped[key] = entry
        }
        return grouped
            .filter { $0.value.prices.count >= 2 }
            .map { (key, val) in
                let avg = val.prices.reduce(0, +) / Double(val.prices.count)
                return RecurringItem(id: key, name: key.capitalized, count: val.prices.count, avgPrice: avg, lastDate: val.lastDate)
            }
            .sorted { $0.count > $1.count }
            .prefix(10).map { $0 }
    }

    func priceHistory(for itemName: String) -> [(date: Date, price: Double)] {
        let key = itemName.lowercased().trimmingCharacters(in: .whitespaces)
        return receiptItems
            .filter { $0.name.lowercased().trimmingCharacters(in: .whitespaces) == key }
            .compactMap { item -> (Date, Double)? in
                guard let receipt = receipts.first(where: { $0.id == item.receiptId }),
                      let date = isoDate.date(from: receipt.date) else { return nil }
                return (date, item.unitPrice > 0 ? item.unitPrice : item.totalPrice)
            }
            .sorted { $0.0 < $1.0 }
    }

    // MARK: - Price history (per product, lexicon-normalized)

    /// Every real purchase of `productName` read off scanned receipts,
    /// newest first. Matching goes through the product lexicon so
    /// "Lapte Zuzu 1.5%" and "Milk" land on the same product; nothing is
    /// interpolated — every entry is a line that exists on a stored receipt.
    func priceEntries(matching productName: String) -> [ProductPriceEntry] {
        let target = ReceiptProductLexicon.fold(
            ReceiptProductLexicon.normalize(productName))
        guard !target.isEmpty else { return [] }
        let receiptsById = Dictionary(uniqueKeysWithValues: receipts.map { ($0.id, $0) })
        return receiptItems.compactMap { item -> ProductPriceEntry? in
            let itemKey = ReceiptProductLexicon.fold(
                ReceiptProductLexicon.normalize(item.name))
            guard itemKey == target
                || ReceiptProductLexicon.match(item.name, against: productName)
                    >= ReceiptProductLexicon.matchThreshold else { return nil }
            guard let receipt = receiptsById[item.receiptId],
                  let date = isoDate.date(from: receipt.date) else { return nil }
            return ProductPriceEntry(
                id: item.id,
                date: date,
                price: item.unitPrice > 0 ? item.unitPrice : item.totalPrice,
                store: receipt.storeName,
                receipt: receipt)
        }
        .sorted { $0.date > $1.date }
    }

    /// All scanned products grouped by their lexicon-normalized name,
    /// each with its purchase entries (newest first). Ordered by purchase
    /// count, then recency — the products the household actually tracks.
    func productPriceGroups() -> [ProductPriceGroup] {
        let receiptsById = Dictionary(uniqueKeysWithValues: receipts.map { ($0.id, $0) })
        var groups: [String: (display: String, entries: [ProductPriceEntry])] = [:]
        for item in receiptItems {
            let display = ReceiptProductLexicon.normalize(item.name)
            let key = ReceiptProductLexicon.fold(display)
            guard !key.isEmpty,
                  let receipt = receiptsById[item.receiptId],
                  let date = isoDate.date(from: receipt.date) else { continue }
            let entry = ProductPriceEntry(
                id: item.id,
                date: date,
                price: item.unitPrice > 0 ? item.unitPrice : item.totalPrice,
                store: receipt.storeName,
                receipt: receipt)
            groups[key, default: (display, [])].entries.append(entry)
        }
        return groups.map { key, value in
            ProductPriceGroup(id: key,
                              name: value.display,
                              entries: value.entries.sorted { $0.date > $1.date })
        }
        .sorted {
            if $0.entries.count != $1.entries.count {
                return $0.entries.count > $1.entries.count
            }
            return ($0.entries.first?.date ?? .distantPast)
                 > ($1.entries.first?.date ?? .distantPast)
        }
    }

    /// The most frequently scanned product names (lexicon-normalized),
    /// excluding anything that already matches a name in `excluding` —
    /// real purchase history only, for "you buy this often" suggestions.
    func frequentProducts(excluding excludedNames: [String], limit: Int = 6) -> [String] {
        let groups = productPriceGroups()
        guard !groups.isEmpty else { return [] }
        let excludedKeys = Set(excludedNames.map {
            ReceiptProductLexicon.fold(ReceiptProductLexicon.normalize($0))
        })
        return groups
            .filter { group in
                guard !excludedKeys.contains(group.id) else { return false }
                return !excludedNames.contains {
                    ReceiptProductLexicon.match(group.name, against: $0)
                        >= ReceiptProductLexicon.matchThreshold
                }
            }
            .prefix(limit)
            .map(\.name)
    }

    // MARK: - Load

    func load(propertyId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let fr: [Receipt] = PropertyRepo.fetch(
                table: "receipts", propertyId: propertyId,
                scope: .strict, order: "date", limit: 1000)
            async let fi: [ReceiptItem] = PropertyRepo.fetch(
                table: "receipt_items", propertyId: propertyId,
                scope: .strict, ascending: true, limit: 1000)
            async let fb: [HouseholdBudget] = PropertyRepo.fetch(
                table: "household_budgets", propertyId: propertyId,
                scope: .strict, order: "month", limit: 500)
            receipts = try await fr
            receiptItems = try await fi
            budgets = try await fb
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Receipts CRUD

    @discardableResult
    func addReceipt(_ payload: NewReceiptPayload, items: [NewReceiptItemPayload]) async throws -> Receipt {
        let inserted: Receipt = try await supabase
            .from("receipts").insert(payload).select().single().execute().value

        if !items.isEmpty {
            let adjusted = items.map { item -> NewReceiptItemPayload in
                var copy = item
                copy.receiptId = inserted.id
                return copy
            }
            let insertedItems: [ReceiptItem] = try await supabase
                .from("receipt_items").insert(adjusted).select().execute().value
            receiptItems.append(contentsOf: insertedItems)
        }
        receipts.insert(inserted, at: 0)
        return inserted
    }

    // MARK: - Receipt image (private, property-scoped `receipt-media` bucket)

    private static let mediaBucket = "receipt-media"

    /// Uploads a receipt photo to the private receipt-media bucket and returns
    /// its storage path (`{propertyId}/{uuid}.jpg`), or nil on failure. The
    /// path is stored in the receipt's `image_url`; reads resolve short-lived
    /// signed URLs (the same pattern plant/chat media use).
    func uploadReceiptImage(_ image: UIImage, propertyId: UUID) async -> String? {
        guard let data = image.uploadJPEG(quality: 0.8, maxDimension: 2048) else { return nil }
        let path = "\(propertyId.uuidString)/\(UUID().uuidString).jpg"
        do {
            try await supabase.storage.from(Self.mediaBucket)
                .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: false))
            return path
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    /// Resolves a stored receipt-image path to a displayable signed URL (legacy
    /// full URLs pass through), cached under the signing window.
    static func resolveImage(_ stored: String) async -> URL? {
        if stored.hasPrefix("http") { return URL(string: stored) }
        if let cached = await ReceiptURLCache.shared.get(stored) { return cached }
        guard let url = try? await supabase.storage.from(mediaBucket)
            .createSignedURL(path: stored, expiresIn: 3600) else { return nil }
        await ReceiptURLCache.shared.set(stored, url: url)
        return url
    }

    func updateReceipt(_ receipt: Receipt) async {
        let now = ISODate.string(from: Date())
        let payload = NewReceiptPayload(
            propertyId: receipt.propertyId,
            storeName: receipt.storeName,
            date: receipt.date,
            total: receipt.total,
            category: receipt.category,
            imageUrl: receipt.imageUrl,
            notes: receipt.notes,
            createdAt: receipt.createdAt,
            updatedAt: now
        )
        do {
            let updated: Receipt = try await supabase
                .from("receipts").update(payload)
                .eq("id", value: receipt.id.uuidString)
                .select().single().execute().value
            if let i = receipts.firstIndex(where: { $0.id == receipt.id }) { receipts[i] = updated }
        } catch { self.error = error.localizedDescription }
    }

    func deleteReceipt(_ receipt: Receipt) async {
        receipts.removeAll { $0.id == receipt.id }
        receiptItems.removeAll { $0.receiptId == receipt.id }
        do {
            try await supabase.from("receipts").delete()
                .eq("id", value: receipt.id.uuidString).execute()
        } catch { self.error = error.localizedDescription }
    }

    // MARK: - Budgets

    @discardableResult
    func upsertBudget(propertyId: UUID, category: String, monthlyLimit: Double) async -> Bool {
        let month = currentMonthKey
        let now = ISODate.string(from: Date())
        let payload = BudgetUpsertPayload(
            propertyId: propertyId, category: category,
            monthlyLimit: monthlyLimit, month: month,
            createdAt: now, updatedAt: now
        )
        do {
            // Write only — do NOT decode a `.select().single()` return. The
            // read-back couples the write's success to a second round-trip and
            // to decoding the row shape; a hiccup there used to look like the
            // save silently failing. We upsert, then reflect the value locally
            // and reconcile ids from a reload.
            try await supabase
                .from("household_budgets")
                .upsert(payload, onConflict: "property_id,category,month")
                .execute()
            error = nil
            if let i = budgets.firstIndex(where: {
                $0.propertyId == propertyId && $0.category == category && $0.month == month
            }) {
                budgets[i].monthlyLimit = monthlyLimit
                budgets[i].updatedAt = now
            } else {
                await loadBudgets(propertyId: propertyId)
            }
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    /// Re-fetch just the budgets for a property (used after an insert to pick
    /// up the server-assigned id without reloading receipts).
    func loadBudgets(propertyId: UUID) async {
        do {
            budgets = try await PropertyRepo.fetch(
                table: "household_budgets", propertyId: propertyId,
                scope: .strict, order: "month", limit: 500)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteBudget(_ budget: HouseholdBudget) async {
        budgets.removeAll { $0.id == budget.id }
        do {
            try await supabase.from("household_budgets").delete()
                .eq("id", value: budget.id.uuidString).execute()
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Price history models

/// One real purchase of a product, read off a stored receipt line.
struct ProductPriceEntry: Identifiable {
    let id: UUID
    let date: Date
    /// Unit price when the receipt states one; otherwise the line total.
    let price: Double
    let store: String
    let receipt: Receipt
}

/// A product (lexicon-normalized name) with all its scanned purchases,
/// newest first.
struct ProductPriceGroup: Identifiable {
    let id: String        // folded normalized name
    let name: String
    let entries: [ProductPriceEntry]
}

// MARK: - Signed-URL cache for receipt images

private actor ReceiptURLCache {
    static let shared = ReceiptURLCache()
    private var entries: [String: (url: URL, expiresAt: Date)] = [:]
    private let ttl: TimeInterval = 50 * 60

    func get(_ key: String) -> URL? {
        guard let e = entries[key], e.expiresAt > Date() else { return nil }
        return e.url
    }
    func set(_ key: String, url: URL) {
        entries[key] = (url, Date().addingTimeInterval(ttl))
    }
}
