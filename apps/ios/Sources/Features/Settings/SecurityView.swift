import SwiftUI
import LocalAuthentication
import Supabase

struct SecurityView: View {
    @EnvironmentObject var auth: AuthService
    @AppStorage("prvio.biometrics") var biometricsEnabled = false
    @AppStorage("prvio.lockMode") private var lockModeEnabled = false
    @State var biometricType: LABiometryType = .none
    @State private var showDeleteConfirm = false
    @State var showPasswordAlert = false
    @State var passwordResetSent = false
    @State var alertMessage = ""
    @State private var showActiveSessions = false
    @State var exportItem: ExportItem?
    @State var isExporting = false
    @State var isDeletingAccount = false
    @State private var showAutoLockPicker = false
    @AppStorage("prvio.autoLockMinutes") private var autoLockMinutes = 5
    @State private var showTOTPEnroll = false
    @State var totpFactorId: String?
    @State private var showRemoveTOTP = false
    @State private var showBackupCodes = false
    @State private var showAuditLog = false
    @State private var showTrustedPersons = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                PageHeader(titleKey: "Security")
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
        .sheet(isPresented: $showBackupCodes) { BackupCodesView() }
        .sheet(isPresented: $showAuditLog) { AuditLogView() }
        .sheet(isPresented: $showTrustedPersons) { TrustedPersonsView() }
        .confirmationDialog("Auto-lock", isPresented: $showAutoLockPicker, titleVisibility: .visible) {
            Button("Immediately") { autoLockMinutes = -1 }
            Button("30 seconds") { autoLockMinutes = -2 }
            Button("1 minute") { autoLockMinutes = 1 }
            Button("5 minutes") { autoLockMinutes = 5 }
            Button("15 minutes") { autoLockMinutes = 15 }
            Button("30 minutes") { autoLockMinutes = 30 }
            Button("1 hour") { autoLockMinutes = 60 }
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
            divider
            Button { showBackupCodes = true } label: {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "key.horizontal.fill", color: .teal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Backup codes")
                            .font(.system(size: 15)).foregroundStyle(.primary)
                        Text("Emergency access codes for account recovery")
                            .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.4))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.primary.opacity(0.28))
                }
                .padding(.horizontal, 14).padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Sessions

    private var sessionsSection: some View {
        secGroup(title: "Sessions", footer: "See all devices and sessions that have accessed your account. You can check active sessions, remove trusted devices, or use \"Sign out of all devices\" to end all sessions.") {
            Button { showActiveSessions = true } label: {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "macbook.and.iphone", color: .blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Active sessions")
                            .font(.system(size: 15)).foregroundStyle(.primary)
                        Text(UIDevice.current.model)
                            .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.4))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.primary.opacity(0.28))
                }
                .padding(.horizontal, 14).padding(.vertical, 13)
            }
            .buttonStyle(.plain)

            divider

            Button { showTrustedPersons = true } label: {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "person.badge.shield.checkmark.fill", color: .green)
                    Text("Trusted persons")
                        .font(.system(size: 15)).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.primary.opacity(0.28))
                }
                .padding(.horizontal, 14).padding(.vertical, 13)
            }
            .buttonStyle(.plain)

            divider

            Button { showAuditLog = true } label: {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "list.clipboard.fill", color: .indigo)
                    Text("Activity log")
                        .font(.system(size: 15)).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.primary.opacity(0.28))
                }
                .padding(.horizontal, 14).padding(.vertical, 13)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Advanced Security

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

    // MARK: - Biometrics

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
                        .labelsHidden().tint(.accentColor)
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
                        Text(autoLockDescription)
                            .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.4))
                    }
                    Spacer()
                    Text(autoLockLabel)
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

    private var autoLockLabel: String {
        switch autoLockMinutes {
        case -1: return "Immediately"
        case -2: return "30 sec"
        case 0:  return "Never"
        case 1:  return "1 min"
        case 60: return "1 hour"
        default: return "\(autoLockMinutes) min"
        }
    }

    private var autoLockDescription: String {
        switch autoLockMinutes {
        case -1: return "Locks every time the app backgrounds"
        case -2: return "Locks after 30 seconds of inactivity"
        case 0:  return "Never auto-locks"
        case 60: return "Locks after 1 hour of inactivity"
        default: return "Locks after \(autoLockMinutes) min of inactivity"
        }
    }
}
