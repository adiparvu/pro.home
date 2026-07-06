import Foundation
import Observation
import Supabase
import UIKit

@MainActor
@Observable
final class PropertyService {
    var properties: [PropertyModel] = []
    var isLoading = false
    var error: String?

    /// The current user's role on the primary property (from property_members),
    /// e.g. owner / partner / tenant / service_provider / guest. Drives role-based
    /// UI gating. nil = unknown → treat as full access (fail-open; real security
    /// is server-side RLS).
    var myRole: String?

    /// Bumped when the UserDefaults-backed selection changes. Since
    /// `selectedPropertyId` isn't an observable stored property, its getter
    /// touches this so consumers (and `primary`) refresh when it changes.
    private var selectionRevision = 0

    var selectedPropertyId: UUID? {
        get {
            _ = selectionRevision
            return UUID(uuidString: UserDefaults.standard.string(forKey: "prvio.selectedPropertyId") ?? "")
        }
        set {
            selectionRevision &+= 1
            UserDefaults.standard.set(newValue?.uuidString, forKey: "prvio.selectedPropertyId")
        }
    }

    var primary: PropertyModel? {
        if let id = selectedPropertyId, let p = properties.first(where: { $0.id == id }) { return p }
        return properties.first
    }

    func select(_ property: PropertyModel) {
        selectedPropertyId = property.id
        Self.activePropertyId = property.id
    }

    /// Mirror of `primary?.id` readable from any service without holding a
    /// reference to this instance. Switching property re-points every
    /// property-scoped query in the app at the newly selected home.
    static private(set) var activePropertyId: UUID?

    /// The group chat's own name, stored in `chat_group_settings` — deliberately
    /// separate from the property's name, so renaming the chat never renames the
    /// property. Empty means "not customised": fall back to the property name.
    var groupChatName: String = ""

    /// The title to display for the group chat: the custom name if set, otherwise
    /// the property name, otherwise a generic fallback.
    var groupChatDisplayName: String {
        if !groupChatName.isEmpty { return groupChatName }
        let prop = primary?.name ?? ""
        return prop.isEmpty ? String(localized: "Chat Grup") : prop
    }

    /// Pull the custom group chat name for the primary property into the store.
    func loadGroupChatName() async {
        guard let pid = primary?.id else { return }
        struct Row: Decodable { let name: String? }
        let rows: [Row]? = try? await supabase
            .from("chat_group_settings")
            .select("name")
            .eq("property_id", value: pid.uuidString)
            .execute()
            .value
        groupChatName = rows?.first?.name ?? ""
    }

    /// Rename the group chat only. Writes to `chat_group_settings`, never to the
    /// property row.
    func updateGroupChatName(_ name: String) async {
        guard let pid = primary?.id else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        groupChatName = trimmed
        struct Payload: Encodable { let property_id: String; let name: String }
        _ = try? await supabase
            .from("chat_group_settings")
            .upsert(Payload(property_id: pid.uuidString, name: trimmed), onConflict: "property_id")
            .execute()
    }

    /// Load the current user's role on the primary property.
    ///
    /// nil means "not resolved yet" and fails open so the owner's UI never
    /// flashes hidden during startup. Once the answer is definitive, an
    /// account with no active membership is clamped to "guest" — an invited
    /// user who isn't (or is no longer) a member must not see the owner UI.
    /// A transient network error keeps the last known role instead of
    /// silently re-opening everything.
    func loadMyRole() async {
        guard let uid = supabase.auth.currentSession?.user.id else {
            myRole = nil; return
        }
        guard let pid = primary?.id else {
            // Signed in with no visible property. Only clamp once the
            // property list has definitively loaded empty.
            if !isLoading && properties.isEmpty { myRole = "guest" }
            return
        }
        struct Row: Decodable { let role: String }
        do {
            let rows: [Row] = try await supabase
                .from("property_members")
                .select("role")
                .eq("property_id", value: pid.uuidString)
                .eq("user_id", value: uid.uuidString)
                .eq("status", value: "active")
                .limit(1)
                .execute()
                .value
            myRole = rows.first?.role ?? "guest"
        } catch {
            // Keep the previous answer — stale gating beats fail-open.
        }
    }

    func load() async {
        // Paint the last known state instantly; the network refresh follows.
        if properties.isEmpty, let cached = ServiceCache.load([PropertyModel].self, entity: "properties") {
            properties = cached
            Self.activePropertyId = primary?.id
        }
        isLoading = true
        defer { isLoading = false }
        do {
            properties = try await supabase
                .from("properties")
                .select()
                .order("created_at", ascending: true)
                .execute()
                .value
            ServiceCache.save(properties, entity: "properties")
        } catch {
            if error is CancellationError { return }
            self.error = error.localizedDescription
        }
        Self.activePropertyId = primary?.id
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
            _ = try? await supabase
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
