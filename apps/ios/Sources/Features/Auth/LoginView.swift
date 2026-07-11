import SwiftUI
import UIKit

struct LoginView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    enum Field { case email, password }

    private var canSubmit: Bool { !email.isEmpty && !password.isEmpty }

    var body: some View {
        ZStack {
            // Adaptive base — light/dark/system all handled by `appBackground`.
            appBackground.ignoresSafeArea()

            // Subtle brand glow at the top. Suppressed under Reduce Transparency
            // so the screen collapses to a clean solid surface.
            if !reduceTransparency {
                RadialGradient(
                    colors: [Color.brandSkyBlue.opacity(0.20), .clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 420
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                Spacer()

                brandEmblem
                    .padding(.bottom, AppSpacing.xxl)

                Text("PRVIO")
                    .font(AppFont.scaled(30, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .padding(.bottom, 40)

                form
                    .padding(.horizontal, AppSpacing.xxl)

                signInButton
                    .padding(.horizontal, AppSpacing.xxl)
                    .padding(.top, AppSpacing.lg)

                Spacer()
                Spacer()
            }
        }
    }

    // MARK: - Brand emblem
    //
    // The new PRVIO monogram (glowing white P-with-a-roof — the shared
    // `BrandMark` template asset) sits on a brand-gradient badge so the white
    // glyph reads with equal contrast in light and dark. The mark itself keeps
    // its glow; the gradient anchors the identity used by the app icon/splash.

    private var brandEmblem: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.xxl, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.brandSkyBlue, Color.brandPrimaryBlue, Color.brandPurple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image("BrandMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white)
                .shadow(color: .white.opacity(reduceTransparency ? 0 : 0.45), radius: 10)
                .padding(20)
        }
        .frame(width: 96, height: 96)
        .shadow(color: Color.brandSkyBlue.opacity(reduceTransparency ? 0 : 0.45), radius: 24, y: 10)
        .accessibilityLabel(Text("PRVIO"))
    }

    // MARK: - Form

    private var form: some View {
        VStack(spacing: AppSpacing.md) {
            GlassTextField(
                placeholder: "Email",
                text: $email,
                icon: "envelope",
                keyboardType: .emailAddress,
                textContentType: .username
            )
            .focused($focus, equals: .email)
            .submitLabel(.next)
            .onSubmit { focus = .password }

            GlassTextField(
                placeholder: "Password",
                text: $password,
                icon: "lock",
                isSecure: true,
                textContentType: .password
            )
            .focused($focus, equals: .password)
            .submitLabel(.go)
            .onSubmit { signIn() }

            if let error = errorMessage {
                Text(error)
                    .font(AppFont.caption)
                    .foregroundStyle(Color.brandDanger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppSpacing.xxs)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Sign in button

    private var signInButton: some View {
        GlassWideButton(label: "Sign In", isBusy: isLoading, isEnabled: canSubmit) {
            signIn()
        }
        .animation(.snappy, value: canSubmit)
    }

    private func signIn() {
        guard canSubmit else { return }
        focus = nil
        isLoading = true
        withAnimation(.snappy) { errorMessage = nil }
        Task {
            do {
                try await auth.signIn(email: email, password: password)
            } catch {
                withAnimation(.snappy) { errorMessage = error.localizedDescription }
            }
            isLoading = false
        }
    }
}

// MARK: - Glass text field
//
// A single adaptive glass field row. `textContentType` is threaded through to
// the underlying Text/SecureField so iOS credential autofill and iCloud
// Keychain can associate the username + password. The placeholder is a
// `LocalizedStringKey` so it localizes (RO/EN).

private struct GlassTextField: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    var icon: String
    var keyboardType: UIKeyboardType = .default
    var isSecure = false
    var textContentType: UITextContentType? = nil

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(AppFont.scaled(16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                        .textContentType(textContentType)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                        .textContentType(textContentType)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .font(AppFont.body)
            .foregroundStyle(.primary)
            .tint(.accentColor)
        }
        .padding(.horizontal, AppSpacing.lg)
        .frame(height: 52)
        .glassRoundedRect(AppRadius.lg)
    }
}
