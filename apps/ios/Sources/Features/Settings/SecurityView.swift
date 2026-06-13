import SwiftUI
import LocalAuthentication

struct SecurityView: View {
    @EnvironmentObject private var auth: AuthService
    @AppStorage("prvhouse.biometrics") private var biometricsEnabled = false
    @State private var biometricType: LABiometryType = .none
    @State private var passwordResetSent = false
    @State private var showPasswordAlert = false
    @State private var alertMessage = ""
    @State private var showDeleteConfirm = false
    @State private var exportItem: ExportItem?
    @State private var isExporting = false
    @State private var isDeletingAccount = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                biometricSection
                accountSection
                dangerSection
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Security & Privacy")
        .navigationBarTitleDisplayMode(.large)
        .task { checkBiometrics() }
        .alert(alertMessage, isPresented: $showPasswordAlert) {
            Button("OK", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete Account",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete My Account", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This is permanent and cannot be undone. All your data will be lost.")
        }
        .sheet(item: $exportItem) { item in
            ShareSheet(activityItems: [item.url])
        }
    }

    // MARK: - Biometric

    private var biometricSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Authentication")

            VStack(spacing: 0) {
                if biometricType != .none {
                    HStack(spacing: 12) {
                        ColoredIconBadge(
                            icon: biometricType == .faceID ? "faceid" : "touchid",
                            color: Color(red: 0.3, green: 0.85, blue: 0.5)
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(biometricType == .faceID ? "Face ID" : "Touch ID")
                                .font(.system(size: 15))
                                .foregroundStyle(.primary)
                            Text("Unlock app without password")
                                .font(.system(size: 12))
                                .foregroundStyle(.primary.opacity(0.4))
                        }
                        Spacer()
                        Toggle("", isOn: $biometricsEnabled)
                            .labelsHidden()
                            .tint(.blue)
                            .onChange(of: biometricsEnabled) { _, newValue in
                                if newValue { Task { await authenticateBiometric() } }
                            }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    Rectangle()
                        .fill(.primary.opacity(0.05))
                        .frame(height: 0.5)
                        .padding(.leading, 52)
                }

                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "lock.rotation", color: .blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-Lock")
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                        Text("Locks after 5 minutes")
                            .font(.system(size: 12))
                            .foregroundStyle(.primary.opacity(0.4))
                    }
                    Spacer()
                    Text("5 min")
                        .font(.system(size: 14))
                        .foregroundStyle(.primary.opacity(0.38))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.28))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.primary.opacity(0.07), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Account")

            VStack(spacing: 0) {
                Button {
                    Task { await sendPasswordReset() }
                } label: {
                    HStack(spacing: 12) {
                        ColoredIconBadge(icon: "key.fill", color: .orange)
                        Text(passwordResetSent ? "Reset Email Sent" : "Change Password")
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                        Spacer()
                        if passwordResetSent {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.5))
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary.opacity(0.28))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                Rectangle()
                    .fill(.primary.opacity(0.05))
                    .frame(height: 0.5)
                    .padding(.leading, 52)

                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "shield.fill", color: .purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Two-Factor Authentication")
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                        Text("Managed via your email provider")
                            .font(.system(size: 12))
                            .foregroundStyle(.primary.opacity(0.4))
                    }
                    Spacer()
                    Text("On")
                        .font(.system(size: 14))
                        .foregroundStyle(.primary.opacity(0.38))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.primary.opacity(0.07), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Danger zone

    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Data & Privacy")

            VStack(spacing: 0) {
                Button {
                    exportData()
                } label: {
                    HStack(spacing: 12) {
                        ColoredIconBadge(icon: "square.and.arrow.up.fill", color: .cyan)
                        Text("Export My Data")
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.28))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                Rectangle()
                    .fill(.primary.opacity(0.05))
                    .frame(height: 0.5)
                    .padding(.leading, 52)

                Button { showDeleteConfirm = true } label: {
                    HStack(spacing: 12) {
                        ColoredIconBadge(icon: "trash.fill", color: .red)
                        Text("Delete Account")
                            .font(.system(size: 15))
                            .foregroundStyle(.red)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.28))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
            .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.primary.opacity(0.07), lineWidth: 0.5)
            )
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.primary.opacity(0.35))
            .padding(.leading, 4)
    }

    // MARK: - Actions

    private func checkBiometrics() {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            biometricType = context.biometryType
        }
    }

    private func authenticateBiometric() async {
        let context = LAContext()
        do {
            let reason = biometricType == .faceID
                ? "Enable Face ID for PRVHouse"
                : "Enable Touch ID for PRVHouse"
            let success = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            if !success { biometricsEnabled = false }
        } catch {
            biometricsEnabled = false
        }
    }

    private func sendPasswordReset() async {
        guard let email = auth.session?.user.email else { return }
        do {
            try await supabase.auth.resetPasswordForEmail(email)
            passwordResetSent = true
            alertMessage = "Password reset email sent to \(email). Check your inbox."
            showPasswordAlert = true
        } catch {
            alertMessage = "Could not send reset email. Please try again."
            showPasswordAlert = true
        }
    }

    private func exportData() {
        guard !isExporting else { return }
        isExporting = true
        Task {
            do {
                let userId = try await supabase.auth.session.user.id
                let tasksData = (try? await supabase
                    .from("maintenance_tasks").select().execute().data) ?? Data()
                let recordsData = (try? await supabase
                    .from("financial_records").select().execute().data) ?? Data()
                let docsData = (try? await supabase
                    .from("documents").select().execute().data) ?? Data()
                let contractorsData = (try? await supabase
                    .from("contractors").select().execute().data) ?? Data()

                let tasks = (try? JSONSerialization.jsonObject(with: tasksData)) as? [[String: Any]] ?? []
                let records = (try? JSONSerialization.jsonObject(with: recordsData)) as? [[String: Any]] ?? []
                let docs = (try? JSONSerialization.jsonObject(with: docsData)) as? [[String: Any]] ?? []
                let contractors = (try? JSONSerialization.jsonObject(with: contractorsData)) as? [[String: Any]] ?? []

                let export: [String: Any] = [
                    "exported_at": ISO8601DateFormatter().string(from: Date()),
                    "user_id": userId.uuidString,
                    "tasks": tasks,
                    "financial_records": records,
                    "documents": docs,
                    "contractors": contractors
                ]

                let data = try JSONSerialization.data(withJSONObject: export, options: .prettyPrinted)
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("prvhouse_export.json")
                try data.write(to: tmp)
                await MainActor.run {
                    isExporting = false
                    exportItem = ExportItem(url: tmp)
                }
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
            // Delete all user data (cascade via FK or explicit)
            let tables = ["maintenance_tasks", "financial_records", "documents",
                          "contractors", "profiles"]
            for table in tables {
                try? await supabase.from(table)
                    .delete()
                    .eq("user_id", value: userId.uuidString)
                    .execute()
            }
            try? await supabase.auth.signOut()
        } catch {
            try? await supabase.auth.signOut()
        }
        isDeletingAccount = false
    }
}

// MARK: - Helpers

struct ExportItem: Identifiable {
    let id = UUID()
    let url: URL
}

