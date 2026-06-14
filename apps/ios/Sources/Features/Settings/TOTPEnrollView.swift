import SwiftUI
import CoreImage.CIFilterBuiltins
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
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        if isLoading {
                            ProgressView().tint(.primary).padding(.top, 60)
                            Text("Se pregătește înrolarea…")
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                        } else if let error, factorId == nil {
                            errorState(error)
                        } else {
                            instructions
                            qrCard
                            secretCard
                            codeEntry
                            if let error { Text(error).font(.system(size: 13)).foregroundStyle(.red).multilineTextAlignment(.center) }
                            verifyButton
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Authenticator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anulează") { cancel() }
                }
            }
            .task { await startEnroll() }
        }
    }

    // MARK: - Sections

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scanează codul cu o aplicație de autentificare (Google Authenticator, 1Password, Authy) sau introdu cheia manual, apoi tastează codul de 6 cifre.")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var qrCard: some View {
        VStack {
            if let img = qrImage(from: otpauthURI) {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 200, height: 200)
                    .padding(16)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var secretCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CHEIE MANUALĂ").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            HStack {
                Text(secret)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
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
            }
            .padding(14)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var codeEntry: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("COD DE 6 CIFRE").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            TextField("000000", text: $code)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .padding(14)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onChange(of: code) { _, v in
                    code = String(v.filter(\.isNumber).prefix(6))
                }
        }
    }

    private var verifyButton: some View {
        Button { Task { await verify() } } label: {
            Group {
                if isVerifying { ProgressView().tint(.white) }
                else { Text("Activează").font(.system(size: 16, weight: .semibold)) }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(code.count == 6 ? Color.blue : Color.gray, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(code.count != 6 || isVerifying)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.shield.fill").font(.system(size: 40)).foregroundStyle(.orange)
            Text("Nu s-a putut porni înrolarea")
                .font(.system(size: 16, weight: .semibold))
            Text(message)
                .font(.system(size: 13)).foregroundStyle(.secondary)
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
                params: MFAEnrollParams(factorType: .totp, issuer: "PRVIO",
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
            self.error = "Cod invalid sau expirat. Încearcă din nou."
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

    private func qrImage(from string: String) -> UIImage? {
        guard !string.isEmpty else { return nil }
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
