import Foundation
import ObjectiveC

// MARK: - LanguageManager
// Uses class-level method swizzle (method_exchangeImplementations) so the override
// affects all Bundle.main lookups regardless of how the instance was created.
// Strings are loaded directly via PropertyListSerialization into a plain dictionary
// to avoid the Bundle(url: lprojDir) resource-index issue with .lproj folder references.

enum LanguageManager {
    static var currentBundle: Bundle? { _strings != nil ? Bundle.main : nil }
    /// The locale every `String(localized:)` in the app resolves against (see
    /// the shim at the bottom of this file). Modern Foundation resolves
    /// `String(localized:)` in native Swift, bypassing the ObjC method the
    /// swizzle exchanges — so the override must ride the `locale:` parameter,
    /// which is part of the supported API, not the runtime.
    private(set) static var activeLocale: Locale = .autoupdatingCurrent
    private(set) static var _strings: [String: String]? = nil
    /// The chosen language's .lproj loaded as its own bundle — resolves through
    /// the real localization machinery, covering formats the manual .strings
    /// parser can't read (compiled catalogs, stringsdict plurals).
    private(set) static var bundleOverride: Bundle? = nil
    private static var _isSwizzled = false

    static func apply(_ code: String) {
        let shortCode = String(code.prefix(2))
        activeLocale = Locale(identifier: shortCode)
        _strings = loadStrings(code: code) ?? loadStrings(code: shortCode)
        bundleOverride = lprojBundle(code: code) ?? lprojBundle(code: shortCode)
        ensureSwizzled()
    }

    private static func lprojBundle(code: String) -> Bundle? {
        Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:))
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
        let supported = ["en", "ro"]
        let code = Locale.preferredLanguages
            .compactMap { tag -> String? in
                let c = String(tag.prefix(2))
                return supported.contains(c) ? c : nil
            }
            .first ?? "en"
        apply(code)
    }

    static func reset() {
        activeLocale = .autoupdatingCurrent
        _strings = nil
        bundleOverride = nil
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

// MARK: - The one localization shim
//
// Every unqualified `String(localized: "…")` in this module resolves through
// this initializer (same-module declarations win overload resolution against
// imported ones), which forwards to Foundation's full initializer with the
// app's chosen locale. This is what makes the in-app language switch actually
// bind: on iOS 17+ Foundation resolves `String(localized:)` in native Swift,
// so neither the bundle swizzle nor `AppleLanguages` help until relaunch —
// the `locale:` parameter is the supported, deterministic override.
extension String {
    init(localized keyAndValue: String.LocalizationValue, comment: StaticString? = nil) {
        self.init(localized: keyAndValue, table: nil, bundle: .main,
                  locale: LanguageManager.activeLocale, comment: comment)
    }
}

extension Bundle {
    @objc(prvio_localizedStringForKey:value:table:)
    func prvio_localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        // After swizzle: calling self.prvio_localizedString actually calls the original IMP.
        guard self === Bundle.main,
              LanguageManager._strings != nil || LanguageManager.bundleOverride != nil else {
            return prvio_localizedString(forKey: key, value: value, table: tableName)
        }
        if let result = LanguageManager._strings?[key] {
            // A missing key causes the system to return either the key itself or the `value`
            // parameter (when non-nil/non-empty), so we treat both as "not found".
            let notFound = result == key || (!result.isEmpty && result == (value ?? ""))
            if !notFound { return result }
        }
        // Second chance: the chosen language's lproj bundle through the ORIGINAL
        // implementation (the swizzle is class-wide, so prvio_ on another
        // instance is the pristine lookup) — handles compiled catalog formats.
        if let override = LanguageManager.bundleOverride, override !== self {
            let viaBundle = override.prvio_localizedString(forKey: key, value: value, table: tableName)
            let notFound = viaBundle == key || (!viaBundle.isEmpty && viaBundle == (value ?? ""))
            if !notFound { return viaBundle }
        }
        let fallback = prvio_localizedString(forKey: key, value: value, table: tableName)
#if DEBUG
        if fallback == key || (!fallback.isEmpty && fallback == (value ?? "")) {
            debugLog("[LanguageManager] ⚠️ Missing key '\(key)' in override dict and fallback bundle (table: \(tableName ?? "Localizable"))")
        }
#endif
        return fallback
    }
}
