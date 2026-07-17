import SwiftUI

// Backup codes live SERVER-SIDE as SHA-256 hashes (`backup_codes` table) and
// each unlocks the two-step sign-in gate exactly once — the honest recovery
// path for a lost authenticator app. They are NOT password recovery; the
// copy below says exactly what they do.
struct BackupCodesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var security = AccountSecurityService.shared
    @State private var codes: [String] = []
    @State private var isWorking = false
    @State private var showCopyConfirm = false
    @State private var showRegenerateConfirm = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        warningCard
                        codesGrid
                        actionButtons
                        regenerateButton
                        Spacer(minLength: 60)
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.lg)
                }
            }
            .navigationTitle("Coduri de rezervă")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gata") { dismiss() }.foregroundStyle(.blue)
                }
            }
        }
        .presentationBackground(.thinMaterial)
        .task { await loadState() }
        .confirmationDialog("Generează coduri noi?", isPresented: $showRegenerateConfirm, titleVisibility: .visible) {
            Button("Generează coduri noi", role: .destructive) { Task { await generateNewCodes() } }
            Button("Anulează", role: .cancel) {}
        } message: {
            Text("Codurile existente vor fi invalidate imediat.")
        }
    }

    // MARK: - Warning card

    private var warningCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(AppFont.scaled(20))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("Păstrează-le în siguranță")
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(.primary)
                Text("Un cod deblochează verificarea în doi pași o singură dată, dacă rămâi fără aplicația de autentificare. Nu recuperează parola.")
                    .font(AppFont.scaled(12))
                    .foregroundStyle(Color.primary.opacity(0.55))
            }
        }
        .padding(AppSpacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.5)
        )
    }

    // MARK: - Codes grid

    private var codesGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CODURI DE REZERVĂ")
                .font(AppFont.label)
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.leading, AppSpacing.xxs)

            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(codes.enumerated()), id: \.offset) { idx, code in
                    HStack {
                        Text("\(idx + 1).")
                            .font(AppFont.scaled(12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                            .frame(width: 20, alignment: .trailing)
                        Text(code)
                            .font(AppFont.scaled(15, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)
                            .tracking(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppSpacing.base)
                    .padding(.vertical, 13)
                    .overlay(alignment: .bottom) {
                        if idx < codes.count - 2 {
                            Rectangle()
                                .fill(Color.primary.opacity(AppOpacity.hairline))
                                .frame(height: 0.4)
                        }
                    }
                    .overlay(alignment: .trailing) {
                        if idx % 2 == 0 {
                            Rectangle()
                                .fill(Color.primary.opacity(AppOpacity.hairline))
                                .frame(width: 0.4)
                        }
                    }
                }
            }
            .liquidGlass(cornerRadius: AppRadius.xl)
        }
    }

    // MARK: - Action buttons

    /// Copy/share only make sense while the plaintext is on screen — the
    /// redacted rows after a relaunch have nothing real to hand out.
    private var codesAreRedacted: Bool { codes.first?.contains("•") ?? true }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button { copyAll() } label: {
                Label("Copiază tot", systemImage: showCopyConfirm ? "checkmark" : "doc.on.doc.fill")
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(showCopyConfirm ? Color.brandSuccess : .primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.primary.opacity(AppOpacity.hairline), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .disabled(codesAreRedacted)
            .opacity(codesAreRedacted ? AppOpacity.disabled : 1)

            Button { shareAll() } label: {
                Label("Descarcă", systemImage: "square.and.arrow.up.fill")
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.primary.opacity(AppOpacity.hairline), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .disabled(codesAreRedacted)
            .opacity(codesAreRedacted ? AppOpacity.disabled : 1)
        }
    }

    // MARK: - Regenerate button

    private var regenerateButton: some View {
        Button { showRegenerateConfirm = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(AppFont.scaled(13))
                Text("Generează coduri noi")
                    .font(AppFont.footnote)
            }
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.red.opacity(0.15), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Server-backed state

    /// First open: no codes on the account → generate a fresh set and show
    /// it (the only moment plaintext exists). Later opens: only hashes exist
    /// anywhere, so show redacted placeholders for the unused count — the
    /// user either wrote them down or regenerates.
    private func loadState() async {
        guard codes.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        await security.refreshBackupCodeCount()
        if let unused = security.unusedBackupCodes {
            if unused == 0 {
                await generateNewCodes()
            } else {
                codes = (0..<unused).map { _ in "•••••-•••••" }
            }
        }
    }

    private func generateNewCodes() async {
        do {
            codes = try await security.regenerateBackupCodes()
            AuditLogService.AuditEvent.record("backup_codes_generated", String(localized: "Coduri de rezervă generate"))
        } catch { /* keep whatever was on screen — never show fake codes */ }
    }

    // MARK: - Actions

    private func copyAll() {
        let text = codes.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        UIPasteboard.general.string = text
        HapticFeedback.success()
        withAnimation(AppMotion.state) { showCopyConfirm = true }
        Task { try? await Task.sleep(for: .milliseconds(2000)); withAnimation(AppMotion.state) { showCopyConfirm = false } }
    }

    private func shareAll() {
        let header = String(localized: "PRVIO Backup Codes")
        let footer = String(localized: "Each code can be used only once. Keep them safe.")
        let codeLines = codes.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let text = "\(header)\n\n\(codeLines)\n\n\(footer)"
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            var presented = root
            while let next = presented.presentedViewController { presented = next }
            presented.present(av, animated: true)
        }
    }
}
