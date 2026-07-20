import Foundation
import Observation
import EventKit
import Supabase
import UIKit

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
            members = try await PropertyRepo.fetch(table: "family_members", propertyId: pid,
                                                   ascending: true, limit: 500)
            ServiceCache.save(members, entity: "family", propertyId: pid)
        } catch {
            self.error = error.recordableDescription
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
        let inserted: TenantLease = try await supabase
            .from("tenant_leases")
            .insert(Payload(
                property_id: propertyId, member_id: memberId,
                lease_start: leaseStart.map { AppDate.dayString(from: $0) },
                lease_end: leaseEnd.map { AppDate.dayString(from: $0) },
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
            debugLog("[FamilyService] sendInvite failed: \(error)")
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
            self.error = error.recordableDescription
            return false
        }
    }

    // MARK: - Roster avatars
    //
    // Roster-only members (children, grandparents, contacts — rows without a
    // PRVIO account) have no `profiles` row, so their photo lives on
    // `family_members.avatar_url`, which `MemberAvatar` already renders as the
    // fallback when the member holds no account. Uploads mirror the account
    // avatar pipeline (ProfileService.uploadAvatar): same public "documents"
    // bucket, same `avatars/<auth-uid>/` folder so the existing per-user
    // storage policy applies (the uploader is the signed-in owner/partner),
    // same resize-at-source, and a fresh timestamped filename as cache-buster
    // so no storage update policy is needed. RLS on `family_members` is the
    // existing owner/partner write path — nothing new.

    /// Uploads a photo for a roster member and persists it on the row.
    /// Returns the updated member on success; on failure sets `error` and
    /// returns nil so callers can keep their editor open.
    func uploadAvatar(for member: FamilyMember, image: UIImage) async -> FamilyMember? {
        guard let uploaderId = supabase.auth.currentSession?.user.id,
              let data = image.uploadJPEG(quality: 0.85, maxDimension: 1024) else {
            error = String(localized: "Couldn't save changes.")
            return nil
        }
        do {
            let oldPath = Self.documentsStoragePath(fromPublicURL: member.avatarUrl)
            let path = "avatars/\(uploaderId.uuidString.lowercased())/member-\(member.id.uuidString.lowercased())-\(Int(Date().timeIntervalSince1970)).jpg"
            try await supabase.storage
                .from("documents")
                .upload(path, data: data, options: FileOptions(contentType: "image/jpeg"))
            let urlString = try supabase.storage.from("documents").getPublicURL(path: path).absoluteString
            let updated = try await setAvatarUrl(urlString, memberId: member.id)
            // Previous photo is removed best-effort — a stray file must never
            // fail the upload that already succeeded.
            if let oldPath, oldPath != path {
                _ = try? await supabase.storage.from("documents").remove(paths: [oldPath])
            }
            return updated
        } catch {
            self.error = error.recordableDescription
            return nil
        }
    }

    /// Clears a roster member's photo (row first, then best-effort storage
    /// cleanup). Returns the updated member, or nil on failure with `error` set.
    func removeAvatar(for member: FamilyMember) async -> FamilyMember? {
        do {
            let updated = try await setAvatarUrl(nil, memberId: member.id)
            if let oldPath = Self.documentsStoragePath(fromPublicURL: member.avatarUrl) {
                _ = try? await supabase.storage.from("documents").remove(paths: [oldPath])
            }
            return updated
        } catch {
            self.error = error.recordableDescription
            return nil
        }
    }

    private func setAvatarUrl(_ urlString: String?, memberId: UUID) async throws -> FamilyMember {
        // [String: String?] encodes the nil as an explicit JSON null, so
        // removal genuinely clears the column instead of omitting the key.
        let updated: FamilyMember = try await supabase
            .from("family_members")
            .update(["avatar_url": urlString])
            .eq("id", value: memberId.uuidString)
            .select()
            .single()
            .execute()
            .value
        if let i = members.firstIndex(where: { $0.id == memberId }) {
            members[i] = updated
        }
        return updated
    }

    /// Extracts the in-bucket path from a public "documents" bucket URL so an
    /// old photo can be cleaned up (same parsing as ProfileService's avatars).
    private static func documentsStoragePath(fromPublicURL urlString: String?) -> String? {
        guard let urlString,
              let range = urlString.range(of: "/object/public/documents/") else { return nil }
        let tail = String(urlString[range.upperBound...])
        guard let path = tail.split(separator: "?").first.map(String.init),
              !path.isEmpty else { return nil }
        return path.removingPercentEncoding ?? path
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
            self.error = error.recordableDescription
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
            debugLog("[FamilyService] calendar access error: \(error)")
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
