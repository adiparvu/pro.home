import SwiftUI
import CryptoKit

struct BackupCodesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var codes: [String] = []
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
        .onAppear { generateCodesIfNeeded() }
        .confirmationDialog("Generează coduri noi?", isPresented: $showRegenerateConfirm, titleVisibility: .visible) {
            Button("Generează coduri noi", role: .destructive) { generateNewCodes() }
            Button("Anulează", role: .cancel) {}
        } message: {
            Text("Codurile existente vor fi invalidate imediat.")
        }
    }

    // MARK: - Warning card

    private var warningCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("Păstrează-le în siguranță")
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(.primary)
                Text("Stochează aceste coduri undeva sigur. Fiecare cod poate fi folosit o singură dată.")
                    .font(.system(size: 12))
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
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                            .frame(width: 20, alignment: .trailing)
                        Text(code)
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
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
        }
    }

    // MARK: - Regenerate button

    private var regenerateButton: some View {
        Button { showRegenerateConfirm = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13))
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

    // MARK: - Code generation

    private func generateCodesIfNeeded() {
        // Don't regenerate if codes are already visible in this session.
        guard codes.isEmpty else { return }
        if UserDefaults.standard.data(forKey: "prvio.backupCodesHash") == nil {
            // First time: generate fresh codes.
            generateNewCodes()
        } else {
            // Codes were generated in a previous session; codes aren't stored in
            // plain text (only hashes). Show redacted placeholders so the user
            // can either use them (if written down) or regenerate.
            codes = (0..<8).map { _ in "•••••-•••••" }
        }
    }

    private func generateNewCodes() {
        codes = (0..<8).map { _ in makeCode() }
        saveHashes()
        AuditLogService.AuditEvent.record("backup_codes_generated", String(localized: "Coduri de rezervă generate"))
    }

    private func makeCode() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let part1 = String((0..<5).map { _ in chars[Int.random(in: 0..<chars.count)] })
        let part2 = String((0..<5).map { _ in chars[Int.random(in: 0..<chars.count)] })
        return "\(part1)-\(part2)"
    }

    private func saveHashes() {
        let hashes = codes.map { code -> String in
            let data = Data(code.utf8)
            let digest = SHA256.hash(data: data)
            return digest.compactMap { String(format: "%02x", $0) }.joined()
        }
        if let encoded = try? JSONEncoder().encode(hashes) {
            UserDefaults.standard.set(encoded, forKey: "prvio.backupCodesHash")
        }
    }

    // MARK: - Actions

    private func copyAll() {
        let text = codes.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        UIPasteboard.general.string = text
        HapticFeedback.success()
        withAnimation { showCopyConfirm = true }
        Task { try? await Task.sleep(for: .milliseconds(2000)); withAnimation { showCopyConfirm = false } }
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
