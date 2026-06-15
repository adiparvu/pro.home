import SwiftUI
import LocalAuthentication
import Supabase

struct SecurityView: View {
    @EnvironmentObject private var auth: AuthService
    @AppStorage("prvio.biometrics") private var biometricsEnabled = false
    @AppStorage("prvio.lockMode") private var lockModeEnabled = false
    @State private var biometricType: LABiometryType = .none
    @State private var showDeleteConfirm = false
    @State private var showPasswordAlert = false
    @State private var passwordResetSent = false
    @State private var alertMessage = ""
    @State private var showActiveSessions = false
    @State private var exportItem: ExportItem?
    @State private var isExporting = false
    @State private var isDeletingAccount = false
    @State private var showAutoLockPicker = false
    @AppStorage("prvio.autoLockMinutes") private var autoLockMinutes = 5
    @State private var showTOTPEnroll = false
    @State private var totpFactorId: String?
    @State private var showRemoveTOTP = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                PageHeader(title: "Security")
                mfaSection
                sessionsSection
                advancedSection
                biometricSection
                dataSection
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { checkBiometrics() }
        .task { await loadFactors() }
        .sheet(isPresented: $showTOTPEnroll) {
            TOTPEnrollView { Task { await loadFactors() } }
        }
        .confirmationDialog("Disable authenticator app?", isPresented: $showRemoveTOTP, titleVisibility: .visible) {
            Button("Disable", role: .destructive) { Task { await removeTOTP() } }
            Button("Cancel", role: .cancel) {}
        }
        .alert(alertMessage, isPresented: $showPasswordAlert) {
            Button("OK", role: .cancel) {}
        }
        .confirmationDialog("Delete account", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete permanently", role: .destructive) { Task { await deleteAccount() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All your data will be permanently deleted. This action cannot be undone.")
        }
        .sheet(item: $exportItem) { item in ShareSheet(activityItems: [item.url]) }
        .sheet(isPresented: $showActiveSessions) { ActiveSessionsSheet() }
        .confirmationDialog("Auto-lock", isPresented: $showAutoLockPicker, titleVisibility: .visible) {
            ForEach([1, 5, 15, 30], id: \.self) { minutes in
                Button("\(minutes) min") { autoLockMinutes = minutes }
            }
            Button("Never") { autoLockMinutes = 0 }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - MFA

    private var mfaSection: some View {
        secGroup(title: "Multi-factor authentication (MFA)", footer: "Requires an additional security check at sign-in. If you fail this check, you will have the option to recover your account.") {
            Button {
                if totpFactorId != nil { showRemoveTOTP = true } else { showTOTPEnroll = true }
            } label: {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "apps.iphone", color: .indigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Authenticator app")
                            .font(.system(size: 15)).foregroundStyle(.primary)
                        Text("TOTP codes (Google Authenticator, 1Password…)")
                            .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.4))
                    }
                    Spacer()
                    if totpFactorId != nil {
                        Text("Enabled").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(red: 0.2, green: 0.78, blue: 0.45))
                    } else {
                        Text("Disabled").font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.38))
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.primary.opacity(0.28))
                }
                .padding(.horizontal, 14).padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            divider
            statusRow(icon: "message.fill", color: Color(red: 0.3, green: 0.82, blue: 0.45), title: "Text messages", status: "Coming soon")
        }
    }

    // MARK: - Sessions

    private var sessionsSection: some View {
        secGroup(title: "Sessions", footer: "See all devices and sessions that have accessed your account. You can check active sessions, remove trusted devices, or use \"Sign out of all devices\" to end all sessions.") {
            Button { showActiveSessions = true } label: {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "macbook.and.iphone", color: .blue)
                    Text("Active sessions")
                        .font(.system(size: 15)).foregroundStyle(.primary)
                    Spacer()
                    Text("1")
                        .font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.4))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.primary.opacity(0.28))
                }
                .padding(.horizontal, 14).padding(.vertical, 13)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Advanced security

    private var advancedSection: some View {
        secGroup(title: "Advanced security") {
            Button {
                Task { await sendPasswordReset() }
            } label: {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "key.fill", color: .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Advanced account security")
                            .font(.system(size: 15)).foregroundStyle(.primary)
                        Text("Change password or email")
                            .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.4))
                    }
                    Spacer()
                    if passwordResetSent {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.primary.opacity(0.28))
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 13)
            }
            .buttonStyle(.plain)

            divider

            HStack(spacing: 12) {
                ColoredIconBadge(icon: "lock.shield.fill", color: .purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lockdown mode")
                        .font(.system(size: 15)).foregroundStyle(.primary)
                    Text("Requires more secure sign-in methods")
                        .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.4))
                }
                Spacer()
                Toggle("", isOn: $lockModeEnabled)
                    .labelsHidden().tint(.purple)
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
        }
    }

    // MARK: - Biometrics (PRVIO codex)

    private var biometricSection: some View {
        secGroup(title: "PRVIO") {
            if biometricType != .none {
                HStack(spacing: 12) {
                    ColoredIconBadge(
                        icon: biometricType == .faceID ? "faceid" : "touchid",
                        color: Color(red: 0.3, green: 0.82, blue: 0.45)
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(biometricType == .faceID ? "Require Face ID" : "Require Touch ID")
                            .font(.system(size: 15)).foregroundStyle(.primary)
                        Text("Face ID or passcode to access PRVIO")
                            .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.4))
                    }
                    Spacer()
                    Toggle("", isOn: $biometricsEnabled)
                        .labelsHidden().tint(.blue)
                        .onChange(of: biometricsEnabled) { _, newVal in
                            if newVal { Task { await authenticateBiometric() } }
                        }
                }
                .padding(.horizontal, 14).padding(.vertical, 13)

                divider
            }

            Button { showAutoLockPicker = true } label: {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "timer", color: .cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-lock")
                            .font(.system(size: 15)).foregroundStyle(.primary)
                        Text(autoLockMinutes == 0 ? "Never auto-locks" : "Locks after \(autoLockMinutes) min of inactivity")
                            .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.4))
                    }
                    Spacer()
                    Text(autoLockMinutes == 0 ? "Never" : "\(autoLockMinutes) min")
                        .font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.38))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.primary.opacity(0.28))
                }
                .padding(.horizontal, 14).padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Data & Privacy

    private var dataSection: some View {
        secGroup(title: "Data & Privacy") {
            Button { exportData() } label: {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "square.and.arrow.up.fill", color: .cyan)
                    Text("Export my data")
                        .font(.system(size: 15)).foregroundStyle(.primary)
                    Spacer()
                    if isExporting {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.primary.opacity(0.28))
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 13)
            }
            .buttonStyle(.plain)

            divider

            Button { showDeleteConfirm = true } label: {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "trash.fill", color: .red)
                    Text("Delete account")
                        .font(.system(size: 15)).foregroundStyle(.red)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.primary.opacity(0.28))
                }
                .padding(.horizontal, 14).padding(.vertical, 13)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func secGroup<Content: View>(title: String, footer: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 8)

            VStack(spacing: 0) { content() }
                .liquidGlass(cornerRadius: 20)

            if let footer {
                Text(footer)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.38))
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
            }
        }
    }

    private func statusRow(icon: String, color: Color, title: String, status: String) -> some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color)
            Text(title)
                .font(.system(size: 15)).foregroundStyle(.primary)
            Spacer()
            Text(status)
                .font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.38))
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.4).padding(.leading, 52)
    }

    // MARK: - Actions

    private func loadFactors() async {
        do {
            let factors = try await supabase.auth.mfa.listFactors()
            totpFactorId = factors.totp.first?.id
        } catch {
            // leave as-is on error
        }
    }

    private func removeTOTP() async {
        guard let id = totpFactorId else { return }
        do {
            try await supabase.auth.mfa.unenroll(params: MFAUnenrollParams(factorId: id))
            totpFactorId = nil
            HapticFeedback.success()
        } catch {
            alertMessage = "Could not disable. Please try again."
            showPasswordAlert = true
        }
    }

    private func checkBiometrics() {
        let ctx = LAContext(); var err: NSError?
        if ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) {
            biometricType = ctx.biometryType
        }
    }

    private func authenticateBiometric() async {
        let ctx = LAContext()
        let reason = biometricType == .faceID ? "Enable Face ID for PRVIO" : "Enable Touch ID for PRVIO"
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            if !ok { biometricsEnabled = false }
        } catch { biometricsEnabled = false }
    }

    private func sendPasswordReset() async {
        guard let email = auth.session?.user.email else { return }
        do {
            try await supabase.auth.resetPasswordForEmail(email)
            passwordResetSent = true
            alertMessage = "Reset email sent to \(email). Check your inbox."
            showPasswordAlert = true
        } catch {
            alertMessage = "Could not send the email. Please try again."
            showPasswordAlert = true
        }
    }

    private func exportData() {
        guard !isExporting else { return }
        isExporting = true
        Task {
            do {
                let userId = try await supabase.auth.session.user.id
                let tasksData   = (try? await supabase.from("maintenance_tasks").select().execute().data)   ?? Data()
                let recordsData = (try? await supabase.from("financial_records").select().execute().data)   ?? Data()
                let docsData    = (try? await supabase.from("documents").select().execute().data)            ?? Data()
                let tasks     = (try? JSONSerialization.jsonObject(with: tasksData))   as? [[String: Any]] ?? []
                let records   = (try? JSONSerialization.jsonObject(with: recordsData)) as? [[String: Any]] ?? []
                let docs      = (try? JSONSerialization.jsonObject(with: docsData))    as? [[String: Any]] ?? []
                let export: [String: Any] = [
                    "exported_at": ISO8601DateFormatter().string(from: Date()),
                    "user_id": userId.uuidString,
                    "tasks": tasks, "financial_records": records, "documents": docs
                ]
                let data = try JSONSerialization.data(withJSONObject: export, options: .prettyPrinted)
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("prvio_export.json")
                try data.write(to: tmp)
                await MainActor.run { isExporting = false; exportItem = ExportItem(url: tmp) }
            } catch {
                await MainActor.run {
                    isExporting = false
                    alertMessage = "Export failed: \(error.localizedDescription)"
                    showPasswordAlert = true
                }
            }
        }
    }

    private func deleteAccount() async {
        isDeletingAccount = true
        do {
            let userId = try await supabase.auth.session.user.id
            for table in ["maintenance_tasks", "financial_records", "documents", "contractors"] {
                try? await supabase.from(table).delete().eq("user_id", value: userId.uuidString).execute()
            }
            // profiles is keyed by the user id itself, not a user_id column.
            try? await supabase.from("profiles").delete().eq("id", value: userId.uuidString).execute()
            try? await supabase.auth.signOut()
        } catch { try? await supabase.auth.signOut() }
        isDeletingAccount = false
    }
}

// MARK: - Active Sessions Sheet

private struct ActiveSessionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthService

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        sessionRow(
                            icon: "iphone",
                            title: "This device",
                            subtitle: "Current session · active now",
                            color: Color(red: 0.3, green: 0.82, blue: 0.45),
                            isCurrent: true
                        )
                    }
                    .liquidGlass(cornerRadius: 20)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    Text("You can sign out other sessions if you notice suspicious activity.")
                        .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.38))
                        .multilineTextAlignment(.center).padding(.horizontal, 28).padding(.top, 16)

                    Button {
                        Task { try? await supabase.auth.signOut(scope: .others) }
                    } label: {
                        Text("Sign out all other sessions")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(.red)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20).padding(.top, 20)
                }
            }
            .navigationTitle("Active sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(.blue)
                }
            }
        }
    }

    private func sessionRow(icon: String, title: String, subtitle: String, color: Color, isCurrent: Bool) -> some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 15)).foregroundStyle(.primary)
                    if isCurrent {
                        Text("CURRENT")
                            .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(color, in: Capsule())
                    }
                }
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.4))
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
    }
}

// MARK: - Helpers

struct ExportItem: Identifiable {
    let id = UUID()
    let url: URL
}
