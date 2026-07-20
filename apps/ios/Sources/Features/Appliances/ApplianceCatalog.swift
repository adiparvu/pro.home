import SwiftUI

// MARK: - Built-in appliance catalog
//
// The appliance types a home actually owns, each carrying its category and
// the brands present on the Romanian and Belgian markets. Picking a type
// sets the category and pre-fills the name; picking a brand completes it
// ("Frigider Bosch") — the form fills itself and the model number stays
// free text, read off the rating plate (or scanned with the OCR button).

struct ApplianceType: Identifiable, Equatable {
    let id: String
    let nameEN: String
    let nameRO: String
    let icon: String
    let category: ApplianceCategory
    let brands: [String]

    var name: String { Locale.appIsRomanian ? nameRO : nameEN }
}

enum ApplianceCatalog {

    private static let coldBrands = ["Arctic", "Beko", "Bosch", "Samsung", "LG", "Whirlpool",
                                     "Electrolux", "Liebherr", "Gorenje", "Haier", "Hisense", "Indesit"]
    private static let cookBrands = ["Bosch", "Electrolux", "Whirlpool", "Samsung", "Beko",
                                     "AEG", "Gorenje", "Miele", "Hansa", "Teka"]
    private static let laundryBrands = ["Arctic", "Beko", "Bosch", "Samsung", "LG", "Whirlpool",
                                        "Electrolux", "AEG", "Candy", "Indesit", "Miele"]

