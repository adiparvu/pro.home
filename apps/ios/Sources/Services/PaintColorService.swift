import Foundation
import Observation

@MainActor
@Observable
final class PaintColorService {
    var colors: [PaintColor] = []
    var isLoading = false
    var error: String?

    var byRoom: [String: [PaintColor]] {
        Dictionary(grouping: colors, by: { $0.roomName })
    }

    var roomNames: [String] {
        Array(Set(colors.map { $0.roomName })).sorted()
    }

    func load(propertyId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            colors = try await PropertyRepo.fetch(table: "paint_colors", propertyId: propertyId,
                                                  scope: .strict, order: "room_name", ascending: true,
                                                  limit: 500)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func add(_ payload: NewPaintColorPayload) async {
        do {
            let inserted: PaintColor = try await supabase
                .from("paint_colors")
                .insert(payload)
                .select().single().execute().value
            colors.append(inserted)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Full-row update by id (everything editable; identity/created stay).
    private struct UpdatePayload: Encodable {
        let room_name: String, surface: String, color_name: String
        let brand: String?, code: String?, finish: String?
        let hex_color: String?, notes: String?, photo_url: String?
        let last_used_at: String?, leftover_note: String?
    }

    func update(_ color: PaintColor) async {
        let payload = UpdatePayload(
            room_name: color.roomName, surface: color.surface, color_name: color.colorName,
            brand: color.brand, code: color.code, finish: color.finish?.rawValue,
            hex_color: color.hexColor, notes: color.notes, photo_url: color.photoUrl,
            last_used_at: color.lastUsedAt, leftover_note: color.leftoverNote)
        do {
            let fresh: PaintColor = try await supabase
                .from("paint_colors")
                .update(payload)
                .eq("id", value: color.id.uuidString)
                .select()
                .single()
                .execute()
                .value
            if let i = colors.firstIndex(where: { $0.id == color.id }) { colors[i] = fresh }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func delete(_ color: PaintColor) async {
        colors.removeAll { $0.id == color.id }
        do {
            try await supabase
                .from("paint_colors").delete()
                .eq("id", value: color.id.uuidString).execute()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
