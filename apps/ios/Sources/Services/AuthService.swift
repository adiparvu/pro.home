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
        await syncRealtimeAuth(session)
        isLoading = false
    }

    /// Keeps the realtime socket's token in lock-step with the session for
    /// EVERY channel (chat, notifications, tasks, presence, …). The SDK only
    /// forwards the token to realtime when it CHANGES, so a socket that
    /// connected before the session settled — or that missed a refresh — keeps
    /// joining channels with a stale token. The server then rejects each join
    /// with `JwtSignatureError`, and the ~dozen channels retry to exhaustion,
    /// flooding realtime into `client_rate_limit_exceeded` — which is exactly
    /// what the server logs showed while chat realtime was dead. Pushing the
    /// current token on every auth event guarantees all joins authenticate.
    private func syncRealtimeAuth(_ session: Session?) async {
        await supabase.realtimeV2.setAuth(session?.accessToken)
    }

    private func listenToAuthChanges() async {
        for await (event, session) in supabase.auth.authStateChanges {
            switch event {
            case .initialSession, .signedIn, .userUpdated:
                self.session = session
                await syncRealtimeAuth(session)
            case .tokenRefreshed:
                self.session = session
                await syncRealtimeAuth(session)
                if let s = session {
                    AccountsStore.shared.updateTokens(
                        userId: s.user.id.uuidString,
                        accessToken: s.accessToken,
                        refreshToken: s.refreshToken
                    )
                }
            case .signedOut, .passwordRecovery, .userDeleted:
                self.session = nil
                await syncRealtimeAuth(nil)
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
        // Unbind this device from the leaving account BEFORE the session dies
        // (RLS only lets an account delete its own binding). Other accounts
        // signed into this phone keep their bindings — and their pushes.
        await PushTokenService.unbindCurrentAccount()
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
        // Logout bypasses reloadWorld (session is now nil), so the watch would
        // keep its last owner payload forever — wipe the App Group glance data
        // and tell the wrist to clear its own cache.
        SharedDataStore.clearWatchData()
        WatchSyncService.shared.pushCleared()
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
        // Wipe the wrist immediately; reloadWorld(.accountSwitch) then re-pushes
        // the new account's role-scoped payload, so the watch never briefly
        // shows the previous account's glance data.
        SharedDataStore.clearWatchData()
        WatchSyncService.shared.pushCleared()
        // Bind this device to the account we just became — bindings are per
        // (token, user), so the previous account keeps receiving its pushes too.
        await PushTokenService.bindCurrentAccount()
    }
}
