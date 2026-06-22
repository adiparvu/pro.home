import Foundation
import SwiftUI

// MARK: - LocalizationManager
// High-level wrapper around LanguageManager's bundle swizzle.
// Holds the current Language value and provides helpers for
// building locale-aware environments and AI prompt injections.

@MainActor
final class LocalizationManager: ObservableObject {

    static let shared = LocalizationManager()

    @Published private(set) var currentLanguage: Language

    private init() {
        let saved        = UserDefaults.standard.string(forKey: "prvio.locale")
        let followSystem = UserDefaults.standard.bool(forKey: "prvio.followSystemLang")
        if followSystem || saved == nil {
            currentLanguage = Language.devicePreferred
        } else {
            currentLanguage = Language(rawValue: saved ?? "en") ?? .english
        }
    }

    // MARK: Mutation

    func setLanguage(_ language: Language) {
        LanguageManager.apply(language.rawValue)
        currentLanguage = language
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
    }

    func resetToSystem() {
        LanguageManager.reset()
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        currentLanguage = Language.devicePreferred
    }

    // MARK: Helpers

    var locale: Locale { currentLanguage.locale }

    /// String to include in every AI request so the assistant replies in the user's language
    var aiLanguageContext: String { currentLanguage.aiInstruction }
}
