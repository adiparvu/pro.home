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
                let data = try await AccountDeletionService.exportJSON()
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
            try await AccountDeletionService.deleteAccount()
        } catch {
            alertMessage = String(format: String(localized: "delete_account_failed_fmt"),
                                  error.localizedDescription)
            showPasswordAlert = true
        }
        isDeletingAccount = false
    }
}
