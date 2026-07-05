import Foundation
import Observation
import Supabase
import UIKit

@MainActor
@Observable
final class ProfileService {
    var profile: ProfileData?
    var isLoading = false
    var isSaving = false
    var isUploadingAvatar = false

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
            #if DEBUG
            print("[ProfileService] load error: \(error)")
            #endif
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

        // Avatars live in the public "documents" bucket, on the same path the
        // web app writes to — the dedicated "avatars" bucket rejects uploads
        // for invited accounts. A fresh timestamped filename means no
        // overwrite (so no storage update policy is needed) and doubles as a
        // cache-buster; the previous file is removed best-effort afterwards.
        let oldPath = Self.documentsStoragePath(fromPublicURL: profile?.avatarUrl)
        let path = "avatars/\(userId.uuidString.lowercased())/\(Int(Date().timeIntervalSince1970)).jpg"
        try await supabase.storage
            .from("documents")
            .upload(path, data: data, options: FileOptions(contentType: "image/jpeg"))

        let urlString = try supabase.storage.from("documents").getPublicURL(path: path).absoluteString

        try await supabase.from("profiles")
            .update(["avatar_url": urlString])
            .eq("id", value: userId.uuidString)
            .execute()
        profile?.avatarUrl = urlString

        if let oldPath, oldPath != path {
            _ = try? await supabase.storage.from("documents").remove(paths: [oldPath])
        }
    }

    /// Extracts the in-bucket path from a public "documents" bucket URL,
    /// so an old avatar can be cleaned up after a new one is uploaded.
    private static func documentsStoragePath(fromPublicURL urlString: String?) -> String? {
        guard let urlString,
              let range = urlString.range(of: "/object/public/documents/") else { return nil }
        let tail = String(urlString[range.upperBound...])
        guard let path = tail.split(separator: "?").first.map(String.init),
              !path.isEmpty else { return nil }
        return path.removingPercentEncoding ?? path
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
