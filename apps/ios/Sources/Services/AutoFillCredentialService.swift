import Foundation
import AuthenticationServices

// MARK: - AutoFill Credential Service
// Stores smart home / property credentials that iOS AutoFill can suggest
// in Safari and other apps (router admin, camera IP, solar app, etc.)

@MainActor
final class AutoFillCredentialService: ObservableObject {
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

    @Published var credentials: [PropertyCredential] = []

    private let storageKey = "prvio.autofill.credentials"

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

    // Saves to Keychain via UserDefaults (in production: use SecItemAdd)
    private func save() {
        if let data = try? JSONEncoder().encode(credentials) {
            UserDefaults(suiteName: "group.com.prvio.app")?.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults(suiteName: "group.com.prvio.app")?.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([PropertyCredential].self, from: data)
        else { return }
        credentials = saved
    }
}
