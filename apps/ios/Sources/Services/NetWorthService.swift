import Foundation
import Observation
import Supabase

// MARK: - Net worth service ("Avere netă gospodărie")
//
// Loads the household's manually tracked assets and liabilities and keeps every
// family phone in sync via realtime — the same hardened subscribe pattern as
// FinancialService/SavingsGoalService (liveness idempotency, real leave before
// remove, timeboxed subscribe with no-trace cleanup). The derived figures
// (property value, savings pot, mortgage) are composed in the view from the
// other services; this one owns only the `net_worth_accounts` table.

@MainActor
@Observable
final class NetWorthService {
    private(set) var accounts: [NetWorthAccount] = []
    var isLoading = false
    var error: String?

    private var channel: RealtimeChannelV2?
    private var subscribedPropertyId: UUID?
    private var subs: [RealtimeSubscription] = []
    private var reloadTask: Task<Void, Never>?

    // MARK: - Load

    func load() async {
        let pid = PropertyService.activePropertyId
        if accounts.isEmpty, let cached = ServiceCache.load([NetWorthAccount].self, entity: "net_worth", propertyId: pid) {
            accounts = cached
        }
        isLoading = true
        defer { isLoading = false }
        do {
            accounts = try await PropertyRepo.fetch(table: "net_worth_accounts", propertyId: pid,
                                                    order: "created_at", limit: 500)
            ServiceCache.save(accounts, entity: "net_worth", propertyId: pid)
        } catch {
            if error is CancellationError { return }
            self.error = error.recordableDescription
        }
        if let pid { await subscribeRealtime(propertyId: pid) }
    }

    var assets: [NetWorthAccount] { accounts.filter { $0.isAsset } }
    var liabilities: [NetWorthAccount] { accounts.filter { !$0.isAsset } }

    // MARK: - Mutations

    struct NewAccount: Encodable {
        let propertyId: String
        let name: String
        let category: String
        let kind: String
        let balance: Double
        let currency: String
        let icon: String?
        let notes: String?
        enum CodingKeys: String, CodingKey {
            case name, category, kind, balance, currency, icon, notes
            case propertyId = "property_id"
        }
    }

    func addAccount(_ account: NewAccount) async throws {
        try await supabase.from("net_worth_accounts").insert(account).execute()
        await load()
    }

    struct AccountPatch: Encodable {
        let name: String
        let category: String
        let kind: String
        let balance: Double
        let currency: String
        let icon: String?
        let notes: String?
        let updatedAt: String
        enum CodingKeys: String, CodingKey {
            case name, category, kind, balance, currency, icon, notes
            case updatedAt = "updated_at"
        }
    }

    func updateAccount(_ id: UUID, patch: AccountPatch) async throws {
        try await supabase.from("net_worth_accounts")
            .update(patch).eq("id", value: id.uuidString).execute()
        await load()
    }

    func deleteAccount(_ account: NetWorthAccount) async {
        do {
            try await supabase.from("net_worth_accounts")
                .delete().eq("id", value: account.id.uuidString).execute()
            accounts.removeAll { $0.id == account.id }
        } catch { self.error = error.recordableDescription }
    }

    // MARK: - Live family sync (hardened, mirrors FinancialService)

    private func subscribeRealtime(propertyId: UUID) async {
        if let ch = channel, subscribedPropertyId == propertyId,
           ch.status == .subscribed || ch.status == .subscribing { return }
        if let ch = channel {
            await ch.unsubscribe()
            await realtimeAnon.removeChannel(ch)
            channel = nil
            subs.removeAll()
        }
        let ch = realtimeAnon.channel("net_worth:\(propertyId.uuidString)")
        subs.append(ch.onPostgresChange(
            AnyAction.self, schema: "public", table: "net_worth_accounts",
            filter: "property_id=eq.\(propertyId.uuidString)"
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleReload() }
        })
        do {
            try await withRealtimeTimeout(seconds: 15) { try await ch.subscribeWithError() }
            channel = ch
            subscribedPropertyId = propertyId
        } catch {
            debugLog("Net worth realtime subscribe failed:", error)
            subs.removeAll()
            await ch.unsubscribe()
            await realtimeAnon.removeChannel(ch)
        }
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, !AppLifecycle.isBackgrounded else { return }
            await self?.load()
        }
    }
}
