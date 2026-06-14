import Foundation
import Supabase
import UIKit

@MainActor
final class ProfileService: ObservableObject {
    @Published var profile: ProfileData?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var isUploadingAvatar = false

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

    func update(
        displayName: String,
        fullName: String,
        firstName: String?,
        lastName: String?,
        birthDate: String?,
        phone: String?,
        email: String?,
        socialLinks: [SocialLink],
        notes: String?
    ) async throws {
        guard let id = profile?.id else { return }
        isSaving = true
        defer { isSaving = false }
        func clean(_ s: String?) -> String? { (s?.isEmpty ?? true) ? nil : s }

        let payload = ProfileUpdate(
            fullName: fullName,
            displayName: displayName,
            firstName: clean(firstName),
            lastName: clean(lastName),
            birthDate: clean(birthDate),
            phone: clean(phone),
            email: clean(email),
            socialLinks: socialLinks,
            notes: clean(notes),
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        try await supabase
            .from("profiles")
            .update(payload)
            .eq("id", value: id.uuidString)
            .execute()
        profile?.fullName = fullName
        profile?.displayName = clean(displayName)
        profile?.firstName = clean(firstName)
        profile?.lastName = clean(lastName)
        profile?.birthDate = clean(birthDate)
        profile?.phone = clean(phone)
        if let e = clean(email) { profile?.email = e }
        profile?.socialLinks = socialLinks
        profile?.notes = clean(notes)
    }

    func uploadAvatar(_ image: UIImage) async throws {
        guard let userId = profile?.id,
              let data = image.jpegData(compressionQuality: 0.85) else { return }
        isUploadingAvatar = true
        defer { isUploadingAvatar = false }

        let path = "\(userId.uuidString)/avatar.jpg"
        try await supabase.storage
            .from("avatars")
            .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))

        let publicURL = try supabase.storage.from("avatars").getPublicURL(path: path)
        let urlString = publicURL.absoluteString + "?v=\(Int(Date().timeIntervalSince1970))"

        try await supabase.from("profiles")
            .update(["avatar_url": urlString])
            .eq("id", value: userId.uuidString)
            .execute()
        profile?.avatarUrl = urlString
    }

    func updateEmail(_ newEmail: String) async throws {
        try await supabase.auth.update(user: UserAttributes(email: newEmail))
    }

    func updatePassword(_ newPassword: String) async throws {
        try await supabase.auth.update(user: UserAttributes(password: newPassword))
    }

    func sendPasswordReset() async throws {
        guard let email = profile?.email else { return }
        try await supabase.auth.resetPasswordForEmail(email)
    }
}
