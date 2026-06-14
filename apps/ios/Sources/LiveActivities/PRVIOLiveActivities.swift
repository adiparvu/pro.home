import ActivityKit
import Foundation

// MARK: - Shopping Live Activity

struct ShoppingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var itemsBought: Int
        var totalItems: Int
        var listName: String
    }
    let propertyName: String
    let listName: String
}

// MARK: - Maintenance Live Activity

struct MaintenanceActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var progress: Double
        var stepDescription: String
        var isComplete: Bool
    }
    let taskTitle: String
    let category: String
}

// MARK: - Delivery Live Activity

struct DeliveryActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var status: String
        var statusLabel: String
        var eta: String?
    }
    let trackingNumber: String
    let carrier: String
    let description: String
}

// MARK: - Plant Care Live Activity

struct PlantCareActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var wateredCount: Int
        var totalCount: Int
        var lastWateredName: String?
    }
    let propertyName: String
}
