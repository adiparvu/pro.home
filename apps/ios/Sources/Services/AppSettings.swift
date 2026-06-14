import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("prvio.theme")       var theme:             String = "dark"
    @AppStorage("prvio.locale")      var locale:            String = "en"
    @AppStorage("prvio.currency")    var preferredCurrency: String = "EUR"
    @AppStorage("prvio.accentColor") var accentColor:       String = "blue"
    @AppStorage("prvio.hapticOn")    var hapticEnabled:     Bool   = true

    // Customizable floating (speed-dial) buttons — per page.
    // Stored in UserDefaults, keyed by host, so this scales to any number of pages.
    // (Home keeps its legacy key for backward compatibility.)

    private func actionsKey(_ host: FloatingButtonHost) -> String {
        host == .home ? "prvio.quickActions" : "prvio.fab.\(host.rawValue)"
    }
    private func visibleKey(_ host: FloatingButtonHost) -> String {
        "prvio.fab.\(host.rawValue).on"
    }

    func fabActions(_ host: FloatingButtonHost) -> [DashboardQuickAction] {
        let raw = UserDefaults.standard.string(forKey: actionsKey(host)) ?? host.defaultActionsRaw
        return raw.split(separator: ",").compactMap { DashboardQuickAction(rawValue: String($0)) }
    }

    func fabVisible(_ host: FloatingButtonHost) -> Bool {
        if UserDefaults.standard.object(forKey: visibleKey(host)) == nil { return host.defaultVisible }
        return UserDefaults.standard.bool(forKey: visibleKey(host))
    }

    func setFabVisible(_ host: FloatingButtonHost, _ on: Bool) {
        // Direct UserDefaults writes don't auto-publish, so notify observers explicitly.
        objectWillChange.send()
        UserDefaults.standard.set(on, forKey: visibleKey(host))
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
        objectWillChange.send()
        UserDefaults.standard.set(raw, forKey: actionsKey(host))
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
    case tasks
    case finances
    case analytics
    case inventory
    case documents
    case contractors
    case utilities
    case family
    case blueprints

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:        return "Ecran principal"
        case .tasks:       return "Sarcini"
        case .finances:    return "Finanțe"
        case .analytics:   return "Analiză"
        case .inventory:   return "Inventar"
        case .documents:   return "Documente"
        case .contractors: return "Contractori"
        case .utilities:   return "Utilități"
        case .family:      return "Familie"
        case .blueprints:  return "Planuri & 3D"
        }
    }

    var icon: String {
        switch self {
        case .home:        return "house.fill"
        case .tasks:       return "checklist"
        case .finances:    return "creditcard.fill"
        case .analytics:   return "chart.bar.xaxis"
        case .inventory:   return "shippingbox.fill"
        case .documents:   return "doc.text.fill"
        case .contractors: return "wrench.and.screwdriver.fill"
        case .utilities:   return "bolt.fill"
        case .family:      return "person.2.fill"
        case .blueprints:  return "cube.transparent.fill"
        }
    }

    /// Pages that historically already had a floating button stay visible by
    /// default; every other page starts hidden so nothing is added unexpectedly.
    var defaultVisible: Bool {
        switch self {
        case .home, .finances, .inventory: return true
        default: return false
        }
    }

    var defaultActionsRaw: String {
        switch self {
        case .home:      return "aria,newTask,chat,scan"
        case .finances:  return "addExpense"
        case .inventory: return "scan,addItem"
        case .tasks:     return "newTask,aria"
        default:         return "newTask,chat,aria"
        }
    }
}
