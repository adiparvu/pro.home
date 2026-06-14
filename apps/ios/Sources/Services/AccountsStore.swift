import Foundation
import Security
import Supabase

struct SavedAccount: Codable, Identifiable, Equatable {
    var id: String { userId }
    let userId: String
    let email: String
    var displayName: String?
    var avatarUrl: String?
    var accessToken: String
    var refreshToken: String

    var initial: String {
        let name = displayName ?? email
        return String(name.prefix(1)).uppercased()
    }
}

@MainActor
final class AccountsStore: ObservableObject {
    static let shared = AccountsStore()

    @Published private(set) var accounts: [SavedAccount] = []

    private let keychainKey = "prvio.saved.accounts"
    private let keychainService = "com.prvio.app"

    private init() {
        accounts = loadFromKeychain()
    }

    func save(session: Session, displayName: String?, avatarUrl: String?) {
        let userId = session.user.id.uuidString
        let account = SavedAccount(
            userId: userId,
            email: session.user.email ?? "",
            displayName: displayName,
            avatarUrl: avatarUrl,
            accessToken: session.accessToken,
            refreshToken: session.refreshToken
        )
        if let idx = accounts.firstIndex(where: { $0.userId == userId }) {
            accounts[idx] = account
        } else {
            accounts.append(account)
        }
        saveToKeychain()
    }

    func updateProfile(userId: String, displayName: String?, avatarUrl: String?) {
        guard let idx = accounts.firstIndex(where: { $0.userId == userId }) else { return }
        accounts[idx].displayName = displayName
        accounts[idx].avatarUrl = avatarUrl
        saveToKeychain()
    }

    func updateTokens(userId: String, accessToken: String, refreshToken: String) {
        guard let idx = accounts.firstIndex(where: { $0.userId == userId }) else { return }
        accounts[idx].accessToken = accessToken
        accounts[idx].refreshToken = refreshToken
        saveToKeychain()
    }

    func remove(userId: String) {
        accounts.removeAll { $0.userId == userId }
        saveToKeychain()
    }

    // MARK: - Keychain

    private func loadFromKeychain() -> [SavedAccount] {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainKey,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let decoded = try? JSONDecoder().decode([SavedAccount].self, from: data)
        else { return [] }
        return decoded
    }

    private func saveToKeychain() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainKey
        ]
        let attributes: [CFString: Any] = [kSecValueData: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }
}
