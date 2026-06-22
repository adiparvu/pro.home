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
        let path = Bundle.main.path(forResource: code, ofType: "lproj")
                ?? Bundle.main.path(forResource: String(code.prefix(2)), ofType: "lproj")
        _currentBundle = path.flatMap { Bundle(path: $0) }
        ensureSwizzled()
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
        // Fall back to main bundle if key not found in override (returns key itself)
        if result == key {
            return prvio_localizedString(forKey: key, value: value, table: tableName)
        }
        return result
    }
}
