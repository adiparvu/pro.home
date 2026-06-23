import Foundation
import ObjectiveC

// MARK: - LanguageManager
// Uses class-level method swizzle (method_exchangeImplementations) so the override
// affects all Bundle.main lookups regardless of how the instance was created.

enum LanguageManager {
    static var currentBundle: Bundle? { _currentBundle }
    private(set) static var _currentBundle: Bundle? = nil
    private static var _isSwizzled = false

    static func apply(_ code: String) {
        let shortCode = String(code.prefix(2))
        _currentBundle = findLprojBundle(code) ?? findLprojBundle(shortCode)
        ensureSwizzled()
    }

    // Locates and returns a Bundle for the given language code's .lproj directory.
    // Tries the Bundle resource index first; falls back to URL construction so it
    // works even when XcodeGen generated the project with folder references instead
    // of proper localization variant groups.
    private static func findLprojBundle(_ code: String) -> Bundle? {
        // Path via Bundle's resource index (standard way)
        if let p = Bundle.main.path(forResource: code, ofType: "lproj"),
           let b = Bundle(path: p),
           b.path(forResource: "Localizable", ofType: "strings") != nil {
            return b
        }
        // Direct URL construction — works when lproj dirs are folder references
        let url = Bundle.main.bundleURL.appendingPathComponent("\(code).lproj")
        if let b = Bundle(url: url),
           b.path(forResource: "Localizable", ofType: "strings") != nil {
            return b
        }
        return nil
    }

    /// Apply the best matching supported language from the device's preferred language list.
    /// Call this when followSystemLanguage = true so the swizzle infrastructure is always active.
    static func applySystemLanguage() {
        let supported = ["en", "ro", "fr", "nl", "de"]
        let code = Locale.preferredLanguages
            .compactMap { tag -> String? in
                let c = String(tag.prefix(2))
                return supported.contains(c) ? c : nil
            }
            .first ?? "en"
        apply(code)
    }

    static func reset() {
        _currentBundle = nil
        ensureSwizzled()
    }

    private static func ensureSwizzled() {
        guard !_isSwizzled else { return }
        let original = NSSelectorFromString("localizedStringForKey:value:table:")
        let swizzled = NSSelectorFromString("prvio_localizedStringForKey:value:table:")
        guard let orig = class_getInstanceMethod(Bundle.self, original),
              let swiz = class_getInstanceMethod(Bundle.self, swizzled) else { return }
        method_exchangeImplementations(orig, swiz)
        _isSwizzled = true
    }
}

extension Bundle {
    @objc(prvio_localizedStringForKey:value:table:)
    func prvio_localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        // After swizzle: calling self.prvio_localizedString actually calls the original IMP.
        guard self === Bundle.main, let override = LanguageManager._currentBundle else {
            return prvio_localizedString(forKey: key, value: value, table: tableName)
        }
        let result = override.prvio_localizedString(forKey: key, value: value, table: tableName)
        // Fall back to main bundle if key not found in override.
        // A missing key causes the system to return either the key itself or the `value`
        // parameter (when non-nil/non-empty), so we treat both as "not found".
        let notFound = result == key || (!result.isEmpty && result == (value ?? ""))
        if notFound {
            let fallback = prvio_localizedString(forKey: key, value: value, table: tableName)
#if DEBUG
            // Warn if the key is unresolved in both the override bundle and the fallback bundle.
            if fallback == key || (!fallback.isEmpty && fallback == (value ?? "")) {
                print("[LanguageManager] ⚠️ Missing localization key '\(key)' in override bundle and fallback bundle (table: \(tableName ?? "Localizable"))")
            }
#endif
            return fallback
        }
        return result
    }
}
