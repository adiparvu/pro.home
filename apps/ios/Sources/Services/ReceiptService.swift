import Foundation
import Observation
import SwiftUI

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
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f.string(from: date).capitalized
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

    // MARK: - Load

    func load(propertyId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let fr: [Receipt] = supabase
                .from("receipts").select()
                .eq("property_id", value: propertyId.uuidString)
                .order("date", ascending: false).execute().value
            async let fi: [ReceiptItem] = supabase
                .from("receipt_items").select()
                .eq("property_id", value: propertyId.uuidString)
                .order("created_at", ascending: true).execute().value
            async let fb: [HouseholdBudget] = supabase
                .from("household_budgets").select()
                .eq("property_id", value: propertyId.uuidString)
                .order("month", ascending: false).execute().value
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

    func updateReceipt(_ receipt: Receipt) async {
        let now = ISO8601DateFormatter().string(from: Date())
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

    func upsertBudget(propertyId: UUID, category: String, monthlyLimit: Double) async {
        let now = ISO8601DateFormatter().string(from: Date())
        let payload = BudgetUpsertPayload(
            propertyId: propertyId, category: category,
            monthlyLimit: monthlyLimit, month: currentMonthKey,
            createdAt: now, updatedAt: now
        )
        do {
            let upserted: HouseholdBudget = try await supabase
                .from("household_budgets")
                .upsert(payload, onConflict: "property_id,category,month")
                .select().single().execute().value
            if let i = budgets.firstIndex(where: { $0.id == upserted.id }) {
                budgets[i] = upserted
            } else {
                budgets.insert(upserted, at: 0)
            }
        } catch { self.error = error.localizedDescription }
    }

    func deleteBudget(_ budget: HouseholdBudget) async {
        budgets.removeAll { $0.id == budget.id }
        do {
            try await supabase.from("household_budgets").delete()
                .eq("id", value: budget.id.uuidString).execute()
        } catch { self.error = error.localizedDescription }
    }
}
