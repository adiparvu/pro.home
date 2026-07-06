import Foundation
import Observation
import EventKit

@MainActor
@Observable
final class FamilyService {
    var members: [FamilyMember] = []
    var isLoading = false
    var error: String?

    func load() async {
        let pid = PropertyService.activePropertyId
        // Paint the last known state instantly; the network refresh follows.
        if members.isEmpty, let cached = ServiceCache.load([FamilyMember].self, entity: "family", propertyId: pid) {
            members = cached
        }
        isLoading = true
        defer { isLoading = false }
        do {
            var query = supabase.from("family_members").select()
            if let pid {
                // Scope to the selected home; legacy rows without a property
                // stay visible rather than silently disappearing.
                query = query.or("property_id.eq.\(pid.uuidString),property_id.is.null")
            }
            members = try await query
                .order("created_at", ascending: true)
                .execute()
                .value
            ServiceCache.save(members, entity: "family", propertyId: pid)
        } catch {
            self.error = error.localizedDescription
        }
    }

    @discardableResult
    func add(name: String, role: String, email: String?, phone: String?,
             color: String, propertyId: UUID?, birthday: String?,
             socialLinks: [SocialLink]) async throws -> FamilyMember? {
        guard let ownerId = supabase.auth.currentSession?.user.id else { return nil }

        struct Payload: Encodable {
            let owner_id: UUID
            let property_id: UUID?
            let name: String
            let role: String
            let email: String?
            let phone: String?
            let color: String
            let birthday: String?
            let social_links: [SocialLink]
        }

        let inserted: FamilyMember = try await supabase
            .from("family_members")
            .insert(Payload(owner_id: ownerId, property_id: propertyId,
                            name: name, role: role, email: email, phone: phone, color: color,
                            birthday: birthday, social_links: socialLinks))
            .select()
            .single()
            .execute()
            .value
        members.append(inserted)
        members.sort { $0.name < $1.name }
        return inserted
    }

    // MARK: - Tenant leases

    /// Lease details per tenant, keyed by the family-member id.
    var leases: [UUID: TenantLease] = [:]

    func loadLeases(propertyId: UUID) async {
        let rows: [TenantLease]? = try? await supabase
            .from("tenant_leases")
            .select()
            .eq("property_id", value: propertyId.uuidString)
            .execute()
            .value
        leases = Dictionary((rows ?? []).map { ($0.memberId, $0) },
                            uniquingKeysWith: { _, new in new })
    }

    func saveLease(memberId: UUID, propertyId: UUID,
                   leaseStart: Date?, leaseEnd: Date?,
                   monthlyRent: Double?, currency: String, deposit: Double?,
                   paymentDay: Int?, occupants: Int?, notes: String?) async throws {
        struct Payload: Encodable {
            let property_id: UUID
            let member_id: UUID
            let lease_start: String?
            let lease_end: String?
            let monthly_rent: Double?
            let currency: String
            let deposit: Double?
            let payment_day: Int?
            let occupants: Int?
            let notes: String?
        }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let inserted: TenantLease = try await supabase
            .from("tenant_leases")
            .insert(Payload(
                property_id: propertyId, member_id: memberId,
                lease_start: leaseStart.map { f.string(from: $0) },
                lease_end: leaseEnd.map { f.string(from: $0) },
                monthly_rent: monthlyRent, currency: currency, deposit: deposit,
                payment_day: paymentDay, occupants: occupants, notes: notes))
            .select()
            .single()
            .execute()
            .value
        leases[memberId] = inserted
    }

    /// WhatsApp-style invite: a contact with an email is sent an invitation that
    /// (server-side) creates their account, grants property membership, and
    /// links this contact row to their real user.
    ///
    /// Returns `nil` on success (or when there's no email — nothing to send), or
    /// a human-readable message when the invite failed. We deliberately do NOT
    /// swallow the error: a silently-failing invite is exactly the bug that made
    /// invitations "disappear", so callers surface this to the inviter.
    @discardableResult
    func sendInvite(to email: String, name: String, role: String,
                    propertyId: UUID?, propertyName: String?) async -> String? {
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        struct InvitePayload: Encodable {
            let to: String
            let name: String
            let propertyId: String?
            let propertyName: String?
            let role: String
            let inviterEmail: String?
            let locale: String
        }
        let inviterEmail = try? await supabase.auth.session.user.email
        // App language so the invite email is localized (server also falls back
        // to the inviter's profile locale, then Romanian).
        let locale = Locale.current.language.languageCode?.identifier ?? "ro"
        let payload = InvitePayload(
            to: email, name: name,
            propertyId: propertyId?.uuidString, propertyName: propertyName,
            role: role, inviterEmail: inviterEmail, locale: locale
        )
        do {
            _ = try await supabase.functions.invoke("send-invite-email", options: .init(body: payload))
            return nil
        } catch {
            let message = error.localizedDescription
            self.error = message
            #if DEBUG
            print("[FamilyService] sendInvite failed: \(error)")
            #endif
            return message
        }
    }

    /// Returns true on success. On failure it sets `error` AND returns false so
    /// the caller can keep its editor open instead of falsely reporting "saved"
    /// (an RLS-rejected edit used to dismiss and silently revert on next load).
    @discardableResult
    func update(_ member: FamilyMember) async -> Bool {
        struct Payload: Encodable {
            let name: String
            let role: String
            let email: String?
            let phone: String?
            let color: String
            let birthday: String?
            let social_links: [SocialLink]
        }
        do {
            let updated: FamilyMember = try await supabase
                .from("family_members")
                .update(Payload(name: member.name, role: member.role,
                                email: member.email, phone: member.phone, color: member.color,
                                birthday: member.birthday, social_links: member.socialLinks ?? []))
                .eq("id", value: member.id.uuidString)
                .select()
                .single()
                .execute()
                .value
            if let i = members.firstIndex(where: { $0.id == member.id }) {
                members[i] = updated
            }
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func delete(_ member: FamilyMember) async {
        do {
            try await supabase
                .from("family_members")
                .delete()
                .eq("id", value: member.id.uuidString)
                .execute()
            members.removeAll { $0.id == member.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func addBirthdayToCalendar(name: String, birthday: Date) async {
        let store = EKEventStore()
        do {
            if #available(iOS 17.0, *) {
                try await store.requestWriteOnlyAccessToEvents()
            } else {
                try await store.requestAccess(to: .event)
            }
            createBirthdayEvent(store: store, name: name, birthday: birthday)
        } catch {
            #if DEBUG
            print("[FamilyService] calendar access error: \(error)")
            #endif
        }
    }

    private nonisolated func createBirthdayEvent(store: EKEventStore, name: String, birthday: Date) {
        let event = EKEvent(eventStore: store)
        event.title = String(format: String(localized: "🎂 %@"), name)
        event.startDate = birthday
        event.endDate = birthday
        event.isAllDay = true
        let rule = EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)
        event.addRecurrenceRule(rule)
        event.calendar = store.defaultCalendarForNewEvents
        try? store.save(event, span: .futureEvents)
    }
}
