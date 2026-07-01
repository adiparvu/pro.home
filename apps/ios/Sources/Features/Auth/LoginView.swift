import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthService
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    enum Field { case email, password }

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()
            RadialGradient(
                colors: [Color.primary.opacity(AppOpacity.hairline), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 400
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo
                VStack(spacing: 14) {
                    PRVIOLogoView(size: 84)
                        .shadow(color: Color(red: 0.24, green: 0.50, blue: 1.00).opacity(0.50), radius: 22, y: 8)

                    VStack(spacing: 4) {
                        Text("PRVIO")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Property management")
                            .font(AppFont.footnote)
                            .foregroundStyle(.white.opacity(0.45))
                            .tracking(0.4)
                    }
                }
                .padding(.bottom, 48)

                // Form
                VStack(spacing: 12) {
                    GlassTextField(
                        placeholder: "Email",
                        text: $email,
                        keyboardType: .emailAddress,
                        icon: "envelope"
                    )
                    .focused($focus, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }

                    GlassTextField(
                        placeholder: "Password",
                        text: $password,
                        isSecure: true,
                        icon: "lock"
                    )
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { signIn() }

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, AppSpacing.xxs)
                    }
                }
                .padding(.horizontal, AppSpacing.xxl)

                // Sign in button
                Button(action: signIn) {
                    ZStack {
                        if isLoading {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Text("Sign In")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.black)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(isLoading || email.isEmpty || password.isEmpty)
                .opacity((email.isEmpty || password.isEmpty) ? 0.5 : 1)
                .padding(.horizontal, AppSpacing.xxl)
                .padding(.top, AppSpacing.lg)

                Spacer()
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }

    private func signIn() {
        guard !email.isEmpty, !password.isEmpty else { return }
        focus = nil
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await auth.signIn(email: email, password: password)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

private struct GlassTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var isSecure = false
    var icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .font(.body)
        }
        .padding(.horizontal, AppSpacing.lg)
        .frame(height: 52)
        .glassRoundedRect(14)
    }
}
