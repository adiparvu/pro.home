import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("prvio.theme")       var theme:             String = "dark"
    @AppStorage("prvio.locale")      var locale:            String = "en"
    @AppStorage("prvio.currency")    var preferredCurrency: String = "EUR"
    @AppStorage("prvio.accentColor") var accentColor:       String = "blue"
    @AppStorage("prvio.hapticOn")    var hapticEnabled:     Bool   = true

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
