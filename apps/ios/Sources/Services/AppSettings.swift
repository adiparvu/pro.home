import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("prvio.theme")              var theme:                 String = "dark"
    @AppStorage("prvio.locale")             var locale:                String = "ro"
    @AppStorage("prvio.followSystemLang")   var followSystemLanguage:  Bool   = true
    @AppStorage("prvio.currency")           var preferredCurrency:     String = "EUR"
    @AppStorage("prvio.accentColor")        var accentColor:           String = "blue"
    @AppStorage("prvio.accentOn")           var accentEnabled:         Bool   = true
    @AppStorage("prvio.hapticOn")           var hapticEnabled:         Bool   = true
    @AppStorage("prvio.voiceInput")         var voiceInputEnabled:     Bool   = true

    init() {
        // Restore language on every launch so the bundle swizzle is always active.
        // Use object(forKey:) so a missing key → true (follow system), not false.
        let savedLocale = UserDefaults.standard.string(forKey: "prvio.locale") ?? "en"
        let followSystem = (UserDefaults.standard.object(forKey: "prvio.followSystemLang") as? Bool) ?? true
        if followSystem {
            LanguageManager.applySystemLanguage()
        } else {
            LanguageManager.apply(savedLocale)
        }
    }

    var appLocale: Locale {
        followSystemLanguage ? .autoupdatingCurrent : Locale(identifier: locale)
    }

    var currentLanguage: Language {
        if followSystemLanguage { return Language.devicePreferred }
        return Language(rawValue: locale) ?? Language.devicePreferred
    }

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

    /// Supported languages — derived from the Language enum, which is
    /// the single source of truth for what lproj bundles are shipped.
    static var languages: [(code: String, name: String, flag: String)] {
        Language.allCases.map { ($0.rawValue, $0.nativeName, $0.flag) }
    }
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
    case addSupply
    case waterPlant

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aria:       return "ARIA"
        case .newTask:    return String(localized: "New Task")
        case .chat:       return String(localized: "Family Chat")
        case .scan:       return String(localized: "Scan")
        case .addItem:    return String(localized: "Add Object")
        case .addExpense: return String(localized: "New Transaction")
        case .finances:   return String(localized: "Finances")
        case .addSupply:  return String(localized: "New Item")
        case .waterPlant: return String(localized: "Water Plants")
        }
    }

    var subtitle: String {
        switch self {
        case .aria:       return String(localized: "AI Assistant")
        case .newTask:    return String(localized: "Add a task")
        case .chat:       return String(localized: "Family messages")
        case .scan:       return String(localized: "Scan a QR code")
        case .addItem:    return String(localized: "Add to inventory")
        case .addExpense: return String(localized: "Income or expense")
        case .finances:   return String(localized: "Open finances")
        case .addSupply:  return String(localized: "Add to supplies")
        case .waterPlant: return String(localized: "Mark as watered")
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
        case .addSupply:  return "cart.badge.plus"
        case .waterPlant: return "drop.fill"
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
        case .addSupply:  return Color(red: 0.35, green: 0.65, blue: 1.0)
        case .waterPlant: return Color(red: 0.15, green: 0.80, blue: 0.40)
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
    case supplies
    case plants

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:        return String(localized: "Home")
        case .tasks:       return String(localized: "Tasks")
        case .finances:    return String(localized: "Finances")
        case .analytics:   return String(localized: "Analytics")
        case .inventory:   return String(localized: "Inventory")
        case .documents:   return String(localized: "Documents")
        case .contractors: return String(localized: "Contractors")
        case .utilities:   return String(localized: "Utilities")
        case .family:      return String(localized: "Family")
        case .blueprints:  return String(localized: "Blueprints")
        case .supplies:    return String(localized: "Supplies")
        case .plants:      return String(localized: "Plants")
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
        case .supplies:    return "cart.fill"
        case .plants:      return "leaf.fill"
        }
    }

    /// Pages that historically already had a floating button stay visible by
    /// default; every other page starts hidden so nothing is added unexpectedly.
    var defaultVisible: Bool {
        switch self {
        case .home, .finances, .inventory, .plants: return true
        default: return false
        }
    }

    var defaultActionsRaw: String {
        switch self {
        case .home:      return "aria,newTask,chat,scan"
        case .finances:  return "addExpense"
        case .inventory: return "scan,addItem"
        case .tasks:     return "newTask,aria"
        case .supplies:  return "addSupply"
        case .plants:    return "waterPlant"
        default:         return "newTask,chat,aria"
        }
    }
}
