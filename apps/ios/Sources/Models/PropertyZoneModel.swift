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
    var notes: String?
    var sortOrder: Int
    let createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, icon, layer, polygon, notes
        case propertyId  = "property_id"
        case colorHex    = "color_hex"
        case healthScore = "health_score"
        case sortOrder   = "sort_order"
        case createdAt   = "created_at"
        case updatedAt   = "updated_at"
    }

    // Coordinates for MapPolygon
    var coordinates: [CLLocationCoordinate2D] {
        polygon.map(\.coordinate)
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
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
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
    var sortOrder: Int
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case name, icon, layer, polygon
        case propertyId  = "property_id"
        case colorHex    = "color_hex"
        case healthScore = "health_score"
        case sortOrder   = "sort_order"
        case createdAt   = "created_at"
        case updatedAt   = "updated_at"
    }
}

