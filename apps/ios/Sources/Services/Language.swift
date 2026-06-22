import Foundation
import SwiftUI

// MARK: - Language enum — single source of truth for supported locales

enum Language: String, CaseIterable, Identifiable, Codable {
    case english  = "en"
    case romanian = "ro"
    case french   = "fr"
    case dutch    = "nl"
    case german   = "de"

    var id: String { rawValue }

    /// Native spelling of the language name
    var nativeName: String {
        switch self {
        case .english:  return "English"
        case .romanian: return "Română"
        case .french:   return "Français"
        case .dutch:    return "Nederlands"
        case .german:   return "Deutsch"
        }
    }

    /// Localized name of the language (translated into the current app language)
    var localizedName: String {
        switch self {
        case .english:  return String(localized: "lang_english")
        case .romanian: return String(localized: "lang_romanian")
        case .french:   return String(localized: "lang_french")
        case .dutch:    return String(localized: "lang_dutch")
        case .german:   return String(localized: "lang_german")
        }
    }

    var flag: String {
        switch self {
        case .english:  return "🇬🇧"
        case .romanian: return "🇷🇴"
        case .french:   return "🇫🇷"
        case .dutch:    return "🇳🇱"
        case .german:   return "🇩🇪"
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
