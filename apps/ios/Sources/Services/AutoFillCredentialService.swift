import Foundation
import Observation
import Security
import AuthenticationServices

// MARK: - AutoFill Credential Service
// Stores smart home / property credentials that iOS AutoFill can suggest
// in Safari and other apps (router admin, camera IP, solar app, etc.)

// MARK: - Keychain helper (credentials contain passwords — never UserDefaults)
private enum KeychainStore {
    static let service = "com.prvio.app.autofill"
    static let account = "credentials"

    static func save(_ data: Data) {
        let query: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrService as String:    service,
            kSecAttrAccount as String:    account,
            kSecValueData as String:      data,
            // Passwords stay on this device and out of backups.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> Data? {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      account,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
@Observable
final class AutoFillCredentialService {
    static let shared = AutoFillCredentialService()

    struct PropertyCredential: Identifiable, Codable {
        var id: UUID = UUID()
        var serviceURL: String
        var serviceName: String
        var username: String
        var note: String
        var category: Category

        enum Category: String, Codable, CaseIterable {
            case router, camera, solar, utility, smart, other

            var label: String {
                switch self {
                case .router:  return "Router / WiFi"
                case .camera:  return "Cameră securitate"
                case .solar:   return "Panou solar"
                case .utility: return "Cont furnizor utilități"
                case .smart:   return "Dispozitiv smart"
                case .other:   return "Altele"
                }
            }

            var icon: String {
                switch self {
                case .router:  return "wifi"
                case .camera:  return "video.fill"
                case .solar:   return "sun.max.fill"
                case .utility: return "bolt.fill"
                case .smart:   return "homekit"
                case .other:   return "key.fill"
                }
            }
        }
    }

    var credentials: [PropertyCredential] = []

    private init() { load() }

    func add(_ credential: PropertyCredential) {
        credentials.append(credential)
        save()
    }

    func delete(at offsets: IndexSet) {
        credentials.remove(atOffsets: offsets)
        save()
    }

    func update(_ credential: PropertyCredential) {
        if let idx = credentials.firstIndex(where: { $0.id == credential.id }) {
            credentials[idx] = credential
            save()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        KeychainStore.save(data)
    }

    private func load() {
        guard let data = KeychainStore.load(),
              let saved = try? JSONDecoder().decode([PropertyCredential].self, from: data)
        else { return }
        credentials = saved
    }
}
