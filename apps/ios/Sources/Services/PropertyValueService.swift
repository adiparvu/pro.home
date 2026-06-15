import Foundation

@MainActor
final class PropertyValueService: ObservableObject {
    @Published var entries: [PropertyValueEntry] = []
    @Published var isLoading = false
    @Published var error: String?

    var latestValue: PropertyValueEntry? {
        sortedEntries.first
    }

    var sortedEntries: [PropertyValueEntry] {
        entries.sorted {
            ($0.enteredDate ?? .distantPast) > ($1.enteredDate ?? .distantPast)
        }
    }

    func load(propertyId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await supabase
                .from("property_value_entries")
                .select()
                .eq("property_id", value: propertyId.uuidString)
                .order("entered_at", ascending: false)
                .execute().value
        } catch {
            self.error = error.localizedDescription
        }
    }

    func add(_ payload: NewPropertyValuePayload) async {
        do {
            let inserted: PropertyValueEntry = try await supabase
                .from("property_value_entries")
                .insert(payload)
                .select().single().execute().value
            entries.insert(inserted, at: 0)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func delete(_ entry: PropertyValueEntry) async {
        entries.removeAll { $0.id == entry.id }
        do {
            try await supabase
                .from("property_value_entries").delete()
                .eq("id", value: entry.id.uuidString).execute()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
