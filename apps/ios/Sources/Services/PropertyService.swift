import Foundation
import Supabase
import UIKit

@MainActor
final class PropertyService: ObservableObject {
    @Published var properties: [PropertyModel] = []
    @Published var isLoading = false
    @Published var error: String?

    var selectedPropertyId: UUID? {
        get { UUID(uuidString: UserDefaults.standard.string(forKey: "prvio.selectedPropertyId") ?? "") }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue?.uuidString, forKey: "prvio.selectedPropertyId")
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
        guard let uid = supabase.auth.currentSession?.user.id else { return }
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
            let creator_id: UUID
        }
        struct MemberInsert: Encodable {
            let property_id: UUID
            let user_id: UUID
            let role: String
            let status: String
        }
        do {
            let created: PropertyModel = try await supabase
                .from("properties")
                .insert(PropertyCreate(
                    name: name, address_line1: addressLine1, city: city,
                    country: country, property_type: propertyType,
                    postal_code: postalCode, size_sqm: sizeSqm,
                    num_rooms: numRooms, latitude: latitude, longitude: longitude,
                    creator_id: uid
                ))
                .select()
                .single()
                .execute()
                .value
            properties.append(created)
            // Ensure creator is in property_members as owner (trigger handles this too)
            try? await supabase
                .from("property_members")
                .upsert(MemberInsert(property_id: created.id, user_id: uid, role: "owner", status: "active"),
                        onConflict: "property_id,user_id")
                .execute()
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
            let photo_url: String?
            let year_built: Int?
            let story: String?
            let renovations: [Renovation]
            let owners: [OwnerRecord]
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
            longitude: property.longitude,
            photo_url: property.photoUrl,
            year_built: property.yearBuilt,
            story: property.story,
            renovations: property.renovations ?? [],
            owners: property.owners ?? []
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

    /// Uploads a property photo to Storage and persists its public URL.
    func uploadPhoto(propertyId: UUID, image: UIImage) async {
        guard let data = image.jpegData(compressionQuality: 0.82) else { return }
        let uid = supabase.auth.currentSession?.user.id.uuidString ?? "anon"
        let path = "\(uid)/properties/\(propertyId.uuidString)/\(UUID().uuidString).jpg"
        do {
            try await supabase.storage.from("documents")
                .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: false))
            let url = try supabase.storage.from("documents").getPublicURL(path: path).absoluteString
            try await supabase.from("properties")
                .update(["photo_url": url])
                .eq("id", value: propertyId.uuidString)
                .execute()
            if let idx = properties.firstIndex(where: { $0.id == propertyId }) {
                properties[idx].photoUrl = url
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
