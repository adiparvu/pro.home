import SwiftUI
import Observation
import UIKit
import Supabase

// MARK: - Status / Stories model

struct StatusUpdate: Identifiable, Codable, Hashable {
    let id: UUID
    let propertyId: UUID
    let authorId: UUID
    let authorName: String
    let mediaUrl: String?
    let caption: String?
    let createdAt: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case id, caption
        case propertyId = "property_id"
        case authorId   = "author_id"
        case authorName = "author_name"
        case mediaUrl   = "media_url"
        case createdAt  = "created_at"
        case expiresAt  = "expires_at"
    }

    var date: Date? { ISODate.date(from: createdAt) }
}

/// One author's active statuses, grouped for the list/ring UI.
struct StatusGroup: Identifiable {
    let authorId: UUID
    let authorName: String
    let items: [StatusUpdate]
    var id: UUID { authorId }
    var latest: StatusUpdate? { items.last }
}

// MARK: - Status service (singleton)

@MainActor
@Observable
final class StatusService {
    static let shared = StatusService()
    private init() {}

    /// Active (non-expired) updates for the property.
    var updates: [StatusUpdate] = []
    /// Ids of statuses the current user has already viewed.
    var viewedIds: Set<UUID> = []

    private var uid: UUID? { supabase.auth.currentSession?.user.id }

    func load(propertyId: UUID) async {
        let nowISO = ISO8601DateFormatter().string(from: Date())
        guard let rows: [StatusUpdate] = try? await supabase
            .from("status_updates")
            .select()
            .eq("property_id", value: propertyId.uuidString)
            .gt("expires_at", value: nowISO)
            .order("created_at", ascending: true)
            .execute().value
        else { return }
        updates = rows
        await loadMyViews()
    }

    private func loadMyViews() async {
        guard let uid, !updates.isEmpty else { viewedIds = []; return }
        struct V: Decodable { let status_id: UUID }
        guard let rows: [V] = try? await supabase
            .from("status_views")
            .select("status_id")
            .eq("viewer_id", value: uid.uuidString)
            .execute().value
        else { return }
        let current = Set(updates.map { $0.id })
        viewedIds = Set(rows.map { $0.status_id }).intersection(current)
    }

    /// Posts a story. Returns nil on success or a human-readable error — the
    /// caller must surface it. We never celebrate (or insert an imageless row)
    /// when the upload or insert failed: an offline post used to play the
    /// success haptic while nothing actually reached anyone.
    @discardableResult
    func post(propertyId: UUID, authorName: String, image: UIImage, caption: String?) async -> String? {
        guard let uid else { return String(localized: "You're not signed in.") }
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            return String(localized: "Couldn't prepare the image.")
        }
        // Private bucket + signed URL at display (resolved via ChatMedia). Path is
        // scoped by property so chat-media RLS admits property members.
        guard let mediaPath = await ChatMedia.upload(data, propertyId: propertyId, subdir: "status",
                                                     ext: "jpg", contentType: "image/jpeg") else {
            return String(localized: "Image upload failed. Check your connection and try again.")
        }
        struct Payload: Encodable {
            let property_id: String
            let author_id: String
            let author_name: String
            let media_url: String?
            let caption: String?
        }
        do {
            try await supabase.from("status_updates").insert(Payload(
                property_id: propertyId.uuidString,
                author_id: uid.uuidString,
                author_name: authorName,
                media_url: mediaPath,
                caption: (caption?.isEmpty == false) ? caption : nil
            )).execute()
        } catch {
            return error.localizedDescription
        }
        await load(propertyId: propertyId)
        HapticFeedback.success()
        return nil
    }

    func markViewed(_ status: StatusUpdate, viewerName: String) async {
        guard let uid, !viewedIds.contains(status.id) else { return }
        viewedIds.insert(status.id)
        struct V: Encodable { let status_id: String; let viewer_id: String; let viewer_name: String }
        _ = try? await supabase.from("status_views").upsert(
            V(status_id: status.id.uuidString, viewer_id: uid.uuidString, viewer_name: viewerName),
            onConflict: "status_id,viewer_id").execute()
    }

    func viewers(of statusId: UUID) async -> [String] {
        struct V: Decodable { let viewer_name: String? }
        guard let rows: [V] = try? await supabase
            .from("status_views")
            .select("viewer_name")
            .eq("status_id", value: statusId.uuidString)
            .execute().value
        else { return [] }
        return rows.compactMap { $0.viewer_name }
    }

    func delete(_ status: StatusUpdate, propertyId: UUID) async {
        _ = try? await supabase.from("status_updates").delete()
            .eq("id", value: status.id.uuidString).execute()
        await load(propertyId: propertyId)
    }

    // MARK: - Derived

    func myGroup(myId: UUID?) -> StatusGroup? {
        guard let myId else { return nil }
        let mine = updates.filter { $0.authorId == myId }
        guard !mine.isEmpty else { return nil }
        return StatusGroup(authorId: myId, authorName: "My status", items: mine)
    }

    func otherGroups(myId: UUID?) -> [StatusGroup] {
        let others = updates.filter { $0.authorId != myId }
        let groups = Dictionary(grouping: others, by: { $0.authorId })
        return groups.map { key, value in
            StatusGroup(authorId: key, authorName: value.first?.authorName ?? "", items: value)
        }
        .sorted { ($0.latest?.createdAt ?? "") > ($1.latest?.createdAt ?? "") }
    }

    func allSeen(_ group: StatusGroup) -> Bool {
        group.items.allSatisfy { viewedIds.contains($0.id) }
    }
}
