import Foundation
import Observation
import Supabase

// MARK: - Chore service ("Corvezi & alocație")
//
// CRUD over `chores` plus the completion ledger. The flow is deliberately
// three-step so the allowance stays honest: log → approve (parent) → payout.
// Payout stamps `paid_at` on the approved rows and writes one real expense
// record per currency into the family ledger (tag "allowance"). Loaded lazily
// on the Chores surface, not at app launch — mirrors MeterService.

@MainActor
@Observable
final class ChoreService {
    private(set) var chores: [Chore] = []
    private(set) var completions: [ChoreCompletion] = []
    var isLoading = false
    var error: String?
    private var loadedPropertyId: UUID?

    // MARK: - Load (lazy — first Chores surface)

    func loadIfNeeded() async {
        let pid = PropertyService.activePropertyId
        guard loadedPropertyId != pid || chores.isEmpty else { return }
        await load()
    }

    func load() async {
        let pid = PropertyService.activePropertyId
        if chores.isEmpty, let cached = ServiceCache.load([Chore].self, entity: "chores", propertyId: pid) {
            chores = cached
        }
        isLoading = true
        defer { isLoading = false }
        do {
            chores = try await PropertyRepo.fetch(table: "chores", propertyId: pid,
                                                  order: "created_at", limit: 200)
            completions = try await PropertyRepo.fetch(table: "chore_completions", propertyId: pid,
                                                       order: "completed_at", limit: 1000)
            loadedPropertyId = pid
            ServiceCache.save(chores, entity: "chores", propertyId: pid)
        } catch {
            if error is CancellationError { return }
            self.error = error.recordableDescription
        }
    }

    // MARK: - Derived (the page reads these, never re-filters)

    var activeChores: [Chore] { chores.filter { $0.active } }

    var pending: [ChoreCompletion] {
        completions.filter { !$0.isApproved }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    var balances: [ChoreBalance] { ChoreBalance.balances(from: completions) }

    var recentHistory: [ChoreCompletion] {
        completions.filter { $0.isApproved }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    func lastCompletion(for choreId: UUID) -> ChoreCompletion? {
        completions.filter { $0.choreId == choreId }
            .max { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    func chore(for completion: ChoreCompletion) -> Chore? {
        chores.first { $0.id == completion.choreId }
    }

    // MARK: - Chore CRUD

    struct ChorePayload: Encodable {
        var propertyId: String?
        let title: String
        let icon: String?
        let reward: Double
        let currency: String
        let assignedMemberId: String?
        let assignedMemberName: String?
        let recurrence: String
        let active: Bool
        var updatedAt: String?
        enum CodingKeys: String, CodingKey {
            case title, icon, reward, currency, recurrence, active
            case propertyId         = "property_id"
            case assignedMemberId   = "assigned_member_id"
            case assignedMemberName = "assigned_member_name"
            case updatedAt          = "updated_at"
        }
    }

    func add(_ payload: ChorePayload) async throws {
        var p = payload
        p.propertyId = PropertyService.activePropertyId?.uuidString
        try await supabase.from("chores").insert(p).execute()
        await load()
    }

    func update(_ id: UUID, payload: ChorePayload) async throws {
        var p = payload
        p.updatedAt = ISODate.string(from: Date())
        try await supabase.from("chores")
            .update(p).eq("id", value: id.uuidString).execute()
        await load()
    }

    func delete(_ chore: Chore) async {
        do {
            try await supabase.from("chores")
                .delete().eq("id", value: chore.id.uuidString).execute()
            chores.removeAll { $0.id == chore.id }
            completions.removeAll { $0.choreId == chore.id }
        } catch { self.error = error.recordableDescription }
    }

    // MARK: - The allowance flow: log → approve → payout

    private struct NewCompletion: Encodable {
        let choreId: String
        let propertyId: String
        let memberId: String?
        let memberName: String?
        let reward: Double
        let currency: String
        let completedAt: String
        enum CodingKeys: String, CodingKey {
            case reward, currency
            case choreId     = "chore_id"
            case propertyId  = "property_id"
            case memberId    = "member_id"
            case memberName  = "member_name"
            case completedAt = "completed_at"
        }
    }

    /// Logs a completion. Credit goes to the ASSIGNED child when the chore
    /// has one (a parent often marks it on the kid's behalf); otherwise to
    /// whoever tapped. The reward is snapshotted from the chore so a later
    /// price change never rewrites history.
    func logCompletion(for chore: Chore) async throws {
        guard let pid = PropertyService.activePropertyId else { return }
        var memberId = chore.assignedMemberId
        var memberName = chore.assignedMemberName
        if memberId == nil && memberName == nil {
            memberId = supabase.auth.currentSession?.user.id.uuidString
            memberName = await currentMemberName()
        }
        try await supabase.from("chore_completions").insert(NewCompletion(
            choreId: chore.id.uuidString,
            propertyId: pid.uuidString,
            memberId: memberId,
            memberName: memberName,
            reward: chore.reward,
            currency: chore.currency,
            completedAt: AppDate.dayString(from: Date()))).execute()
        await load()
    }

    private struct ApprovePatch: Encodable {
        let approvedBy: String
        let approvedAt: String
        enum CodingKeys: String, CodingKey {
            case approvedBy = "approved_by"
            case approvedAt = "approved_at"
        }
    }

    func approve(_ completion: ChoreCompletion) async throws {
        guard let uid = supabase.auth.currentSession?.user.id else { return }
        try await supabase.from("chore_completions")
            .update(ApprovePatch(approvedBy: uid.uuidString,
                                 approvedAt: ISODate.string(from: Date())))
            .eq("id", value: completion.id.uuidString).execute()
        await load()
    }

    /// Rejecting removes the row — the balance only ever contains rows a
    /// parent explicitly approved.
    func reject(_ completion: ChoreCompletion) async {
        do {
            try await supabase.from("chore_completions")
                .delete().eq("id", value: completion.id.uuidString).execute()
            completions.removeAll { $0.id == completion.id }
        } catch { self.error = error.recordableDescription }
    }

    /// Pays a child's whole balance: stamps `paid_at` on the approved rows,
    /// then writes one expense record per currency into the family ledger so
    /// the allowance shows up where every other household cost lives.
    func payout(_ balance: ChoreBalance, into financial: FinancialService) async throws {
        guard let pid = PropertyService.activePropertyId else { return }
        let rows = completions.filter { $0.isApproved && !$0.isPaid && $0.memberKey == balance.memberKey }
        guard !rows.isEmpty else { return }
        try await supabase.from("chore_completions")
            .update(["paid_at": ISODate.string(from: Date())])
            .in("id", values: rows.map { $0.id.uuidString })
            .execute()
        let perCurrency = Dictionary(grouping: rows, by: { $0.currency })
        for (currency, group) in perCurrency {
            try await financial.add(FinancialService.NewFinancialRecord(
                propertyId: pid.uuidString,
                title: String(format: String(localized: "allowance_payout_title_fmt"),
                              balance.memberName),
                amount: group.reduce(0) { $0 + $1.reward },
                currency: currency,
                type: "expense",
                category: "other",
                date: AppDate.dayString(from: Date()),
                description: String(format: String(localized: "allowance_payout_desc_fmt"),
                                    group.count),
                tags: ["allowance"]))
        }
        await load()
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
}
