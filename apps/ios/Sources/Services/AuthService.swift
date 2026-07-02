import Foundation
import Observation
import Supabase
import Combine

@MainActor
@Observable
final class AuthService {
    static let shared = AuthService()

    var session: Session?
    var isLoading = true

    private var sessionTask: Task<Void, Never>?
    private var authChangesTask: Task<Void, Never>?

    private init() {
        sessionTask     = Task { await loadSession() }
        authChangesTask = Task { await listenToAuthChanges() }
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
        for await (event, session) in supabase.auth.authStateChanges {
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
        AuditLogService.AuditEvent.record("login", String(localized: "Signed in with email"))
    }

    /// Complete sign-in from a magic-link / invite deep link (`prvio://…`).
    /// Supabase auth callbacks carry tokens in the URL fragment (implicit flow)
    /// or a `?code=` (PKCE); everything else is an ordinary deep link and is
    /// left for the router. Returns true when the URL was an auth callback we
    /// consumed.
    func handleOpenURL(_ url: URL) async -> Bool {
        let s = url.absoluteString
        let looksLikeAuth = s.contains("access_token")
            || s.contains("refresh_token")
            || s.contains("code=")
            || s.contains("error_description")
            || (url.fragment?.contains("access_token") ?? false)
        guard looksLikeAuth else { return false }
        do {
            self.session = try await supabase.auth.session(from: url)
            AuditLogService.AuditEvent.record("login", String(localized: "Signed in via link"))
            return true
        } catch {
            return false
        }
    }

    func signOut() async throws {
        AuditLogService.AuditEvent.record("logout", String(localized: "Signed out"))
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
