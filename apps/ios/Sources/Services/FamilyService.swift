import Foundation

@MainActor
final class FamilyService: ObservableObject {
    @Published var members: [FamilyMember] = []
    @Published var isLoading = false
    @Published var error: String?

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            members = try await supabase
                .from("family_members")
                .select()
                .order("created_at", ascending: true)
                .execute()
                .value
        } catch {
            self.error = error.localizedDescription
        }
    }

    func add(name: String, role: String, email: String?, phone: String?,
             color: String, propertyId: UUID?) async throws {
        guard let ownerId = supabase.auth.currentSession?.user.id else { return }

        struct Payload: Encodable {
            let owner_id: UUID
            let property_id: UUID?
            let name: String
            let role: String
            let email: String?
            let phone: String?
            let color: String
        }

        let inserted: FamilyMember = try await supabase
            .from("family_members")
            .insert(Payload(owner_id: ownerId, property_id: propertyId,
                            name: name, role: role, email: email, phone: phone, color: color))
            .select()
            .single()
            .execute()
            .value
        members.append(inserted)
        members.sort { $0.name < $1.name }
    }

    func update(_ member: FamilyMember) async {
        struct Payload: Encodable {
            let name: String
            let role: String
            let email: String?
            let phone: String?
            let color: String
        }
        do {
            let updated: FamilyMember = try await supabase
                .from("family_members")
                .update(Payload(name: member.name, role: member.role,
                                email: member.email, phone: member.phone, color: member.color))
                .eq("id", value: member.id.uuidString)
                .select()
                .single()
                .execute()
                .value
            if let i = members.firstIndex(where: { $0.id == member.id }) {
                members[i] = updated
            }
        } catch {
            self.error = error.localizedDescription
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
}
