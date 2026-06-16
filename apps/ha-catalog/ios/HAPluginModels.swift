import Foundation

// MARK: - Plugin Category

enum HAPluginCategory: String, CaseIterable, Codable, Identifiable {
    case integrations
    case ai
    case cameras
    case security
    case energy
    case garden
    case voice
    case automations
    case monitoring
    case media
    case mqtt
    case zigbee
    case matter
    case dashboards
    case cards
    case themes
    case utilities

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .integrations: return "Integrations"
        case .ai:           return "AI"
        case .cameras:      return "Cameras"
        case .security:     return "Security"
        case .energy:       return "Energy"
        case .garden:       return "Garden"
        case .voice:        return "Voice"
        case .automations:  return "Automations"
        case .monitoring:   return "Monitoring"
        case .media:        return "Media"
        case .mqtt:         return "MQTT"
        case .zigbee:       return "Zigbee"
        case .matter:       return "Matter"
        case .dashboards:   return "Dashboards"
        case .cards:        return "Cards"
        case .themes:       return "Themes"
        case .utilities:    return "Utilities"
        }
    }

    var icon: String {
        switch self {
        case .integrations: return "puzzlepiece.extension.fill"
        case .ai:           return "sparkles"
        case .cameras:      return "camera.fill"
        case .security:     return "lock.shield.fill"
        case .energy:       return "bolt.fill"
        case .garden:       return "leaf.fill"
        case .voice:        return "mic.fill"
        case .automations:  return "gearshape.2.fill"
        case .monitoring:   return "chart.xyaxis.line"
        case .media:        return "play.fill"
        case .mqtt:         return "antenna.radiowaves.left.and.right"
        case .zigbee:       return "wifi"
        case .matter:       return "dot.radiowaves.right"
        case .dashboards:   return "rectangle.3.offgrid.fill"
        case .cards:        return "square.grid.2x2.fill"
        case .themes:       return "paintpalette.fill"
        case .utilities:    return "wrench.and.screwdriver.fill"
        }
    }
}

// MARK: - Plugin Status

enum HAPluginStatus: String, Codable {
    case active
    case archived
    case deprecated
    case unknown
}

// MARK: - Install Type

enum HAPluginInstallType: String, Codable {
    case hacs       // Install via Home Assistant Community Store
    case addon      // HA Add-on (runs in supervisor)
    case manual     // Manual file copy / Git clone
    case lovelace   // Frontend resource (JS/CSS)
    case theme      // YAML theme file
    case blueprint  // HA Blueprint YAML
}

// MARK: - Plugin Manifest (read-only catalog entry)

struct HAPluginManifest: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let category: HAPluginCategory
    let subcategory: String?
    let description: String
    let githubUrl: URL?
    let websiteUrl: URL?
    let hacsUrl: URL?
    let docsUrl: URL?
    let license: String?
    let status: HAPluginStatus
    let hacsCompatible: Bool
    let stars: Int?
    let lastUpdated: String?
    let tags: [String]
    let installType: HAPluginInstallType
    let requiresHAVersion: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, category, subcategory, description
        case githubUrl, websiteUrl, hacsUrl, docsUrl
        case license, status, hacsCompatible, stars, lastUpdated
        case tags, installType, requiresHAVersion
    }
}

// MARK: - Installed Plugin State

struct HAInstalledPlugin: Identifiable, Codable {
    let id: String              // matches HAPluginManifest.id
    var isEnabled: Bool
    var installedAt: Date
    var version: String?
    var notes: String?
    var haInstanceId: String?   // which HA instance this is installed on
}

// MARK: - HA Instance (connection target)

struct HAInstance: Identifiable, Codable {
    let id: UUID
    var name: String
    var url: URL
    var accessToken: String     // Long-lived access token
    var isDefault: Bool
    var version: String?        // Detected HA version
    var lastSeen: Date?
}

// MARK: - Plugin Install Request

struct HAPluginInstallRequest {
    let manifest: HAPluginManifest
    let targetInstance: HAInstance
    let autoEnable: Bool
}

// MARK: - Plugin Catalog Response

struct HAPluginCatalog: Codable {
    let version: String
    let builtAt: String
    let plugins: [HAPluginManifest]
    let categories: [HACategoryMeta]
}

struct HACategoryMeta: Codable, Identifiable {
    let id: String
    let name: String
    let icon: String
    let color: String
    let description: String
    var pluginCount: Int
}
