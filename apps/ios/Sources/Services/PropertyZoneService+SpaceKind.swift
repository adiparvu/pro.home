import Foundation

// MARK: - Space kind persistence (Estate OS E1)
//
// The one write the estate surfaces need: classify a zone as a SpaceKind.
// A targeted single-column PATCH (never the full-row `update`, whose
// `NewPropertyZone` payload doesn't carry `space_kind` — deliberately, so
// ordinary zone edits can never clobber a stored kind), followed by the
// sanctioned refresh: `load(propertyId:)` re-fetches the service-owned
// `zones` array instead of mutating it in place.

extension PropertyZoneService {
    /// Persists (or clears, with nil) a zone's space kind, then reloads the
    /// zone list so every observer re-renders from the server's truth.
    func setSpaceKind(_ kind: SpaceKind?, for zone: PropertyZone, propertyId: UUID) async {
        let patch = SpaceKindPatch(spaceKind: kind?.rawValue,
                                   updatedAt: ISODate.string(from: Date()))
        do {
            try await supabase
                .from("property_zones")
                .update(patch)
                .eq("id", value: zone.id.uuidString)
                .execute()
        } catch {
            self.error = error.localizedDescription
        }
        await load(propertyId: propertyId)
    }
}

/// PATCH body for `setSpaceKind`. Encodes `space_kind` explicitly — even
/// when nil — so clearing a kind writes SQL NULL instead of being omitted.
private struct SpaceKindPatch: Encodable {
    let spaceKind: String?
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case spaceKind = "space_kind"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(spaceKind, forKey: .spaceKind)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}
