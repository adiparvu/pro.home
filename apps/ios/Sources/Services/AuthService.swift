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

    /// Invited accounts are created with `needs_password: true` in their user
    /// metadata (send-invite-email). Until they set one, the app forces the
    /// strong-password screen — an invite link alone must not become a
    /// passwordless account someone else could reuse later.
    var needsPasswordSetup: Bool {
        guard let meta = session?.user.userMetadata else { return false }
        if case .bool(true) = meta["needs_password"] { return true }
        return false
    }

    func completePasswordSetup(password: String) async throws {
        let user = try await supabase.auth.update(user: UserAttributes(
            password: password,
            data: ["needs_password": .bool(false)]
        ))
        // authStateChanges emits .userUpdated too; set directly so the cover
        // dismisses without waiting on the stream.
        if var s = session {
            s.user = user
            session = s
        }
        AuditLogService.AuditEvent.record("security", String(localized: "Password set for invited account"))
    }

    func signOut() async throws {
        AuditLogService.AuditEvent.record("logout", String(localized: "Signed out"))
        let signedOutUserId = session?.user.id.uuidString
        try await supabase.auth.signOut()
        session = nil
        // Signing out of an account removes it from the quick-switch list — a
        // logged-out account must not linger in the Accounts sheet. (Switching
        // accounts goes through switchTo/setSession, not signOut, so this only
        // fires on an explicit logout.)
        if let signedOutUserId { AccountsStore.shared.remove(userId: signedOutUserId) }
        // The next account must never see this household's cached data.
        ServiceCache.clear()
        SignedStorage.clearCache()
    }

    func switchTo(account: SavedAccount) async throws {
        let restored = try await supabase.auth.setSession(
            accessToken: account.accessToken,
            refreshToken: account.refreshToken
        )
        self.session = restored
        // Account switch = different household visibility; drop the old cache.
        ServiceCache.clear()
        SignedStorage.clearCache()
    }
}
