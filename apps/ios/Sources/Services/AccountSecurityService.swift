import Foundation
import Observation
import CryptoKit
import Supabase

// MARK: - AccountSecurityService — the account's security authority
//
// One service owns everything the Security page promises about the ACCOUNT
// (as opposed to the local app lock, which stays in AppLockManager):
//
//   • The sign-in MFA gate: when the account has a verified TOTP factor,
//     the session signs in at AAL1 and PRVIO refuses to show the app until
//     the user passes the 6-digit challenge (or spends a backup code). The
//     gate is enforced at the app level — the honest statement of what it
//     does, mirrored in the UI copy.
//   • Backup codes: generated on demand, stored ONLY as SHA-256 hashes in
//     the `backup_codes` table, each spendable exactly once at the gate.
//     They are NOT password recovery — copy must never claim that.
//   • The server-side security journal (`account_security_events`): real
//     events only, readable from any of the user's devices.

struct AccountSecurityEvent: Codable, Identifiable {
    let id: UUID
    let type: String
    let payload: [String: String]?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, type, payload
        case createdAt = "created_at"
    }
}

@MainActor
@Observable
final class AccountSecurityService {
    static let shared = AccountSecurityService()
    private init() {}

    /// True while the session is AAL1 but the account can reach AAL2 —
    /// i.e. a verified TOTP factor exists and hasn't been challenged yet.
    /// PRVIOApp covers the whole UI with MFAChallengeView while this holds.
    private(set) var needsMFAChallenge = false

    /// Set after a backup code unlocked the gate — the Security page uses it
    /// to suggest re-enrolling the authenticator the user evidently lost.
    private(set) var unlockedWithBackupCode = false

    /// Unused backup codes on the account (nil until first load).
    private(set) var unusedBackupCodes: Int?

    private(set) var recentEvents: [AccountSecurityEvent] = []

    // MARK: - MFA gate

    /// Re-derives the gate from the real assurance level. Called on every
    /// session change; on any error the gate FAILS OPEN (a network hiccup
    /// must not brick the app — the server still holds its own guarantees).
    func refreshMFAStatus() async {
        guard supabase.auth.currentSession != nil else {
            needsMFAChallenge = false
            return
        }
        do {
            let aal = try await supabase.auth.mfa.getAuthenticatorAssuranceLevel()
            needsMFAChallenge = aal.currentLevel != aal.nextLevel && aal.nextLevel == "aal2"
        } catch {
            needsMFAChallenge = false
        }
    }

    /// Challenges the account's verified TOTP factor with a 6-digit code.
    func verifyTOTP(code: String) async -> Bool {
        do {
            let factors = try await supabase.auth.mfa.listFactors()
            guard let factor = factors.totp.first else { return false }
            try await supabase.auth.mfa.challengeAndVerify(
                params: MFAChallengeAndVerifyParams(factorId: factor.id, code: code)
            )
            needsMFAChallenge = false
            return true
        } catch {
            return false
        }
    }

    // MARK: - Backup codes

    static func hash(_ code: String) -> String {
        let normalized = code.uppercased().replacingOccurrences(of: " ", with: "")
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Spends one unused backup code at the gate. The UPDATE is conditional
    /// on `used_at IS NULL` and returns the touched rows, so two devices
    /// racing the same code can never both succeed.
    func verifyBackupCode(_ code: String) async -> Bool {
        guard let userId = supabase.auth.currentSession?.user.id else { return false }
        struct Spent: Codable { let id: UUID }
        do {
            let spent: [Spent] = try await supabase.from("backup_codes")
                .update(["used_at": ISODate.string(from: Date())])
                .eq("user_id", value: userId.uuidString)
                .eq("code_hash", value: Self.hash(code))
                .is("used_at", value: nil)
                .select("id")
                .execute().value
            guard !spent.isEmpty else { return false }
            // The gate opens app-level; the session itself stays AAL1 —
            // which is exactly what the backup-code copy promises.
            needsMFAChallenge = false
            unlockedWithBackupCode = true
            await recordEvent("backup_code_used")
            await refreshBackupCodeCount()
            return true
        } catch {
            return false
        }
    }

    /// Replaces the account's backup codes with a fresh set and returns the
    /// PLAIN codes — shown exactly once; only hashes ever leave the device.
    func regenerateBackupCodes() async throws -> [String] {
        guard let userId = supabase.auth.currentSession?.user.id else { return [] }
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let codes = (0..<8).map { _ in
            let part = { String((0..<5).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] }) }
            return "\(part())-\(part())"
        }
        struct CodeInsert: Codable {
            let user_id: String
            let code_hash: String
        }
        _ = try await supabase.from("backup_codes")
            .delete()
            .eq("user_id", value: userId.uuidString)
            .execute()
        _ = try await supabase.from("backup_codes")
            .insert(codes.map { CodeInsert(user_id: userId.uuidString, code_hash: Self.hash($0)) })
            .execute()
        unusedBackupCodes = codes.count
        await recordEvent("backup_codes_generated")
        return codes
    }

    func refreshBackupCodeCount() async {
        guard let userId = supabase.auth.currentSession?.user.id else { return }
        struct Row: Codable { let id: UUID }
        do {
            let rows: [Row] = try await supabase.from("backup_codes")
                .select("id")
                .eq("user_id", value: userId.uuidString)
                .is("used_at", value: nil)
                .execute().value
            unusedBackupCodes = rows.count
        } catch { /* count stays unknown — the UI shows nothing false */ }
    }

    // MARK: - Server-side security journal

    func recordEvent(_ type: String, payload: [String: String] = [:]) async {
        guard let userId = supabase.auth.currentSession?.user.id else { return }
        struct EventInsert: Codable {
            let user_id: String
            let type: String
            let payload: [String: String]
        }
        _ = try? await supabase.from("account_security_events")
            .insert(EventInsert(user_id: userId.uuidString, type: type, payload: payload))
            .execute()
    }

    func loadRecentEvents(limit: Int = 30) async {
        guard let userId = supabase.auth.currentSession?.user.id else { return }
        do {
            recentEvents = try await supabase.from("account_security_events")
                .select("id, type, payload, created_at")
                .eq("user_id", value: userId.uuidString)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute().value
        } catch { /* journal is glanceable — next open retries */ }
    }
}
