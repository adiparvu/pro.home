import SwiftUI

// MARK: - AppLanguage environment key
// Allows any view to read the current Language without an EnvironmentObject.

private struct AppLanguageKey: EnvironmentKey {
    static let defaultValue: Language = Language.devicePreferred
}

extension EnvironmentValues {
    var appLanguage: Language {
        get { self[AppLanguageKey.self] }
        set { self[AppLanguageKey.self] = newValue }
    }
}

// MARK: - Preview helper

extension View {
    /// Wraps the view for SwiftUI Preview in a specific language.
    func previewLocalization(_ language: Language) -> some View {
        environment(\.locale, language.locale)
            .environment(\.appLanguage, language)
    }
}
