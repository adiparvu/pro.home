import Foundation
import Observation
import Supabase

// MARK: - Shared savings goals service ("Obiective comune")
//
// Loads the property's goals and their contribution ledger, computes honest
// progress, and keeps every family phone in sync via realtime — the same
// hardened subscribe pattern as FinancialService (liveness idempotency, real
// leave before remove, timeboxed subscribe with no-trace cleanup).

@MainActor
@Observable
final class SavingsGoalService {
    private(set) var goals: [SavingsGoal] = []
    private(set) var contributions: [GoalContribution] = []
    var isLoading = false
    var error: String?

    private var channel: RealtimeChannelV2?
    private var subscribedPropertyId: UUID?
    private var subs: [RealtimeSubscription] = []
    private var reloadTask: Task<Void, Never>?

    // MARK: - Load

    func load() async {
        let pid = PropertyService.activePropertyId
        if goals.isEmpty, let cached = ServiceCache.load([SavingsGoal].self, entity: "savings_goals", propertyId: pid) {
            goals = cached
        }
        isLoading = true
        defer { isLoading = false }
        do {
            goals = try await PropertyRepo.fetch(table: "savings_goals", propertyId: pid,
                                                 order: "created_at", limit: 200)
            contributions = try await PropertyRepo.fetch(table: "goal_contributions", propertyId: pid,
                                                         order: "contributed_at", limit: 2000)
            ServiceCache.save(goals, entity: "savings_goals", propertyId: pid)
        } catch {
            if error is CancellationError { return }
            self.error = error.recordableDescription
        }
        if let pid { await subscribeRealtime(propertyId: pid) }
    }

    /// Honest progress for a goal, computed from the live ledger.
    func progress(for goal: SavingsGoal) -> SavingsGoalProgress {
        SavingsGoalProgress(goal: goal, contributions: contributions)
    }

    func contributions(for goalId: UUID) -> [GoalContribution] {
        contributions.filter { $0.goalId == goalId }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    // MARK: - Mutations

    struct NewGoal: Encodable {
        let propertyId: String
        let title: String
        let icon: String?
        let color: String?
        let targetAmount: Double
        let currency: String
        let monthlyPerMember: Double?
        let deadline: String?
        enum CodingKeys: String, CodingKey {
            case title, icon, color, currency, deadline
            case propertyId = "property_id"
            case targetAmount = "target_amount"
            case monthlyPerMember = "monthly_per_member"
        }
    }

    func addGoal(_ goal: NewGoal) async throws {
        try await supabase.from("savings_goals").insert(goal).execute()
        await load()
    }

    func deleteGoal(_ goal: SavingsGoal) async {
        do {
            try await supabase.from("savings_goals")
                .delete().eq("id", value: goal.id.uuidString).execute()
            goals.removeAll { $0.id == goal.id }
            contributions.removeAll { $0.goalId == goal.id }
        } catch { self.error = error.recordableDescription }
    }

    struct NewContribution: Encodable {
        let goalId: String
        let propertyId: String
        let memberId: String?
        let memberName: String?
        let amount: Double
        let note: String?
        let contributedAt: String
        enum CodingKeys: String, CodingKey {
            case amount, note
            case goalId = "goal_id"
            case propertyId = "property_id"
            case memberId = "member_id"
            case memberName = "member_name"
            case contributedAt = "contributed_at"
        }
    }

    /// Records a manual deposit. Member identity is stamped from the signed-in
    /// user so the per-member breakdown is truthful without asking each time.
    func addContribution(to goal: SavingsGoal, amount: Double, note: String?) async throws {
        let uid = supabase.auth.currentSession?.user.id
        let payload = NewContribution(
            goalId: goal.id.uuidString,
            propertyId: goal.propertyId.uuidString,
            memberId: uid?.uuidString,
            memberName: await currentMemberName(),
            amount: amount,
            note: note?.isEmpty == true ? nil : note,
            contributedAt: AppDate.day.string(from: Date()))
        try await supabase.from("goal_contributions").insert(payload).execute()
        await load()
    }

    func deleteContribution(_ c: GoalContribution) async {
        do {
            try await supabase.from("goal_contributions")
                .delete().eq("id", value: c.id.uuidString).execute()
            contributions.removeAll { $0.id == c.id }
        } catch { self.error = error.recordableDescription }
    }

    private func currentMemberName() async -> String? {
        guard let uid = supabase.auth.currentSession?.user.id else { return nil }
        if let name = MemberDirectory.shared.byId[uid]?.name, !name.isEmpty { return name }
        struct Row: Decodable {
            let displayName: String?; let fullName: String?
            enum CodingKeys: String, CodingKey {
                case displayName = "display_name", fullName = "full_name"
            }
        }
        guard let row: Row = try? await supabase.from("profiles")
            .select("display_name, full_name").eq("id", value: uid.uuidString)
            .single().execute().value else { return nil }
        return row.displayName ?? row.fullName
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
        let ch = realtimeAnon.channel("savings_goals:\(propertyId.uuidString)")
        for table in ["savings_goals", "goal_contributions"] {
            subs.append(ch.onPostgresChange(
                AnyAction.self, schema: "public", table: table,
                filter: "property_id=eq.\(propertyId.uuidString)"
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.scheduleReload() }
            })
        }
        do {
            try await withRealtimeTimeout(seconds: 15) { try await ch.subscribeWithError() }
            channel = ch
            subscribedPropertyId = propertyId
        } catch {
            debugLog("Savings realtime subscribe failed:", error)
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
