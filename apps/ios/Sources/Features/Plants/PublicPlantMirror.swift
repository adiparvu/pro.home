import Foundation

// MARK: - Public plant mirror (migration 174, IMG_8728)
//
// The plant-label QR must answer ANY phone, not just ones with PRVIO:
// showing the Etichetă QR card mirrors the plant's public details
// (name, species, in-garden-since, watering rhythm, property) into
// `public_plants`, which the xparvu.com/p/<uuid> page renders. Opt-in
// by construction — a plant is published the moment its owner opens
// the label card, never before.

enum PublicPlantMirror {
    /// Fire-and-forget upsert of the plant's public card. Safe to call on
    /// every card appearance — one row per plant, newest data wins.
    static func sync(_ plant: Plant) {
        Task {
            guard let uid = supabase.auth.currentSession?.user.id else { return }
            // The real property ENTITY's name, like the item pages use.
            struct PropRow: Decodable { let name: String }
            let propRow: PropRow? = try? await supabase.from("properties")
                .select("name").eq("id", value: plant.propertyId.uuidString)
                .single().execute().value
            struct Payload: Encodable {
                let plant_uuid, name, user_id: String
                let species, emoji, location, property_name, planted_at: String?
                let watering_interval_days: Int
            }
            let display = (plant.nickname?.isEmpty == false ? plant.nickname! : plant.name)
            let payload = Payload(
                plant_uuid: plant.id.uuidString,
                name: display,
                user_id: uid.uuidString,
                species: plant.species?.isEmpty == false ? plant.species : plant.latinName,
                emoji: plant.emoji.isEmpty ? nil : plant.emoji,
                location: plant.location?.isEmpty == false ? plant.location : nil,
                property_name: propRow.map { $0.name.trimmingCharacters(in: .whitespaces) },
                planted_at: plant.createdAt,
                watering_interval_days: plant.wateringIntervalDays)
            _ = try? await supabase.from("public_plants")
                .upsert(payload, onConflict: "plant_uuid").execute()
        }
    }

    /// Removes the public card (called when the plant is deleted).
    static func remove(plantId: UUID) {
        Task {
            _ = try? await supabase.from("public_plants")
                .delete().eq("plant_uuid", value: plantId.uuidString).execute()
        }
    }
}
