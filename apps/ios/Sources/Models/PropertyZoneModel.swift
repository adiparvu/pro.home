import SwiftUI
import CoreLocation
import MapKit

// MARK: - Geo point (matches the jsonb {"lat":..,"lon":..} stored per polygon vertex)

struct GeoPoint: Codable, Equatable, Hashable {
    var lat: Double
    var lon: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

// MARK: - Image point (normalized 0–1 vertex on the static aerial photo)

struct ImagePoint: Codable, Equatable, Hashable {
    var x: Double
    var y: Double
}

// MARK: - PropertyZone

struct PropertyZone: Identifiable, Codable, Equatable {
    let id: UUID
    let propertyId: UUID
    var name: String
    var icon: String
    var colorHex: String
    var layer: PropertyLayer
    var healthScore: Int
    var polygon: [GeoPoint]
    var imagePolygon: [ImagePoint]?
    var notes: String?
    /// The immersive BACKDROP of the space page (cover photo).
    var photoUrl: String?
    /// The small identity disc (hero + list rows) — separate from the
    /// backdrop (migration 168) so one photo can set the mood and another
    /// can identify the space.
    var avatarUrl: String?
    var sortOrder: Int
    /// Estate OS (E1): what KIND of space this zone is (`SpaceKind` raw
    /// value — "pond", "garden"…). nil = never classified; readers use
    /// `resolvedSpaceKind`, which falls back to a conservative name/icon
    /// heuristic. Written only through `PropertyZoneService.setSpaceKind`.
    var spaceKind: String?
    let createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, icon, layer, polygon, notes
        case imagePolygon = "image_polygon"
        case propertyId  = "property_id"
        case colorHex    = "color_hex"
        case healthScore = "health_score"
        case photoUrl    = "photo_url"
        case avatarUrl   = "avatar_url"
        case sortOrder   = "sort_order"
        case spaceKind   = "space_kind"
        case createdAt   = "created_at"
        case updatedAt   = "updated_at"
    }

    // Coordinates for MapPolygon
    var coordinates: [CLLocationCoordinate2D] {
        polygon.map(\.coordinate)
    }

    var imagePoints: [ImagePoint] { imagePolygon ?? [] }
    var hasImageShape: Bool { imagePoints.count >= 3 }

    /// Ray-casting test: is a normalized (0–1) image point inside this zone's
    /// drawn polygon? Used to associate freely-placed element pins with a zone.
    func containsImage(x: Double, y: Double) -> Bool {
        let pts = imagePoints
        guard pts.count >= 3 else { return false }
        var inside = false
        var j = pts.count - 1
        for i in 0..<pts.count {
            let xi = pts[i].x, yi = pts[i].y
            let xj = pts[j].x, yj = pts[j].y
            if ((yi > y) != (yj > y)),
               x < (xj - xi) * (y - yi) / (yj - yi) + xi {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// Normalized centroid (0–1) of the image polygon, for placing a label.
    var imageCentroid: ImagePoint? {
        guard !imagePoints.isEmpty else { return nil }
        let n = Double(imagePoints.count)
        return ImagePoint(x: imagePoints.map(\.x).reduce(0, +) / n,
                          y: imagePoints.map(\.y).reduce(0, +) / n)
    }

    var isDrawable: Bool { polygon.count >= 3 }

    var tint: Color { Color(hex: colorHex) ?? layer.color }

    var healthColor: Color {
        switch healthScore {
        case 80...:  return Color(red: 0.20, green: 0.80, blue: 0.45)
        case 50..<80: return .orange
        default:      return .red
        }
    }

    /// Centroid of the polygon (falls back to average of vertices).
    var center: CLLocationCoordinate2D {
        guard !polygon.isEmpty else {
            return CLLocationCoordinate2D(latitude: 0, longitude: 0)
        }
        let lat = polygon.map(\.lat).reduce(0, +) / Double(polygon.count)
        let lon = polygon.map(\.lon).reduce(0, +) / Double(polygon.count)
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Camera region tightly framing the zone, with a little padding.
    var region: MKCoordinateRegion {
        guard !polygon.isEmpty else {
            return MKCoordinateRegion(
                center: center,
                span: MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002)
            )
        }
        let lats = polygon.map(\.lat)
        let lons = polygon.map(\.lon)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else {
            return MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002))
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.6, 0.0008),
            longitudeDelta: max((maxLon - minLon) * 1.6, 0.0008)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    /// Ray-casting point-in-polygon test (used to detect taps on a zone).
    func contains(_ point: CLLocationCoordinate2D) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let xi = polygon[i].lon, yi = polygon[i].lat
            let xj = polygon[j].lon, yj = polygon[j].lat
            let intersect = ((yi > point.latitude) != (yj > point.latitude)) &&
                (point.longitude < (xj - xi) * (point.latitude - yi) / ((yj - yi) == 0 ? .leastNonzeroMagnitude : (yj - yi)) + xi)
            if intersect { inside.toggle() }
            j = i
        }
        return inside
    }

    /// A default square zone (~`metres` per side) centred on a coordinate.
    static func squarePolygon(around center: CLLocationCoordinate2D, metres: Double = 12) -> [GeoPoint] {
        let dLat = metres / 111_320.0
        let dLon = metres / (111_320.0 * max(cos(center.latitude * .pi / 180), 0.000001))
        return [
            GeoPoint(lat: center.latitude - dLat, lon: center.longitude - dLon),
            GeoPoint(lat: center.latitude - dLat, lon: center.longitude + dLon),
            GeoPoint(lat: center.latitude + dLat, lon: center.longitude + dLon),
            GeoPoint(lat: center.latitude + dLat, lon: center.longitude - dLon),
        ]
    }
}

// MARK: - Write payload

struct NewPropertyZone: Encodable {
    let propertyId: UUID
    var name: String
    var icon: String
    var colorHex: String
    var layer: String
    var healthScore: Int
    var polygon: [GeoPoint]
    var imagePolygon: [ImagePoint]? = nil
    var photoUrl: String?
    var avatarUrl: String? = nil
    var sortOrder: Int
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case name, icon, layer, polygon
        case imagePolygon = "image_polygon"
        case propertyId  = "property_id"
        case colorHex    = "color_hex"
        case healthScore = "health_score"
        case photoUrl    = "photo_url"
        case avatarUrl   = "avatar_url"
        case sortOrder   = "sort_order"
        case createdAt   = "created_at"
        case updatedAt   = "updated_at"
    }
}

