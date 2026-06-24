import Foundation
import ObjectiveC

// MARK: - LanguageManager
// Uses class-level method swizzle (method_exchangeImplementations) so the override
// affects all Bundle.main lookups regardless of how the instance was created.
// Strings are loaded directly via PropertyListSerialization into a plain dictionary
// to avoid the Bundle(url: lprojDir) resource-index issue with .lproj folder references.

enum LanguageManager {
    static var currentBundle: Bundle? { _strings != nil ? Bundle.main : nil }
    private(set) static var _strings: [String: String]? = nil
    private static var _isSwizzled = false

    static func apply(_ code: String) {
        let shortCode = String(code.prefix(2))
        _strings = loadStrings(code: code) ?? loadStrings(code: shortCode)
        ensureSwizzled()
    }

    // Loads Localizable.strings for the given language code directly from the app bundle.
    // Two strategies: Bundle resource index (proper variant groups) and direct URL
    // construction (Fastfile belt-and-suspenders copies).
    private static func loadStrings(code: String) -> [String: String]? {
        // Strategy 1: Bundle resource index with lproj subdirectory
        if let path = Bundle.main.path(forResource: "Localizable", ofType: "strings",
                                       inDirectory: "\(code).lproj"),
           let dict = readStringsFile(at: path) {
            return dict
        }
        // Strategy 2: Direct URL under app bundle
        let url = Bundle.main.bundleURL
            .appendingPathComponent("\(code).lproj")
            .appendingPathComponent("Localizable.strings")
        return readStringsFile(at: url.path)
    }

    private static func readStringsFile(at path: String) -> [String: String]? {
        guard FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        // PropertyListSerialization handles both binary plist and text .strings formats.
        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
           let dict = plist as? [String: String],
           !dict.isEmpty {
            return dict
        }
        // Fallback: NSDictionary for old-style OpenStep text plist
        return NSDictionary(contentsOfFile: path) as? [String: String]
    }

    /// Apply the best matching supported language from the device's preferred language list.
    static func applySystemLanguage() {
        let supported = ["en", "ro", "fr", "nl"]
        let code = Locale.preferredLanguages
            .compactMap { tag -> String? in
                let c = String(tag.prefix(2))
                return supported.contains(c) ? c : nil
            }
            .first ?? "en"
        apply(code)
    }

    static func reset() {
        _strings = nil
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
        guard self === Bundle.main, let strings = LanguageManager._strings else {
            return prvio_localizedString(forKey: key, value: value, table: tableName)
        }
        if let result = strings[key] {
            // A missing key causes the system to return either the key itself or the `value`
            // parameter (when non-nil/non-empty), so we treat both as "not found".
            let notFound = result == key || (!result.isEmpty && result == (value ?? ""))
            if !notFound { return result }
        }
        let fallback = prvio_localizedString(forKey: key, value: value, table: tableName)
#if DEBUG
        if fallback == key || (!fallback.isEmpty && fallback == (value ?? "")) {
            print("[LanguageManager] ⚠️ Missing key '\(key)' in override dict and fallback bundle (table: \(tableName ?? "Localizable"))")
        }
#endif
        return fallback
    }
}
