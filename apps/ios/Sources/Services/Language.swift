import Foundation
import SwiftUI

// MARK: - Language enum — single source of truth for supported locales

enum Language: String, CaseIterable, Identifiable, Codable {
    case english  = "en"
    case romanian = "ro"
    case french   = "fr"
    case dutch    = "nl"

    var id: String { rawValue }

    /// Native spelling of the language name
    var nativeName: String {
        switch self {
        case .english:  return "English"
        case .romanian: return "Română"
        case .french:   return "Français"
        case .dutch:    return "Nederlands"
        }
    }

    /// Localized name of the language (translated into the current app language).
    /// Uses `String(localized:)` which resolves via the bundle swizzle when a custom
    /// language is active. Use this in SwiftUI `Text` views: `Text(lang.localizedName)`.
    var localizedName: String {
        switch self {
        case .english:  return String(localized: "lang_english")
        case .romanian: return String(localized: "lang_romanian")
        case .french:   return String(localized: "lang_french")
        case .dutch:    return String(localized: "lang_dutch")
        }
    }

    /// `LocalizedStringKey` form — bypasses the bundle swizzle; prefer `localizedName` in views
    /// that use `LanguageManager`-based dynamic switching.
    var localizedNameKey: LocalizedStringKey {
        switch self {
        case .english:  return "lang_english"
        case .romanian: return "lang_romanian"
        case .french:   return "lang_french"
        case .dutch:    return "lang_dutch"
        }
    }

    var flag: String {
        switch self {
        case .english:  return "🇬🇧"
        case .romanian: return "🇷🇴"
        case .french:   return "🇫🇷"
        case .dutch:    return "🇳🇱"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }

    /// BCP 47 tag used in AI requests so the model responds in the right language
    var bcp47: String { rawValue }

    /// Instruction string to prepend (or include) in AI prompts
    var aiInstruction: String {
        "Please respond in \(nativeName) (language code: \(bcp47))."
    }

    // MARK: Matching helpers

    /// Best-match a language from any BCP 47 code string (e.g. "fr-CA" → .french)
    static func from(_ code: String?) -> Language? {
        guard let code else { return nil }
        let lower = code.lowercased()
        return allCases.first { lower == $0.rawValue }
            ?? allCases.first { lower.hasPrefix($0.rawValue) }
    }

    /// The device's preferred language, falling back to English if unsupported
    static var devicePreferred: Language {
        from(Locale.preferredLanguages.first) ?? .english
    }
}
