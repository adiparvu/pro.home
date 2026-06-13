import Foundation

@MainActor
final class PropertyService: ObservableObject {
    @Published var properties: [PropertyModel] = []
    @Published var isLoading = false
    @Published var error: String?

    var selectedPropertyId: UUID? {
        get { UUID(uuidString: UserDefaults.standard.string(forKey: "prvhouse.selectedPropertyId") ?? "") }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue?.uuidString, forKey: "prvhouse.selectedPropertyId")
        }
    }

    var primary: PropertyModel? {
        if let id = selectedPropertyId, let p = properties.first(where: { $0.id == id }) { return p }
        return properties.first
    }

    func select(_ property: PropertyModel) { selectedPropertyId = property.id }

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

    func create(name: String, addressLine1: String, city: String, country: String,
                propertyType: String, postalCode: String?, sizeSqm: Double?,
                numRooms: Int?, latitude: Double?, longitude: Double?) async {
        struct PropertyCreate: Encodable {
            let name: String
            let address_line1: String
            let city: String
            let country: String
            let property_type: String
            let postal_code: String?
            let size_sqm: Double?
            let num_rooms: Int?
            let latitude: Double?
            let longitude: Double?
        }
        do {
            let created: PropertyModel = try await supabase
                .from("properties")
                .insert(PropertyCreate(
                    name: name, address_line1: addressLine1, city: city,
                    country: country, property_type: propertyType,
                    postal_code: postalCode, size_sqm: sizeSqm,
                    num_rooms: numRooms, latitude: latitude, longitude: longitude
                ))
                .select()
                .single()
                .execute()
                .value
            properties.append(created)
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
