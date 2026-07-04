import SwiftUI

// MARK: - Mandatory strong-password setup
//
// Shown as an undismissable full-screen cover the first time an invited
// account signs in (their user metadata carries needs_password=true). The
// account was created by the invite link without a password — leaving it that
// way would let anyone with the email inbox reuse the link's session.

struct ForcePasswordView: View {
    @Environment(AuthService.self) private var auth

    @State private var password = ""
    @State private var confirm = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    private struct Rule: Identifiable {
        let id: String
        let label: LocalizedStringKey
        let passes: (String) -> Bool
    }

    private let rules: [Rule] = [
        Rule(id: "len",   label: "At least 10 characters",   passes: { $0.count >= 10 }),
        Rule(id: "upper", label: "One uppercase letter",     passes: { $0.contains(where: \.isUppercase) }),
        Rule(id: "lower", label: "One lowercase letter",     passes: { $0.contains(where: \.isLowercase) }),
        Rule(id: "digit", label: "One number",               passes: { $0.contains(where: \.isNumber) }),
        Rule(id: "sym",   label: "One symbol (!@#$…)",       passes: { $0.contains { !$0.isLetter && !$0.isNumber } }),
    ]

    private var allRulesPass: Bool { rules.allSatisfy { $0.passes(password) } }
    private var canSave: Bool { allRulesPass && password == confirm && !isSaving }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    ZStack {
                        Circle().fill(Color.accentColor.opacity(0.14))
                            .frame(width: 84, height: 84)
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 38))
                            .foregroundStyle(Color.accentColor)
                    }
                    .padding(.top, 48)

                    VStack(spacing: 8) {
                        Text("Secure your account")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("You signed in with an invitation link. Set a strong password to protect your account — you'll use it for future sign-ins.")
                            .font(AppFont.subheadline)
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppSpacing.sm)
                    }

                    VStack(spacing: 0) {
                        secureRow(icon: "key.fill", placeholder: "New password", text: $password)
                        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52)
                        secureRow(icon: "key.fill", placeholder: "Confirm password", text: $confirm)
                    }
                    .liquidGlass(cornerRadius: AppRadius.lg)

                    // Live checklist
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(rules) { rule in
                            let ok = rule.passes(password)
                            HStack(spacing: 8) {
                                Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 13))
                                    .foregroundStyle(ok ? Color.brandSuccess : Color.primary.opacity(0.25))
                                Text(rule.label)
                                    .font(.system(size: 13))
                                    .foregroundStyle(ok ? .primary : Color.primary.opacity(AppOpacity.mediumText))
                            }
                        }
                        if !confirm.isEmpty && confirm != password {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 13)).foregroundStyle(.red)
                                Text("Passwords don't match")
                                    .font(.system(size: 13)).foregroundStyle(.red)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppSpacing.base)
                    .liquidGlass(cornerRadius: AppRadius.lg)

                    if let err = errorMessage {
                        Text(err).font(.system(size: 13)).foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        Group {
                            if isSaving { ProgressView().tint(.white) }
                            else {
                                Text("Set password")
                                    .font(AppFont.subheadline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .foregroundStyle(.white)
                        .background(
                            canSave
                                ? AnyShapeStyle(LinearGradient(colors: [Color.accentColor, Color.brandPurple],
                                                               startPoint: .leading, endPoint: .trailing))
                                : AnyShapeStyle(Color.primary.opacity(0.15)),
                            in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)

                    Spacer(minLength: 30)
                }
                .padding(.horizontal, AppSpacing.xl)
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await auth.completePasswordSetup(password: password)
            HapticFeedback.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func secureRow(icon: String, placeholder: LocalizedStringKey, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14))
                .foregroundStyle(Color.accentColor).frame(width: 28)
            SecureField(placeholder, text: text)
                .font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor)
                .textContentType(.newPassword)
        }
        .padding(.horizontal, AppSpacing.lg).padding(.vertical, 13)
    }
}