    static let types: [ApplianceType] = [
        // Kitchen
        ApplianceType(id: "fridge", nameEN: "Refrigerator", nameRO: "Frigider",
                      icon: "refrigerator", category: .kitchen, brands: coldBrands),
        ApplianceType(id: "freezer", nameEN: "Freezer", nameRO: "Congelator",
                      icon: "snowflake", category: .kitchen, brands: coldBrands),
        ApplianceType(id: "oven", nameEN: "Oven", nameRO: "Cuptor",
                      icon: "oven", category: .kitchen, brands: cookBrands),
        ApplianceType(id: "cooktop", nameEN: "Cooktop", nameRO: "Plită",
                      icon: "stove", category: .kitchen, brands: cookBrands),
        ApplianceType(id: "hood", nameEN: "Range hood", nameRO: "Hotă",
                      icon: "wind", category: .kitchen,
                      brands: ["Faber", "Franke", "Teka", "Bosch", "Electrolux", "Pyramis", "Hansa"]),
        ApplianceType(id: "dishwasher", nameEN: "Dishwasher", nameRO: "Mașină de spălat vase",
                      icon: "dishwasher", category: .kitchen,
                      brands: ["Bosch", "Beko", "Whirlpool", "Electrolux", "AEG", "Miele", "Indesit", "Arctic"]),
        ApplianceType(id: "microwave", nameEN: "Microwave", nameRO: "Cuptor cu microunde",
                      icon: "microwave", category: .kitchen,
                      brands: ["Samsung", "LG", "Whirlpool", "Beko", "Sharp", "Panasonic", "Candy", "Heinner"]),
        ApplianceType(id: "coffee", nameEN: "Coffee machine", nameRO: "Espressor",
                      icon: "cup.and.saucer.fill", category: .kitchen,
                      brands: ["DeLonghi", "Philips", "Krups", "Jura", "Sage", "Nespresso", "Tchibo"]),

        // Laundry
        ApplianceType(id: "washer", nameEN: "Washing machine", nameRO: "Mașină de spălat",
                      icon: "washer", category: .laundry, brands: laundryBrands),
        ApplianceType(id: "dryer", nameEN: "Tumble dryer", nameRO: "Uscător de rufe",
                      icon: "dryer", category: .laundry, brands: laundryBrands),
        ApplianceType(id: "iron", nameEN: "Iron / steam station", nameRO: "Fier / stație de călcat",
                      icon: "tshirt", category: .laundry,
                      brands: ["Philips", "Tefal", "Braun", "Rowenta", "Bosch"]),

        // HVAC & water
        ApplianceType(id: "boiler", nameEN: "Gas boiler", nameRO: "Centrală termică",
                      icon: "flame.fill", category: .hvac,
                      brands: ["Ariston", "Bosch", "Vaillant", "Viessmann", "Immergas", "Ferroli", "Buderus", "Motan"]),
        ApplianceType(id: "waterheater", nameEN: "Water heater", nameRO: "Boiler electric",
                      icon: "water.heater", category: .hvac,
                      brands: ["Ariston", "Tesy", "Eldom", "Bosch", "Electrolux"]),
        ApplianceType(id: "ac", nameEN: "Air conditioner", nameRO: "Aer condiționat",
                      icon: "air.conditioner.horizontal", category: .hvac,
                      brands: ["Daikin", "Mitsubishi Electric", "Gree", "Midea", "LG", "Samsung", "Fujitsu", "Toshiba"]),
        ApplianceType(id: "purifier", nameEN: "Air purifier", nameRO: "Purificator de aer",
                      icon: "air.purifier", category: .hvac,
                      brands: ["Dyson", "Philips", "Xiaomi", "Levoit", "Sharp"]),
        ApplianceType(id: "dehumidifier", nameEN: "Dehumidifier", nameRO: "Dezumidificator",
                      icon: "humidifier", category: .hvac,
                      brands: ["Trotec", "DeLonghi", "Argo", "Klarstein"]),

        // Bathroom
        ApplianceType(id: "hydrophore", nameEN: "Water pump", nameRO: "Hidrofor",
                      icon: "spigot", category: .bathroom,
                      brands: ["Grundfos", "Wilo", "Pedrollo", "DAB"]),

        // Security
        ApplianceType(id: "camera", nameEN: "Security camera", nameRO: "Cameră de supraveghere",
                      icon: "video.fill", category: .security,
                      brands: ["Hikvision", "Dahua", "Ring", "Eufy", "TP-Link Tapo", "Xiaomi"]),
        ApplianceType(id: "alarm", nameEN: "Alarm system", nameRO: "Sistem de alarmă",
                      icon: "bell.fill", category: .security,
                      brands: ["Ajax", "Paradox", "DSC", "Ring"]),
        ApplianceType(id: "smartlock", nameEN: "Smart lock", nameRO: "Yală inteligentă",
                      icon: "lock.fill", category: .security,
                      brands: ["Yale", "Nuki", "Tedee", "Aqara"]),
        ApplianceType(id: "intercom", nameEN: "Intercom", nameRO: "Interfon",
                      icon: "phone.fill", category: .security,
                      brands: ["Commax", "Hikvision", "Fermax"]),

        // Entertainment
        ApplianceType(id: "tv", nameEN: "Television", nameRO: "Televizor",
                      icon: "tv", category: .entertainment,
                      brands: ["Samsung", "LG", "Sony", "Philips", "TCL", "Hisense"]),
        ApplianceType(id: "soundbar", nameEN: "Soundbar / speakers", nameRO: "Soundbar / boxe",
                      icon: "hifispeaker.fill", category: .entertainment,
                      brands: ["Samsung", "Sonos", "LG", "Bose", "JBL", "Sony"]),
        ApplianceType(id: "console", nameEN: "Game console", nameRO: "Consolă de jocuri",
                      icon: "gamecontroller.fill", category: .entertainment,
                      brands: ["Sony", "Microsoft", "Nintendo"]),

        // Other
        ApplianceType(id: "vacuum", nameEN: "Vacuum cleaner", nameRO: "Aspirator",
                      icon: "fanblades", category: .other,
                      brands: ["Dyson", "Rowenta", "Philips", "Bosch", "Kärcher", "Roborock", "iRobot", "Xiaomi", "Samsung"]),
        ApplianceType(id: "router", nameEN: "Router / network", nameRO: "Router / rețea",
                      icon: "wifi.router", category: .other,
                      brands: ["TP-Link", "Asus", "Netgear", "Huawei", "Ubiquiti"]),
    ]

    static func type(id: String) -> ApplianceType? { types.first { $0.id == id } }

    /// Types grouped in the categories' declaration order, for the menu.
    static var byCategory: [(category: ApplianceCategory, types: [ApplianceType])] {
        ApplianceCategory.allCases.compactMap { cat in
            let hits = types.filter { $0.category == cat }
            return hits.isEmpty ? nil : (cat, hits)
        }
    }

    /// Brand fallback when no type is selected.
    static let allBrands: [String] = {
        var seen = Set<String>()
        return types.flatMap(\.brands).filter { seen.insert($0).inserted }.sorted()
    }()
}
