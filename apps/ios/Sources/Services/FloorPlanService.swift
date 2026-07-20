import Foundation
import Observation
import Supabase

// MARK: - Floor plan service (Plans & 3D rebuild, phase A)
//
// Owns the `floor_plans` and `rooms` tables for the primary property.
// Room scans (.usdz from RoomPlan) upload into the private `documents`
// bucket under plans/<propertyId>/ and rows store only the object path —
// display always goes through a short-lived signed URL.

@MainActor
@Observable
final class FloorPlanService {
    var floors: [FloorPlanRecord] = []
    var rooms: [RoomRecord] = []
    var isLoading = false
    var error: String?
    private(set) var propertyId: UUID?

    // MARK: Load

    func load(propertyId: UUID) async {
        self.propertyId = propertyId
        isLoading = floors.isEmpty && rooms.isEmpty
        defer { isLoading = false }
        do {
            floors = try await supabase
                .from("floor_plans")
                .select()
                .eq("property_id", value: propertyId.uuidString)
                .order("sort_order")
                .execute()
                .value
            rooms = try await supabase
                .from("rooms")
                .select()
                .eq("property_id", value: propertyId.uuidString)
                .order("sort_order")
                .execute()
                .value
        } catch {
            self.error = error.recordableDescription
        }
    }

    /// Rooms on a floor, by the DB `floor` level (rooms created before any
    /// floor plan existed still group correctly).
    func rooms(onLevel level: Int) -> [RoomRecord] {
        rooms.filter { $0.floor == level }
    }

    /// Every distinct level present, floors and loose rooms merged.
    var levels: [Int] {
        var set = Set(floors.map(\.floorNumber))
        rooms.forEach { set.insert($0.floor) }
        return set.sorted()
    }

    func floor(forLevel level: Int) -> FloorPlanRecord? {
        floors.first { $0.floorNumber == level }
    }

    // MARK: Floors

    func addFloor(name: String, level: Int) async {
        guard let propertyId else { return }
        struct Insert: Encodable {
            let property_id: String
            let name: String
            let floor_number: Int
            let sort_order: Int
            let created_at: String
            let updated_at: String
        }
        let now = ISODate.string(from: Date())
        do {
            let created: FloorPlanRecord = try await supabase
                .from("floor_plans")
                .insert(Insert(property_id: propertyId.uuidString, name: name,
                               floor_number: level, sort_order: floors.count,
                               created_at: now, updated_at: now))
                .select()
                .single()
                .execute()
                .value
            floors.append(created)
            floors.sort { $0.floorNumber < $1.floorNumber }
        } catch {
            self.error = error.recordableDescription
        }
    }

    func renameFloor(_ floor: FloorPlanRecord, to name: String) async {
        struct Patch: Encodable { let name: String; let updated_at: String }
        do {
            try await supabase
                .from("floor_plans")
                .update(Patch(name: name, updated_at: ISODate.string(from: Date())))
                .eq("id", value: floor.id.uuidString)
                .execute()
            if let idx = floors.firstIndex(where: { $0.id == floor.id }) {
                floors[idx].name = name
            }
        } catch {
            self.error = error.recordableDescription
        }
    }

    /// Deleting a floor keeps its rooms (they fall back to loose rooms on
    /// the same level) — a floor is an organizer, not the rooms' owner.
    func deleteFloor(_ floor: FloorPlanRecord) async {
        struct Unlink: Encodable {
            let floor_plan_id: String?
        }
        do {
            try await supabase
                .from("rooms")
                .update(Unlink(floor_plan_id: nil))
                .eq("floor_plan_id", value: floor.id.uuidString)
                .execute()
            try await supabase
                .from("floor_plans")
                .delete()
                .eq("id", value: floor.id.uuidString)
                .execute()
            floors.removeAll { $0.id == floor.id }
            for idx in rooms.indices where rooms[idx].floorPlanId == floor.id {
                rooms[idx].floorPlanId = nil
            }
        } catch {
            self.error = error.recordableDescription
        }
    }

    // MARK: Rooms

    func addRoom(name: String, type: String, level: Int, areaSqm: Double?) async {
        guard let propertyId else { return }
        struct Insert: Encodable {
            let property_id: String
            let name: String
            let room_type: String
            let floor: Int
            let area_sqm: Double?
            let floor_plan_id: String?
            let sort_order: Int
            let created_at: String
            let updated_at: String
        }
        let now = ISODate.string(from: Date())
        do {
            let created: RoomRecord = try await supabase
                .from("rooms")
                .insert(Insert(property_id: propertyId.uuidString, name: name,
                               room_type: type, floor: level, area_sqm: areaSqm,
                               floor_plan_id: floor(forLevel: level)?.id.uuidString,
                               sort_order: rooms.count,
                               created_at: now, updated_at: now))
                .select()
                .single()
                .execute()
                .value
            rooms.append(created)
        } catch {
            self.error = error.recordableDescription
        }
    }

    func deleteRoom(_ room: RoomRecord) async {
        do {
            if let path = room.scanPath, !path.isEmpty {
                // Best-effort: an orphaned object costs storage, not
                // correctness — the row deletion must not fail on it.
                try? await supabase.storage.from("documents").remove(paths: [path])
            }
            try await supabase
                .from("rooms")
                .delete()
                .eq("id", value: room.id.uuidString)
                .execute()
            rooms.removeAll { $0.id == room.id }
        } catch {
            self.error = error.recordableDescription
        }
    }

    // MARK: Zone bridge (migration 159)

