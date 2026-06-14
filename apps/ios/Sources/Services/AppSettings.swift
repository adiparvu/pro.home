import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("prvio.theme")       var theme:             String = "dark"
    @AppStorage("prvio.locale")      var locale:            String = "en"
    @AppStorage("prvio.currency")    var preferredCurrency: String = "EUR"
    @AppStorage("prvio.accentColor") var accentColor:       String = "blue"
    @AppStorage("prvio.hapticOn")    var hapticEnabled:     Bool   = true

    // Customizable home floating-button quick actions (ordered, comma-separated rawValues)
    @AppStorage("prvio.quickActions") var quickActionsRaw:  String = "aria,newTask,chat,scan"

    var quickActions: [DashboardQuickAction] {
        let parsed = quickActionsRaw
            .split(separator: ",")
            .compactMap { DashboardQuickAction(rawValue: String($0)) }
        return parsed.isEmpty ? [] : parsed
    }

    func isQuickActionEnabled(_ action: DashboardQuickAction) -> Bool {
        quickActions.contains(action)
    }

    func setQuickAction(_ action: DashboardQuickAction, enabled: Bool) {
        var current = quickActions
        if enabled {
            if !current.contains(action) { current.append(action) }
        } else {
            current.removeAll { $0 == action }
        }
        // Persist in canonical order so the FAB layout stays predictable.
        let ordered = DashboardQuickAction.allCases.filter { current.contains($0) }
        // @AppStorage inside an ObservableObject does not auto-publish, so notify
        // observers (home FAB, settings toggles) explicitly.
        objectWillChange.send()
        quickActionsRaw = ordered.map(\.rawValue).joined(separator: ",")
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
    case addExpense
    case finances

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aria:       return "ARIA"
        case .newTask:    return "Sarcină nouă"
        case .chat:       return "Chat familie"
        case .scan:       return "Scanare"
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
        case .addExpense: return Color(red: 0.2,  green: 0.78, blue: 0.6)
        case .finances:   return Color(red: 0.55, green: 0.55, blue: 0.95)
        }
    }
}
