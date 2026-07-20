import SwiftUI

// MARK: - MFAChallengeView — the sign-in gate for accounts with TOTP
//
// Shown as an undismissable full-screen cover while
// `AccountSecurityService.needsMFAChallenge` holds: the password produced an
// AAL1 session, the account has a verified authenticator factor, and PRVIO
// will not reveal the app until the 6-digit code verifies (raising the
// session to AAL2) — or a one-time backup code spends at the gate. The only
// other way out is signing out, which must always remain reachable so a
// lost authenticator can never brick the login screen itself.

struct MFAChallengeView: View {
    @Environment(AuthService.self) private var auth

    @State private var security = AccountSecurityService.shared
    @State private var code = ""
    @State private var backupCode = ""
    @State private var usingBackupCode = false
    @State private var isVerifying = false
    @State private var failed = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: AppSpacing.xl) {
                Spacer(minLength: AppSpacing.xxl)

                Image(systemName: "lock.shield.fill")
                    .font(AppFont.scaled(44, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: AppSpacing.sm) {
                    Text("Two-step verification")
                        .font(AppFont.title2)
                        .foregroundStyle(.primary)
                    Text(usingBackupCode
                         ? "Enter one of your one-time backup codes."
                         : "Enter the 6-digit code from your authenticator app.")
                        .font(AppFont.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, AppSpacing.xl)

                Group {
                    if usingBackupCode {
                        TextField("XXXXX-XXXXX", text: $backupCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(AppFont.scaled(22, weight: .semibold, design: .monospaced))
                    } else {
                        TextField("000000", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .font(AppFont.scaled(28, weight: .semibold, design: .monospaced))
                            .onChange(of: code) { _, value in
                                code = String(value.filter(\.isNumber).prefix(6))
                                if code.count == 6 { Task { await verify() } }
                            }
                    }
                }
                .multilineTextAlignment(.center)
                .focused($fieldFocused)
                .padding(.vertical, AppSpacing.base)
                .padding(.horizontal, AppSpacing.lg)
                .frame(maxWidth: 280)
                .liquidGlass(cornerRadius: AppRadius.lg)

                if failed {
                    Text(usingBackupCode
                         ? "That backup code is invalid or was already used."
                         : "Invalid or expired code. Please try again.")
                        .font(AppFont.footnote)
                        .foregroundStyle(Color.brandDanger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.xl)
                }

                Button {
                    Task { await verify() }
                } label: {
                    Group {
                        if isVerifying {
                            ProgressView().tint(.white)
                        } else {
                            Text("Verify")
                                .font(AppFont.headline)
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: 280)
                    .padding(.vertical, AppSpacing.base)
                    .background(canSubmit ? Color.accentColor : Color.gray,
                                in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit || isVerifying)

                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        usingBackupCode.toggle()
                        failed = false
                    }
                } label: {
                    Text(usingBackupCode ? "Use the authenticator app" : "Use a backup code")
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)

                Spacer()

                // The always-reachable exit: losing the authenticator must
                // never trap the user inside the gate.
                Button {
                    Task { try? await auth.signOut() }
                } label: {
                    Text("Sign out")
                        .font(AppFont.footnote)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.bottom, AppSpacing.xl)
            }
        }
        .onAppear { fieldFocused = true }
    }

    private var canSubmit: Bool {
        usingBackupCode
            ? backupCode.trimmingCharacters(in: .whitespaces).count >= 10
            : code.count == 6
    }

    private func verify() async {
        guard canSubmit, !isVerifying else { return }
        isVerifying = true
        failed = false
        let ok = usingBackupCode
            ? await security.verifyBackupCode(backupCode)
            : await security.verifyTOTP(code: code)
        isVerifying = false
        if ok {
            HapticFeedback.success()
        } else {
            failed = true
            HapticFeedback.error()
            if !usingBackupCode { code = "" }
        }
    }
}