    /// The room representing a zone on the plan — `zone_id` first, the
    /// app-wide trimmed/case/diacritic-insensitive name match as the
    /// fallback for rows created before the bridge existed.
    func room(for zone: PropertyZone) -> RoomRecord? {
        if let byId = rooms.first(where: { $0.zoneId == zone.id }) { return byId }
        return rooms.first {
            $0.name.compare(zone.name, options: [.caseInsensitive, .diacriticInsensitive])
                == .orderedSame
        }
    }

    /// Resolves the zone's plan room, creating one when none exists —
    /// the entry point both "place on plan" and space-page scans use.
    @discardableResult
    func ensureRoom(for zone: PropertyZone, level: Int = 0) async -> RoomRecord? {
        if let existing = room(for: zone) {
            // A name-matched room adopts the id-link so the join is stable
            // from here on.
            if existing.zoneId == nil { await link(existing, to: zone) }
            return room(for: zone)
        }
        guard let propertyId else { return nil }
        struct Insert: Encodable {
            let property_id: String
            let name: String
            let room_type: String
            let floor: Int
            let floor_plan_id: String?
            let zone_id: String
            let sort_order: Int
            let created_at: String
            let updated_at: String
        }
        let now = ISODate.string(from: Date())
        do {
            let created: RoomRecord = try await supabase
                .from("rooms")
                .insert(Insert(property_id: propertyId.uuidString, name: zone.name,
                               room_type: Self.roomType(for: zone.resolvedSpaceKind),
                               floor: level,
                               floor_plan_id: floor(forLevel: level)?.id.uuidString,
                               zone_id: zone.id.uuidString,
                               sort_order: rooms.count,
                               created_at: now, updated_at: now))
                .select()
                .single()
                .execute()
                .value
            rooms.append(created)
            return created
        } catch {
            self.error = error.recordableDescription
            return nil
        }
    }

    /// Targeted PATCH of the id-link only.
    func link(_ room: RoomRecord, to zone: PropertyZone) async {
        struct Patch: Encodable { let zone_id: String; let updated_at: String }
        do {
            try await supabase
                .from("rooms")
                .update(Patch(zone_id: zone.id.uuidString,
                              updated_at: ISODate.string(from: Date())))
                .eq("id", value: room.id.uuidString)
                .execute()
            if let idx = rooms.firstIndex(where: { $0.id == room.id }) {
                rooms[idx].zoneId = zone.id
            }
        } catch {
            self.error = error.recordableDescription
        }
    }

    /// The closest `room_type` enum value for a space kind — a display
    /// default for auto-created plan rooms, freely editable in Blueprints.
    private static func roomType(for kind: SpaceKind) -> String {
        switch kind {
        case .garage:              return "garage"
        case .basement:            return "basement"
        case .garden, .greenhouse: return "garden"
        case .house, .pond, .forest, .custom: return "other"
        }
    }

    /// Persists a room's plan rectangle (percent coordinates, 0–100) after
    /// a drag/resize on the 2D canvas.
    func updateGeometry(_ room: RoomRecord, xPct: Double, yPct: Double,
                        widthPct: Double, heightPct: Double) async {
        struct Patch: Encodable {
            let x_pct: Double
            let y_pct: Double
            let width_pct: Double
            let height_pct: Double
            let updated_at: String
        }
        do {
            try await supabase
                .from("rooms")
                .update(Patch(x_pct: xPct, y_pct: yPct,
                              width_pct: widthPct, height_pct: heightPct,
                              updated_at: ISODate.string(from: Date())))
                .eq("id", value: room.id.uuidString)
                .execute()
            if let idx = rooms.firstIndex(where: { $0.id == room.id }) {
                rooms[idx].xPct = xPct
                rooms[idx].yPct = yPct
                rooms[idx].widthPct = widthPct
                rooms[idx].heightPct = heightPct
            }
        } catch {
            self.error = error.recordableDescription
        }
    }

    // MARK: Scans

    /// Uploads a RoomPlan .usdz for a room and records its object path.
    /// Upsert: re-scanning a room replaces the old model in place.
    func attachScan(fileURL: URL, to room: RoomRecord) async {
        guard let propertyId else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let path = "plans/\(propertyId.uuidString)/\(room.id.uuidString).usdz"
            try await supabase.storage
                .from("documents")
                .upload(path, data: data,
                        options: FileOptions(contentType: "model/vnd.usdz+zip", upsert: true))
            struct Patch: Encodable { let scan_path: String; let updated_at: String }
            try await supabase
                .from("rooms")
                .update(Patch(scan_path: path, updated_at: ISODate.string(from: Date())))
                .eq("id", value: room.id.uuidString)
                .execute()
            if let idx = rooms.firstIndex(where: { $0.id == room.id }) {
                rooms[idx].scanPath = path
            }
        } catch {
            self.error = error.recordableDescription
        }
    }

    /// Downloads the room's scan to a local .usdz (QuickLook needs a file
    /// URL with the right extension) via a short-lived signed URL.
    func localScanURL(for room: RoomRecord) async -> URL? {
        guard let path = room.scanPath, !path.isEmpty else { return nil }
        do {
            let signed = try await supabase.storage
                .from("documents")
                .createSignedURL(path: path, expiresIn: 3600)
            let (data, _) = try await URLSession.shared.data(from: signed)
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("room-\(room.id.uuidString).usdz")
            try data.write(to: tmp, options: .atomic)
            return tmp
        } catch {
            self.error = error.recordableDescription
            return nil
        }
    }
}
