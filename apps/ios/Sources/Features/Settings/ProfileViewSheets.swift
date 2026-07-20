import SwiftUI

// MARK: - Change Email Sheet

struct ChangeEmailSheet: View {
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var confirm = ""

    var isValid: Bool { !email.isEmpty && email == confirm && email.contains("@") }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                VStack(spacing: 16) {
                    VStack(spacing: 0) {
                        emailField("envelope.fill", "New email address", $email, keyboard: .emailAddress)
                        Rectangle().fill(Color.primary.opacity(AppOpacity.hairline)).frame(height: 0.5).padding(.leading, 52)
                        emailField("checkmark.circle.fill", "Confirm new email", $confirm, keyboard: .emailAddress)
                    }
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg))
                    .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))

                    Text("A verification link will be sent to your new address. Your email will only change after you confirm it.")
                        .font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(0.38))
                        .multilineTextAlignment(.center).padding(.horizontal, AppSpacing.sm)
                    Spacer()
                }
                .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.xl)
            }
            .navigationTitle("Change Email").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        onSave(email); HapticFeedback.success(); dismiss()
                    }
                    .font(AppFont.subheadline).foregroundStyle(Color.accentColor)
                    .disabled(!isValid)
                }
            }
        }
        .presentationBackground(.thinMaterial)
    }

    private func emailField(_ icon: String, _ ph: String, _ b: Binding<String>, keyboard: UIKeyboardType) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(AppFont.scaled(14)).foregroundStyle(Color.accentColor).frame(width: 28)
            TextField(ph, text: b)
                .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                .keyboardType(keyboard).autocorrectionDisabled().textInputAutocapitalization(.never)
        }.padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.base)
    }
}

// MARK: - Change Password Sheet

struct ChangePasswordSheet: View {
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirm = ""
    @State private var showPassword = false

    var isValid: Bool { password.count >= 6 && password == confirm }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                VStack(spacing: 16) {
                    VStack(spacing: 0) {
                        passField("lock.fill", "New password", $password)
                        Rectangle().fill(Color.primary.opacity(AppOpacity.hairline)).frame(height: 0.5).padding(.leading, 52)
                        passField("lock.rotation", "Confirm password", $confirm)
                    }
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg))
                    .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))

                    if !password.isEmpty && password.count < 6 {
                        Text("Password must be at least 6 characters")
                            .font(AppFont.scaled(12)).foregroundStyle(.orange)
                    }
                    if !confirm.isEmpty && password != confirm {
                        Text("Passwords don't match")
                            .font(AppFont.scaled(12)).foregroundStyle(.red)
                    }
                    Spacer()
                }
                .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.xl)
            }
            .navigationTitle("Change Password").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Update") {
                        onSave(password); HapticFeedback.success(); dismiss()
                    }
                    .font(AppFont.subheadline).foregroundStyle(Color.accentColor)
                    .disabled(!isValid)
                }
            }
        }
        .presentationBackground(.thinMaterial)
    }

    private func passField(_ icon: String, _ ph: String, _ b: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(AppFont.scaled(14)).foregroundStyle(Color.accentColor).frame(width: 28)
            SecureField(ph, text: b)
                .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
        }.padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.base)
    }
}
