import Foundation
import Supabase

// MARK: - Account data rights (export + erasure)
//
// The two account-level data operations the Security screen offers: a full
// JSON export of the household's business data, and the irreversible
// server-side account deletion. Both live here so no view talks to the
// database directly; the screen only owns presentation state (spinners,
// alerts, the share sheet).

enum AccountDeletionService {

    /// Assembles the pretty-printed JSON export (tasks, financial records,
    /// documents). Each table is fetched best-effort — a missing table
    /// degrades to an empty array instead of failing the whole export.
    /// Throws only when no session exists or the final JSON can't be built.
    static func exportJSON() async throws -> Data {
        let userId = try await supabase.auth.session.user.id
        let tasksData   = (try? await supabase.from("maintenance_tasks").select().execute().data)   ?? Data()
        let recordsData = (try? await supabase.from("financial_records").select().execute().data)   ?? Data()
        let docsData    = (try? await supabase.from("documents").select().execute().data)            ?? Data()
        let tasks     = (try? JSONSerialization.jsonObject(with: tasksData))   as? [[String: Any]] ?? []
        let records   = (try? JSONSerialization.jsonObject(with: recordsData)) as? [[String: Any]] ?? []
        let docs      = (try? JSONSerialization.jsonObject(with: docsData))    as? [[String: Any]] ?? []
        let export: [String: Any] = [
            "exported_at": ISO8601DateFormatter().string(from: Date()),
            "user_id": userId.uuidString,
            "tasks": tasks, "financial_records": records, "documents": docs
        ]
        return try JSONSerialization.data(withJSONObject: export, options: .prettyPrinted)
    }

    /// Deletes the signed-in account. MFA factors are revoked first (the RPC
    /// may remove the auth user, after which unenroll would be impossible).
    /// The deletion itself is one atomic server-side transaction
    /// (delete_my_account RPC), keyed on auth.uid(). It replaced a
    /// client-side cascade that silently no-oped on wrong column names.
    /// All or nothing: on failure this rethrows, the data is intact and the
    /// user stays signed in to retry; on success the local session is
    /// signed out best-effort.
    static func deleteAccount() async throws {
        if let factors = try? await supabase.auth.mfa.listFactors() {
            for factor in factors.totp {
                _ = try? await supabase.auth.mfa.unenroll(params: MFAUnenrollParams(factorId: factor.id))
            }
        }
        try await supabase.rpc("delete_my_account").execute()
        try? await supabase.auth.signOut()
    }
}
