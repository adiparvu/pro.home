import Foundation
import ObjectiveC

// MARK: - Bundle Swizzle

private var _languageBundleKey: UInt8 = 0

private final class LanguageOverrideBundle: Bundle {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        guard let override = objc_getAssociatedObject(self, &_languageBundleKey) as? Bundle else {
            return super.localizedString(forKey: key, value: value, table: tableName)
        }
        return override.localizedString(forKey: key, value: value, table: tableName)
    }
}

// MARK: - LanguageManager

enum LanguageManager {
    /// Redirect all Bundle.main string lookups to the given language's .lproj bundle.
    static func apply(_ code: String) {
        let path = Bundle.main.path(forResource: code, ofType: "lproj")
                ?? Bundle.main.path(forResource: String(code.prefix(2)), ofType: "lproj")
        let langBundle: Bundle? = path.flatMap { Bundle(path: $0) }
        objc_setAssociatedObject(Bundle.main, &_languageBundleKey, langBundle, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        object_setClass(Bundle.main, LanguageOverrideBundle.self)
    }

    /// Remove the override — strings fall back to system language.
    static func reset() {
        objc_setAssociatedObject(Bundle.main, &_languageBundleKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        object_setClass(Bundle.main, LanguageOverrideBundle.self)
    }
}
