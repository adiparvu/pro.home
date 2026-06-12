import Foundation
import Supabase

@MainActor
final class ProfileService: ObservableObject {
    @Published var profile: ProfileData?
    @Published var isLoading = false
    @Published var isSaving = false

    func load(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            profile = try await supabase
                .from("profiles")
                .select()
                .eq("id", value: userId.uuidString)
                .single()
                .execute()
                .value
        } catch {
            print("[ProfileService] load error: \(error)")
        }
    }

    func update(fullName: String, displayName: String, phone: String?) async throws {
        guard let id = profile?.id else { return }
        isSaving = true
        defer { isSaving = false }
        let payload = ProfileUpdate(
            fullName: fullName,
            displayName: displayName,
            phone: phone.flatMap { $0.isEmpty ? nil : $0 },
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        try await supabase
            .from("profiles")
            .update(payload)
            .eq("id", value: id.uuidString)
            .execute()
        profile?.fullName = fullName
        profile?.displayName = displayName.isEmpty ? nil : displayName
        profile?.phone = phone
    }

    func sendPasswordReset() async throws {
        guard let email = profile?.email else { return }
        try await supabase.auth.resetPasswordForEmail(email)
    }
}
