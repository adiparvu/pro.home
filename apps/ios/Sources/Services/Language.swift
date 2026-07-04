import Foundation
import SwiftUI

// MARK: - Language enum — single source of truth for supported locales

// PRVIO ships in Romanian (its native/development language) and English only.
// The list is deliberately short so the picker stays a two-item choice; adding a
// language later means adding a case here plus its .lproj strings — nothing else.
enum Language: String, CaseIterable, Identifiable, Codable {
    case english  = "en"
    case romanian = "ro"

    var id: String { rawValue }

    /// Native spelling of the language name
    var nativeName: String {
        switch self {
        case .english:  return "English"
        case .romanian: return "Română"
        }
    }

    /// Localized name of the language (translated into the current app language).
    /// Uses `String(localized:)` which resolves via the bundle swizzle when a custom
    /// language is active. Use this in SwiftUI `Text` views: `Text(lang.localizedName)`.
    var localizedName: String {
        switch self {
        case .english:  return String(localized: "lang_english")
        case .romanian: return String(localized: "lang_romanian")
        }
    }

    /// `LocalizedStringKey` form — bypasses the bundle swizzle; prefer `localizedName` in views
    /// that use `LanguageManager`-based dynamic switching.
    var localizedNameKey: LocalizedStringKey {
        switch self {
        case .english:  return "lang_english"
        case .romanian: return "lang_romanian"
        }
    }

    var flag: String {
        switch self {
        case .english:  return "🇬🇧"
        case .romanian: return "🇷🇴"
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

    /// Best-match a language from any BCP 47 code string (e.g. "ro-RO" → .romanian)
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
