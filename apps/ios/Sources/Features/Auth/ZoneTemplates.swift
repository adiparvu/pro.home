import Foundation

struct ZoneTemplate {
    let name: String
    let icon: String
    let colorHex: String
}

enum PropertyTypeZones {
    static func templates(for type: String) -> [ZoneTemplate] {
        switch type.lowercased() {
        case "house":
            return [
                ZoneTemplate(name: "Living Room", icon: "sofa.fill", colorHex: "#5E5CE6"),
                ZoneTemplate(name: "Kitchen", icon: "fork.knife", colorHex: "#FF9F0A"),
                ZoneTemplate(name: "Bedroom", icon: "bed.double.fill", colorHex: "#30D158"),
                ZoneTemplate(name: "Bathroom", icon: "shower.fill", colorHex: "#64D2FF"),
                ZoneTemplate(name: "Hallway", icon: "door.left.hand.open", colorHex: "#FF6961"),
                ZoneTemplate(name: "Garden", icon: "leaf.fill", colorHex: "#34C759"),
            ]
        case "apartment":
            return [
                ZoneTemplate(name: "Living Room", icon: "sofa.fill", colorHex: "#5E5CE6"),
                ZoneTemplate(name: "Kitchen", icon: "fork.knife", colorHex: "#FF9F0A"),
                ZoneTemplate(name: "Bedroom", icon: "bed.double.fill", colorHex: "#30D158"),
                ZoneTemplate(name: "Bathroom", icon: "shower.fill", colorHex: "#64D2FF"),
            ]
        case "villa":
            return [
                ZoneTemplate(name: "Living Room", icon: "sofa.fill", colorHex: "#5E5CE6"),
                ZoneTemplate(name: "Kitchen", icon: "fork.knife", colorHex: "#FF9F0A"),
                ZoneTemplate(name: "Master Bedroom", icon: "bed.double.fill", colorHex: "#30D158"),
                ZoneTemplate(name: "Guest Bedroom", icon: "bed.double.fill", colorHex: "#64D2FF"),
                ZoneTemplate(name: "Bathroom", icon: "shower.fill", colorHex: "#64D2FF"),
                ZoneTemplate(name: "Garden", icon: "leaf.fill", colorHex: "#34C759"),
                ZoneTemplate(name: "Garage", icon: "car.fill", colorHex: "#8E8E93"),
                ZoneTemplate(name: "Pool", icon: "water.waves", colorHex: "#0A84FF"),
            ]
        case "studio":
            return [
                ZoneTemplate(name: "Main Room", icon: "house.fill", colorHex: "#5E5CE6"),
                ZoneTemplate(name: "Bathroom", icon: "shower.fill", colorHex: "#64D2FF"),
                ZoneTemplate(name: "Kitchen Corner", icon: "fork.knife", colorHex: "#FF9F0A"),
            ]
        default:
            return [
                ZoneTemplate(name: "Living Room", icon: "sofa.fill", colorHex: "#5E5CE6"),
                ZoneTemplate(name: "Bedroom", icon: "bed.double.fill", colorHex: "#30D158"),
                ZoneTemplate(name: "Bathroom", icon: "shower.fill", colorHex: "#64D2FF"),
            ]
        }
    }
}
