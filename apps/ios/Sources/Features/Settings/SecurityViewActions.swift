import SwiftUI
import LocalAuthentication
import Supabase

extension SecurityView {

    // MARK: - MFA

    func loadFactors() async {
        do {
            let factors = try await supabase.auth.mfa.listFactors()
            totpFactorId = factors.totp.first?.id
        } catch {
            // leave as-is on error
        }
    }

    func removeTOTP() async {
        guard let id = totpFactorId else { return }
        do {
            try await supabase.auth.mfa.unenroll(params: MFAUnenrollParams(factorId: id))
            totpFactorId = nil
            HapticFeedback.success()
        } catch {
            alertMessage = String(localized: "Could not disable. Please try again.")
            showPasswordAlert = true
        }
    }

    // MARK: - Biometrics

    func checkBiometrics() {
        let ctx = LAContext(); var err: NSError?
        if ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) {
            biometricType = ctx.biometryType
        }
    }

    func authenticateBiometric() async {
        let ctx = LAContext()
        let reason = biometricType == .faceID ? String(localized: "Enable Face ID for PRVIO") : String(localized: "Enable Touch ID for PRVIO")
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            if !ok { biometricsEnabled = false }
        } catch { biometricsEnabled = false }
    }

    // MARK: - Password Reset

    func sendPasswordReset() async {
        guard let email = auth.session?.user.email else { return }
        do {
            try await supabase.auth.resetPasswordForEmail(email)
            passwordResetSent = true
            alertMessage = String(format: String(localized: "Reset email sent to %@. Check your inbox."), email)
            showPasswordAlert = true
        } catch {
            alertMessage = String(localized: "Could not send the email. Please try again.")
            showPasswordAlert = true
        }
    }

    // MARK: - Export

    func exportData() {
        guard !isExporting else { return }
        isExporting = true
        Task {
            do {
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
                let data = try JSONSerialization.data(withJSONObject: export, options: .prettyPrinted)
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("prvio_export.json")
                try data.write(to: tmp)
                await MainActor.run { isExporting = false; exportItem = ExportItem(url: tmp) }
            } catch {
                await MainActor.run {
                    isExporting = false
                    alertMessage = String(format: String(localized: "Export failed: %@"), error.localizedDescription)
                    showPasswordAlert = true
                }
            }
        }
    }

    // MARK: - Delete Account

    func deleteAccount() async {
        isDeletingAccount = true
        do {
            let userId = try await supabase.auth.session.user.id
            for table in ["maintenance_tasks", "financial_records", "documents", "contractors"] {
                try? await supabase.from(table).delete().eq("user_id", value: userId.uuidString).execute()
            }
            // profiles is keyed by the user id itself, not a user_id column.
            try? await supabase.from("profiles").delete().eq("id", value: userId.uuidString).execute()
            try? await supabase.auth.signOut()
        } catch { try? await supabase.auth.signOut() }
        isDeletingAccount = false
    }
}
