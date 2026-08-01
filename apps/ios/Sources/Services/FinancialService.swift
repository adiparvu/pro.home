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
            records = try await PropertyRepo.fetch(table: "financial_records", propertyId: pid,
                                                   order: "date", limit: 1000)
            ServiceCache.save(records, entity: "financial", propertyId: pid)
        } catch {
            if error is CancellationError { return }
            self.error = error.recordableDescription
        }
        if let pid { await subscribeRealtime(propertyId: pid) }
    }

    // MARK: - Live family sync
    //
    // An expense added on one phone shows up on every family member's phone
    // in seconds. Events are coalesced so a burst of changes costs one reload.

    private func subscribeRealtime(propertyId: UUID) async {
        // Liveness idempotency (audit 2026-07-21): only a channel that
        // genuinely reached .subscribed (or is mid-join) satisfies the
        // guard — a failed subscribe recorded as "done" was a permanently
        // silent session until app relaunch.
        if let ch = realtimeChannel, subscribedPropertyId == propertyId,
           ch.status == .subscribed || ch.status == .subscribing { return }
        if let ch = realtimeChannel {
            // Real leave from EVERY state (b1173) — removeChannel alone
            // skips the phx_leave and breeds the server-side orphan.
            await ch.unsubscribe()
            await realtimeAnon.removeChannel(ch)
            realtimeChannel = nil
            postgresSubs.removeAll()
        }
        let channel = realtimeAnon.channel("financial_records:\(propertyId.uuidString)")
        postgresSubs.append(channel.onPostgresChange(
            AnyAction.self,
            schema: "public",
            table: "financial_records",
            filter: "property_id=eq.\(propertyId.uuidString)"
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleRealtimeReload() }
        })
        do {
            try await withRealtimeTimeout(seconds: 15) {
                try await channel.subscribeWithError()
            }
            realtimeChannel = channel
            subscribedPropertyId = propertyId
        } catch {
            // No trace on failure: the next subscribe attempt must not be
            // fooled by a dead channel, and the leave keeps the topic clean.
            debugLog("Finance realtime subscribe failed:", error)
            postgresSubs.removeAll()
            await channel.unsubscribe()
            await realtimeAnon.removeChannel(channel)
        }
    }

    private func scheduleRealtimeReload() {
        realtimeReload?.cancel()
        realtimeReload = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            // Quiet in the background (0x8BADF00D scene-update watchdog, b1036).
            guard !Task.isCancelled, !AppLifecycle.isBackgrounded else { return }
            await self?.load()
        }
    }

    /// Insert payload for a new financial record.
    struct NewFinancialRecord: Encodable {
        /// Client-chosen row id, used only by queued writes (see `addQueued`).
        /// Nil for every interactive add — the database generates one, and a
        /// nil optional is simply not encoded.
        var id: String? = nil
        let propertyId: String
        let title: String
        let amount: Double
        let currency: String
        let type: String
        let category: String
        let date: String
        let description: String?
        let tags: [String]

        enum CodingKeys: String, CodingKey {
            case propertyId = "property_id"
            case id, title, amount, currency, type, category, date, description, tags
        }
    }

    /// Inserts a record, then reloads so every screen sees it immediately.
    /// Rethrows the insert error so callers can surface it inline (the
    /// reload itself never throws — it reports through `self.error`).
    func add(_ record: NewFinancialRecord) async throws {
        try await supabase
            .from("financial_records")
            .insert(record)
            .execute()
        await load()
    }

    /// Insert for a write that was QUEUED offline (a card tap parked by the
    /// Shortcuts automation). The row carries the queue entry's own id, so a
    /// retry after an ambiguous failure — the insert landed but the client
    /// never saw the answer — is a no-op instead of a second charge in the
    /// ledger. Exactly-once, which a plain insert cannot be.
    func addQueued(_ record: NewFinancialRecord) async throws {
        try await supabase
            .from("financial_records")
            .upsert(record, onConflict: "id", ignoreDuplicates: true)
            .execute()
        await load()
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
            self.error = error.recordableDescription
        }
    }
}
