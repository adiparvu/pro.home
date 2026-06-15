import Foundation

@MainActor
final class PaintColorService: ObservableObject {
    @Published var colors: [PaintColor] = []
    @Published var isLoading = false
    @Published var error: String?

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
            colors = try await supabase
                .from("paint_colors")
                .select()
                .eq("property_id", value: propertyId.uuidString)
                .order("room_name", ascending: true)
                .execute().value
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
