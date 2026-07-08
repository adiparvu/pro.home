import SwiftUI
import Supabase

/// End-to-end TOTP (authenticator app) enrollment via Supabase MFA:
/// enroll → show QR + secret → user enters 6-digit code → challenge & verify.
struct TOTPEnrollView: View {
    var onEnrolled: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var factorId: String?
    @State private var secret = ""
    @State private var otpauthURI = ""
    @State private var code = ""
    @State private var error: String?
    @State private var isLoading = true
    @State private var isVerifying = false
    @State private var verified = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        if isLoading {
                            ProgressView().tint(.primary).padding(.top, 60)
                            Text("Preparing enrollment…")
                                .font(AppFont.scaled(13)).foregroundStyle(.secondary)
                        } else if let error, factorId == nil {
                            errorState(error)
                        } else {
                            instructions
                            qrCard
                            secretCard
                            codeEntry
                            if let error { Text(LocalizedStringKey(error)).font(AppFont.scaled(13)).foregroundStyle(.red).multilineTextAlignment(.center) }
                            verifyButton
                        }
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.md)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Authenticator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancel() }
                }
            }
            .task { await startEnroll() }
        }
        .presentationBackground(.thinMaterial)
    }

    // MARK: - Sections

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scan the code with an authenticator app (Google Authenticator, 1Password, Authy) or enter the key manually, then type the 6-digit code.")
                .font(AppFont.scaled(14))
                .foregroundStyle(Color.primary.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var qrCard: some View {
        VStack {
            // High-contrast, unobstructed style so third-party authenticator
            // apps scan it reliably.
            QRCodeImage(content: otpauthURI, size: 200, style: .plain)
        }
        .frame(maxWidth: .infinity)
    }

    private var secretCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MANUAL KEY").font(AppFont.label).foregroundStyle(.secondary)
            HStack {
                Text(secret)
                    .font(AppFont.scaled(15, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Spacer()
                Button {
                    UIPasteboard.general.string = secret
                    HapticFeedback.success()
                } label: {
                    Image(systemName: "doc.on.doc").foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy secret code")
            }
            .padding(AppSpacing.base)
            .background(Color.primary.opacity(AppOpacity.hairline), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        }
    }

    private var codeEntry: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("6-DIGIT CODE").font(AppFont.label).foregroundStyle(.secondary)
            TextField("000000", text: $code)
                .font(AppFont.scaled(22, weight: .semibold, design: .monospaced))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .padding(AppSpacing.base)
                .background(Color.primary.opacity(AppOpacity.hairline), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                .onChange(of: code) { _, v in
                    code = String(v.filter(\.isNumber).prefix(6))
                }
        }
    }

    private var verifyButton: some View {
        Button { Task { await verify() } } label: {
            Group {
                if isVerifying { ProgressView().tint(.white) }
                else { Text("Activate").font(AppFont.headline) }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.lg)
            .background(code.count == 6 ? Color.blue : Color.gray, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(code.count != 6 || isVerifying)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.shield.fill").font(AppFont.scaled(40)).foregroundStyle(.orange)
            Text("Could not start enrollment")
                .font(AppFont.headline)
            Text(LocalizedStringKey(message))
                .font(AppFont.scaled(13)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 40)
    }

    // MARK: - Actions

    private func startEnroll() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await supabase.auth.mfa.enroll(
                params: MFATotpEnrollParams(issuer: "PRVIO",
                                            friendlyName: "PRVIO-\(UUID().uuidString.prefix(6))")
            )
            factorId = response.id
            secret = response.totp?.secret ?? ""
            otpauthURI = response.totp?.uri ?? ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func verify() async {
        guard let factorId, code.count == 6 else { return }
        isVerifying = true
        defer { isVerifying = false }
        do {
            try await supabase.auth.mfa.challengeAndVerify(
                params: MFAChallengeAndVerifyParams(factorId: factorId, code: code)
            )
            verified = true
            HapticFeedback.success()
            onEnrolled()
            dismiss()
        } catch {
            self.error = String(localized: "Invalid or expired code. Please try again.")
            HapticFeedback.error()
        }
    }

    private func cancel() {
        // Clean up an unverified factor so it doesn't linger.
        if let factorId, !verified {
            Task { try? await supabase.auth.mfa.unenroll(params: MFAUnenrollParams(factorId: factorId)) }
        }
        dismiss()
    }
}
