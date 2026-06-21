import Foundation
import Supabase
import Combine

@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var session: Session?
    @Published var isLoading = true

    private init() {
        Task { await loadSession() }
        Task { await listenToAuthChanges() }
    }

    private func loadSession() async {
        do {
            session = try await supabase.auth.session
        } catch {
            session = nil
        }
        isLoading = false
    }

    private func listenToAuthChanges() async {
        for await (event, session) in await supabase.auth.authStateChanges {
            switch event {
            case .initialSession, .signedIn, .userUpdated:
                self.session = session
            case .tokenRefreshed:
                self.session = session
                if let s = session {
                    AccountsStore.shared.updateTokens(
                        userId: s.user.id.uuidString,
                        accessToken: s.accessToken,
                        refreshToken: s.refreshToken
                    )
                }
            case .signedOut, .passwordRecovery, .userDeleted:
                self.session = nil
            default:
                break
            }
        }
    }

    func signIn(email: String, password: String) async throws {
        let session = try await supabase.auth.signIn(email: email, password: password)
        self.session = session
        AuditLogService.AuditEvent.record("login", "Signed in with email")
    }

    func signOut() async throws {
        AuditLogService.AuditEvent.record("logout", "Signed out")
        try await supabase.auth.signOut()
        session = nil
    }

    func switchTo(account: SavedAccount) async throws {
        let restored = try await supabase.auth.setSession(
            accessToken: account.accessToken,
            refreshToken: account.refreshToken
        )
        self.session = restored
    }
}
