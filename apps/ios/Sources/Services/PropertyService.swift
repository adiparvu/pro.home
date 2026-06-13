import Foundation

@MainActor
final class PropertyService: ObservableObject {
    @Published var properties: [PropertyModel] = []
    @Published var isLoading = false
    @Published var error: String?

    var primary: PropertyModel? { properties.first }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            properties = try await supabase
                .from("properties")
                .select()
                .order("created_at", ascending: true)
                .execute()
                .value
        } catch {
            self.error = error.localizedDescription
        }
    }

    func update(_ property: PropertyModel) async {
        struct PropertyUpdate: Encodable {
            let name: String
            let address_line1: String
            let city: String
            let country: String
            let postal_code: String?
            let property_type: String
            let size_sqm: Double?
            let num_rooms: Int?
            let latitude: Double?
            let longitude: Double?
        }

        let payload = PropertyUpdate(
            name: property.name,
            address_line1: property.addressLine1,
            city: property.city,
            country: property.country,
            postal_code: property.postalCode,
            property_type: property.propertyType,
            size_sqm: property.sizeSqm,
            num_rooms: property.numRooms,
            latitude: property.latitude,
            longitude: property.longitude
        )

        do {
            let updated: PropertyModel = try await supabase
                .from("properties")
                .update(payload)
                .eq("id", value: property.id.uuidString)
                .select()
                .single()
                .execute()
                .value
            if let idx = properties.firstIndex(where: { $0.id == property.id }) {
                properties[idx] = updated
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
