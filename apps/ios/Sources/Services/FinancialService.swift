import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class FinancialService {
    var records: [FinancialRecord] = []
    var isLoading = false
    var error: String?

    private var realtimeChannel: RealtimeChannelV2?
    private var subscribedPropertyId: UUID?
    private var postgresSubs: [RealtimeSubscription] = []
    private var realtimeReload: Task<Void, Never>?

    // MARK: - Computed stats

    var currentMonthRecords: [FinancialRecord] {
        let cal = Calendar.current
        let now = Date()
        guard let first = cal.date(from: cal.dateComponents([.year, .month], from: now)) else { return [] }
        return records.filter { r in
            guard let d = AppDate.day(from: r.date) else { return false }
            return d >= first && d <= now
        }
    }

    var currentMonthIncome: Double {
        currentMonthRecords.filter { $0.type == "income" }.reduce(0) { $0 + $1.amount }
    }
    var currentMonthExpenses: Double {
        currentMonthRecords.filter { $0.type == "expense" }.reduce(0) { $0 + $1.amount }
    }
    var currentMonthNet: Double { currentMonthIncome - currentMonthExpenses }

    // Last 6 months grouped by month
    var monthlyData: [(month: String, income: Double, expenses: Double)] {
        let cal = Calendar.current
        let now = Date()

        return (0..<6).reversed().compactMap { offset -> (String, Double, Double)? in
            guard let monthDate = cal.date(byAdding: .month, value: -offset, to: now),
                  let first = cal.date(from: cal.dateComponents([.year, .month], from: monthDate)),
                  let last = cal.date(byAdding: .month, value: 1, to: first) else { return nil }
            let monthRecords = records.filter { r in
                guard let d = AppDate.day(from: r.date) else { return false }
                return d >= first && d < last
            }
            let income = monthRecords.filter { $0.type == "income" }.reduce(0) { $0 + $1.amount }
            let expenses = monthRecords.filter { $0.type == "expense" }.reduce(0) { $0 + $1.amount }
            return (AppDate.monthLabel.string(from: first), income, expenses)
        }
    }

    var recentRecords: [FinancialRecord] { Array(records.prefix(5)) }

    var currency: String { records.first?.currency ?? "EUR" }
    var currencySymbol: String { CurrencyService.symbol(for: currency) }

    /// The one way to show an aggregate amount in the household's currency —
    /// locale-aware grouping and symbol placement, rounded, never truncated.
    func moneyDisplay(_ amount: Double, whole: Bool = true) -> String {
        CurrencyService.money(amount, code: currency, whole: whole)
    }

    func load() async {
        let pid = PropertyService.activePropertyId
        // Paint the last known state instantly; the network refresh follows.
        if records.isEmpty, let cached = ServiceCache.load([FinancialRecord].self, entity: "financial", propertyId: pid) {
            records = cached
        }
        isLoading = true
        defer { isLoading = false }
        do {
            var query = supabase.from("financial_records").select()
            if let pid {
                // Scope to the selected home; legacy rows without a property
                // stay visible rather than silently disappearing.
                query = query.or("property_id.eq.\(pid.uuidString),property_id.is.null")
            }
            records = try await query
                .order("date", ascending: false)
                .limit(1000)   // explicit cap — PostgREST truncates silently without one
                .execute()
                .value
            ServiceCache.save(records, entity: "financial", propertyId: pid)
        } catch {
            if error is CancellationError { return }
            self.error = error.localizedDescription
        }
        if let pid { await subscribeRealtime(propertyId: pid) }
    }

    // MARK: - Live family sync
    //
    // An expense added on one phone shows up on every family member's phone
    // in seconds. Events are coalesced so a burst of changes costs one reload.

    private func subscribeRealtime(propertyId: UUID) async {
        guard subscribedPropertyId != propertyId else { return }
        if let ch = realtimeChannel {
            await supabase.realtimeV2.removeChannel(ch)
            realtimeChannel = nil
            postgresSubs.removeAll()
        }
        let channel = supabase.realtimeV2.channel("financial_records:\(propertyId.uuidString)")
        postgresSubs.append(channel.onPostgresChange(
            AnyAction.self,
            schema: "public",
            table: "financial_records",
            filter: "property_id=eq.\(propertyId.uuidString)"
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleRealtimeReload() }
        })
        try? await channel.subscribeWithError()
        realtimeChannel = channel
        subscribedPropertyId = propertyId
    }

    private func scheduleRealtimeReload() {
        realtimeReload?.cancel()
        realtimeReload = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.load()
        }
    }

    func delete(_ record: FinancialRecord) async {
        do {
            try await supabase
                .from("financial_records")
                .delete()
                .eq("id", value: record.id.uuidString)
                .execute()
            records.removeAll { $0.id == record.id }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
