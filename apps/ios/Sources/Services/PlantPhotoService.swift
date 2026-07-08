import Foundation
import Observation
import Supabase
import UIKit

// MARK: - Plant photo album (Plant OS P1)
//
// The evolution album for one plant: photos live in the private `plant-media`
// bucket ({property}/{plant}/{uuid}.jpg) and are indexed in plant_photos, so
// they sync across the household's devices. Reads resolve short-lived signed
// URLs (the same pattern chat media uses).

@MainActor
@Observable
final class PlantPhotoService {
    private(set) var photos: [PlantPhoto] = []
    var isLoading = false

    private static let bucket = "plant-media"

    func load(plantId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        photos = (try? await supabase.from("plant_photos")
            .select()
            .eq("plant_id", value: plantId.uuidString)
            .order("taken_at", ascending: false)
            .execute().value) ?? []
    }

    /// Uploads one album photo and records it. Returns false on failure.
    @discardableResult
    func add(image: UIImage, plantId: UUID, propertyId: UUID, note: String?) async -> Bool {
        guard let data = image.uploadJPEG(quality: 0.8, maxDimension: 2048) else { return false }
        let path = "\(propertyId.uuidString)/\(plantId.uuidString)/\(UUID().uuidString).jpg"
        do {
            try await supabase.storage.from(Self.bucket)
                .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: false))
            struct Payload: Encodable {
                let plant_id: String, property_id: String, url: String, note: String?
            }
            let row: PlantPhoto = try await supabase.from("plant_photos")
                .insert(Payload(plant_id: plantId.uuidString, property_id: propertyId.uuidString,
                                url: path, note: note))
                .select().single().execute().value
            photos.insert(row, at: 0)
            return true
        } catch {
            return false
        }
    }

    func delete(_ photo: PlantPhoto) async {
        do {
            try? await supabase.storage.from(Self.bucket).remove(paths: [photo.url])
            try await supabase.from("plant_photos").delete()
                .eq("id", value: photo.id.uuidString).execute()
            photos.removeAll { $0.id == photo.id }
        } catch { /* best-effort */ }
    }

    /// Resolves a stored path to a displayable signed URL (legacy full URLs
    /// pass through), cached under the signing window.
    static func resolve(_ stored: String) async -> URL? {
        if stored.hasPrefix("http") { return URL(string: stored) }
        if let cached = await PlantURLCache.shared.get(stored) { return cached }
        guard let url = try? await supabase.storage.from(bucket)
            .createSignedURL(path: stored, expiresIn: 3600) else { return nil }
        await PlantURLCache.shared.set(stored, url: url)
        return url
    }
}

private actor PlantURLCache {
    static let shared = PlantURLCache()
    private var entries: [String: (url: URL, expiresAt: Date)] = [:]
    private let ttl: TimeInterval = 50 * 60

    func get(_ key: String) -> URL? {
        guard let e = entries[key], e.expiresAt > Date() else { return nil }
        return e.url
    }
    func set(_ key: String, url: URL) {
        entries[key] = (url, Date().addingTimeInterval(ttl))
    }
}
