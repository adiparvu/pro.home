import Foundation
import Security

// MARK: - Keychain-backed storage for small user secrets
//
// UserDefaults is plaintext on disk and included in backups — a billable
// API key must never live there. Items are marked ThisDeviceOnly so they
// are excluded from backups and never migrate to another device.

enum SecretStore {
    private static let service = "com.prvio.app.secrets"

    static func string(for key: String) -> String {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return "" }
        return value
    }

    static func set(_ value: String, for key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        guard !value.isEmpty, let data = value.data(using: .utf8) else {
            SecItemDelete(query as CFDictionary)
            return
        }
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            addQuery[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }
}

// MARK: - Debug-only logging
//
// Services used to `print(...)` unconditionally, shipping error chatter in
// release builds. Route diagnostics through here instead — free in release.

@inline(__always)
func debugLog(_ items: Any...) {
    #if DEBUG
    print(items.map { "\($0)" }.joined(separator: " "))
    #endif
}
