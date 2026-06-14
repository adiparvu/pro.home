import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("prvio.theme")       var theme:             String = "dark"
    @AppStorage("prvio.locale")      var locale:            String = "en"
    @AppStorage("prvio.currency")    var preferredCurrency: String = "EUR"
    @AppStorage("prvio.accentColor") var accentColor:       String = "blue"
    @AppStorage("prvio.hapticOn")    var hapticEnabled:     Bool   = true

    // Customizable floating (speed-dial) buttons — per page.
    // Stored as ordered, comma-separated action rawValues, plus a visibility flag.
    @AppStorage("prvio.quickActions")      var fabHomeRaw:      String = "aria,newTask,chat,scan"
    @AppStorage("prvio.fab.finances")      var fabFinancesRaw:  String = "addExpense"
    @AppStorage("prvio.fab.inventory")     var fabInventoryRaw: String = "scan,addItem"
    @AppStorage("prvio.fab.home.on")       var fabHomeOn:       Bool   = true
    @AppStorage("prvio.fab.finances.on")   var fabFinancesOn:   Bool   = true
    @AppStorage("prvio.fab.inventory.on")  var fabInventoryOn:  Bool   = true

    func fabActions(_ host: FloatingButtonHost) -> [DashboardQuickAction] {
        rawString(for: host)
            .split(separator: ",")
            .compactMap { DashboardQuickAction(rawValue: String($0)) }
    }

    func fabVisible(_ host: FloatingButtonHost) -> Bool {
        switch host {
        case .home:      return fabHomeOn
        case .finances:  return fabFinancesOn
        case .inventory: return fabInventoryOn
        }
    }

    func setFabVisible(_ host: FloatingButtonHost, _ on: Bool) {
        objectWillChange.send()
        switch host {
        case .home:      fabHomeOn = on
        case .finances:  fabFinancesOn = on
        case .inventory: fabInventoryOn = on
        }
    }

    func isFabActionEnabled(_ host: FloatingButtonHost, _ action: DashboardQuickAction) -> Bool {
        fabActions(host).contains(action)
    }

    func setFabAction(_ host: FloatingButtonHost, _ action: DashboardQuickAction, enabled: Bool) {
        var current = fabActions(host)
        if enabled {
            if !current.contains(action) { current.append(action) }
        } else {
            current.removeAll { $0 == action }
        }
        // Persist in canonical order so the speed-dial layout stays predictable.
        let raw = DashboardQuickAction.allCases
            .filter { current.contains($0) }
            .map(\.rawValue)
            .joined(separator: ",")
        // @AppStorage inside an ObservableObject does not auto-publish, so notify
        // observers (floating buttons, settings toggles) explicitly.
        objectWillChange.send()
        switch host {
        case .home:      fabHomeRaw = raw
        case .finances:  fabFinancesRaw = raw
        case .inventory: fabInventoryRaw = raw
        }
    }

    private func rawString(for host: FloatingButtonHost) -> String {
        switch host {
        case .home:      return fabHomeRaw
        case .finances:  return fabFinancesRaw
        case .inventory: return fabInventoryRaw
        }
    }

    var resolvedColorScheme: ColorScheme? {
        switch theme {
        case "light":  return .light
        case "dark":   return .dark
        default:       return nil   // system
        }
    }

    // Sync to Supabase profiles after sign-in
    func syncToProfile(userId: UUID) {
        Task {
            struct Prefs: Encodable {
                let locale: String
                let theme: String
                let updatedAt: String
                enum CodingKeys: String, CodingKey {
                    case locale, theme; case updatedAt = "updated_at"
                }
            }
            try? await supabase
                .from("profiles")
                .update(Prefs(locale: locale, theme: theme, updatedAt: ISO8601DateFormatter().string(from: Date())))
                .eq("id", value: userId.uuidString)
                .execute()
        }
    }

    // Load preferences from profile on first sign-in
    func loadFromProfile(_ profile: ProfileData) {
        locale = profile.locale ?? locale
        theme  = profile.theme  ?? theme
    }

    static let themes: [(code: String, label: String, icon: String)] = [
        ("dark",   "Dark",   "moon.fill"),
        ("light",  "Light",  "sun.max.fill"),
        ("system", "System", "circle.lefthalf.filled"),
    ]

    static let languages: [(code: String, name: String, flag: String)] = [
        ("en", "English",   "🇬🇧"),
        ("ro", "Română",    "🇷🇴"),
        ("de", "Deutsch",   "🇩🇪"),
        ("fr", "Français",  "🇫🇷"),
        ("es", "Español",   "🇪🇸"),
        ("it", "Italiano",  "🇮🇹"),
    ]
}

// MARK: - Dashboard Quick Actions (customizable floating button)

enum DashboardQuickAction: String, CaseIterable, Identifiable {
    case aria
    case newTask
    case chat
    case scan
    case addItem
    case addExpense
    case finances

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aria:       return "ARIA"
        case .newTask:    return "Sarcină nouă"
        case .chat:       return "Chat familie"
        case .scan:       return "Scanare"
        case .addItem:    return "Adaugă obiect"
        case .addExpense: return "Tranzacție nouă"
        case .finances:   return "Finanțe"
        }
    }

    var subtitle: String {
        switch self {
        case .aria:       return "Asistentul AI"
        case .newTask:    return "Adaugă o sarcină"
        case .chat:       return "Mesaje cu familia"
        case .scan:       return "Scanează un cod QR"
        case .addItem:    return "Adaugă în inventar"
        case .addExpense: return "Venit sau cheltuială"
        case .finances:   return "Deschide finanțele"
        }
    }

    var icon: String {
        switch self {
        case .aria:       return "sparkles"
        case .newTask:    return "checklist"
        case .chat:       return "message.fill"
        case .scan:       return "barcode.viewfinder"
        case .addItem:    return "shippingbox.fill"
        case .addExpense: return "creditcard.fill"
        case .finances:   return "chart.pie.fill"
        }
    }

    var color: Color {
        switch self {
        case .aria:       return Color(red: 0.6,  green: 0.35, blue: 0.95)
        case .newTask:    return Color(red: 0.3,  green: 0.85, blue: 0.45)
        case .chat:       return Color(red: 0.35, green: 0.65, blue: 1.0)
        case .scan:       return Color(red: 1.0,  green: 0.65, blue: 0.15)
        case .addItem:    return Color(red: 0.0,  green: 0.6,  blue: 0.85)
        case .addExpense: return Color(red: 0.2,  green: 0.78, blue: 0.6)
        case .finances:   return Color(red: 0.55, green: 0.55, blue: 0.95)
        }
    }
}

// MARK: - Floating Button Hosts (pages that show a customizable speed-dial)

enum FloatingButtonHost: String, CaseIterable, Identifiable {
    case home
    case finances
    case inventory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:      return "Ecran principal"
        case .finances:  return "Finanțe"
        case .inventory: return "Inventar"
        }
    }

    var icon: String {
        switch self {
        case .home:      return "house.fill"
        case .finances:  return "creditcard.fill"
        case .inventory: return "shippingbox.fill"
        }
    }
}
