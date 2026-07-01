import Foundation
import Observation
import CryptoKit
import LocalAuthentication
import Security

// Encrypts/decrypts locked element notes and gates their viewing behind
// Face ID / Touch ID (LAContext) or a user-set PIN fallback.
//
// Security model:
//   • Note bodies marked "locked" are encrypted with a 256-bit AES-GCM key
//     stored in the Keychain (device-only). This keeps locked notes unreadable
//     in Supabase / for other property members.
//   • Viewing a locked note requires an in-app unlock: Face ID (primary) or the
//     custom PIN (fallback). `isUnlocked` lasts for the session until `lock()`.
//   (A biometric-bound key is a future hardening step.)

@MainActor
@Observable
final class NoteLockManager {
    static let shared = NoteLockManager()

    private(set) var isUnlocked = false

    private let service = "com.prvio.notes"
    private let keyAccount = "masterkey"
    private let pinAccount = "pin"   // stored as "salt:hash"

    private var cachedKey: SymmetricKey?

    var hasPIN: Bool { loadKeychain(account: pinAccount) != nil }

    var biometryAvailable: Bool {
        var err: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
    }

    // MARK: - Master key

    private func masterKey() -> SymmetricKey {
        if let k = cachedKey { return k }
        if let data = loadKeychain(account: keyAccount) {
            let k = SymmetricKey(data: data); cachedKey = k; return k
        }
        let k = SymmetricKey(size: .bits256)
        let data = k.withUnsafeBytes { Data($0) }
        saveKeychain(account: keyAccount, data: data)
        cachedKey = k
        return k
    }

    // MARK: - Encrypt / decrypt

    func encrypt(_ text: String) -> String? {
        guard let plain = text.data(using: .utf8),
              let sealed = try? AES.GCM.seal(plain, using: masterKey()),
              let combined = sealed.combined else { return nil }
        return combined.base64EncodedString()
    }

    func decrypt(_ b64: String) -> String? {
        guard let data = Data(base64Encoded: b64),
              let box = try? AES.GCM.SealedBox(combined: data),
              let opened = try? AES.GCM.open(box, using: masterKey()) else { return nil }
        return String(data: opened, encoding: .utf8)
    }

    // MARK: - Unlock

    func unlockBiometric() async -> Bool {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else { return false }
        do {
            let ok = try await ctx.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: String(localized: "Unlock your locked notes")
            )
            if ok { isUnlocked = true }
            return ok
        } catch {
            return false
        }
    }

    func verifyPIN(_ pin: String) -> Bool {
        guard let data = loadKeychain(account: pinAccount),
              let stored = String(data: data, encoding: .utf8) else { return false }
        let parts = stored.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }
        let ok = Self.hash(pin: pin, salt: parts[0]) == parts[1]
        if ok { isUnlocked = true }
        return ok
    }

    func setPIN(_ pin: String) {
        let salt = UUID().uuidString
        let hash = Self.hash(pin: pin, salt: salt)
        saveKeychain(account: pinAccount, data: Data("\(salt):\(hash)".utf8))
        _ = masterKey() // ensure key exists
    }

    func lock() { isUnlocked = false }

    private static func hash(pin: String, salt: String) -> String {
        SHA256.hash(data: Data((pin + salt).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Keychain

    private func saveKeychain(account: String, data: Data) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    private func loadKeychain(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }
}
