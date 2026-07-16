import SwiftUI
import LocalAuthentication
import Supabase

struct SecurityView: View {
    @Environment(AuthService.self) var auth
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
    @State private var sectionLock = SectionLockManager.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                checkupSection
                mfaSection
                sessionsSection
                advancedSection
                biometricSection
                sectionLocksSection
                dataSection
                Spacer(minLength: 100)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Security")
        .navigationBarTitleDisplayMode(.large)
        .task { checkBiometrics() }
        .task { await loadFactors() }
        .task { await AccountSecurityService.shared.refreshBackupCodeCount() }
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

    // MARK: - Security checkup
    //
    // A real score from real signals only — every point maps to a switch the
    // user can actually flip on this page. Nothing is estimated or guessed.

    private struct CheckupSignal {
        let passed: Bool
        let weight: Int
        let recommendation: LocalizedStringKey
    }

    @AppStorage("prvio.trustedContact.name") private var trustedContactName = ""

    private var checkupSignals: [CheckupSignal] {
        [
            .init(passed: totpFactorId != nil, weight: 30,
                  recommendation: "Turn on the authenticator app (two-step sign-in)"),
            .init(passed: (AccountSecurityService.shared.unusedBackupCodes ?? 0) > 0, weight: 15,
                  recommendation: "Generate backup codes for your account"),
            .init(passed: biometricsEnabled, weight: 20,
                  recommendation: "Require Face ID to open PRVIO"),
            .init(passed: autoLockMinutes != 0, weight: 10,
                  recommendation: "Set an auto-lock interval"),
            .init(passed: !sectionLock.protectedSections.isEmpty, weight: 10,
                  recommendation: "Lock at least one sensitive section"),
            .init(passed: !trustedContactName.isEmpty, weight: 15,
                  recommendation: "Add an emergency trusted contact"),
        ]
    }

    private var checkupScore: Int {
        checkupSignals.filter(\.passed).reduce(0) { $0 + $1.weight }
    }

    private var checkupColor: Color {
        switch checkupScore {
        case ..<50:  return .brandDanger
        case ..<80:  return .brandWarning
        default:     return .brandSuccess
        }
    }

    private var checkupSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.base) {
            HStack(spacing: AppSpacing.lg) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(AppOpacity.hairline), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: CGFloat(checkupScore) / 100)
                        .stroke(checkupColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(verbatim: "\(checkupScore)")
                        .font(AppFont.scaled(20, weight: .bold))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Security checkup")
                        .font(AppFont.headline)
                        .foregroundStyle(.primary)
                    Text(checkupScore == 100
                         ? "Everything on this page is switched on."
                         : "Each recommendation below maps to a control on this page.")
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(0.45))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.top, AppSpacing.base)

            let missing = checkupSignals.filter { !$0.passed }.prefix(3)
            if !missing.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    ForEach(Array(missing.enumerated()), id: \.offset) { _, signal in
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(AppFont.footnote)
                                .foregroundStyle(checkupColor)
                                .symbolRenderingMode(.hierarchical)
                            Text(signal.recommendation)
                                .font(AppFont.scaled(13))
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.base)
            }
            Color.clear.frame(height: AppSpacing.xs)
        }
        .liquidGlass(cornerRadius: AppRadius.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Security checkup"))
        .accessibilityValue(Text(verbatim: "\(checkupScore)/100"))
    }

    // MARK: - MFA

    private var mfaSection: some View {
        secGroup(title: "Multi-factor authentication (MFA)", footer: "Requires an additional security check at sign-in. If you can't pass it, a one-time backup code unlocks the app.") {
            Button {
                if totpFactorId != nil { showRemoveTOTP = true } else { showTOTPEnroll = true }
            } label: {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "apps.iphone", color: .indigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Authenticator app")
                            .font(AppFont.scaled(15)).foregroundStyle(.primary)
                        Text("TOTP codes (Google Authenticator, 1Password…)")
                            .font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(0.4))
                    }
                    Spacer()
                    if totpFactorId != nil {
                        Text("Enabled").font(AppFont.captionEmphasis)
                            .foregroundStyle(Color.brandSuccess)
                    } else {
                        Text("Disabled").font(AppFont.scaled(13)).foregroundStyle(Color.primary.opacity(0.38))
                    }
                    Image(systemName: "chevron.right")
                        .font(AppFont.caption).foregroundStyle(Color.primary.opacity(0.28))
                }
                .padding(.horizontal, AppSpacing.base).padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            divider
            statusRow(icon: "message.fill", color: Color.brandSuccess, title: "Text messages", status: "Coming soon")
            divider
            Button { showBackupCodes = true } label: {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "key.horizontal.fill", color: .teal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Backup codes")
                            .font(AppFont.scaled(15)).foregroundStyle(.primary)
                        Text("One-time codes that unlock two-step sign-in")
                            .font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(0.4))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AppFont.caption).foregroundStyle(Color.primary.opacity(0.28))
                }
                .padding(.horizontal, AppSpacing.base).padding(.vertical, 13)
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
                            .font(AppFont.scaled(15)).foregroundStyle(.primary)
                        Text(UIDevice.current.model)
                            .font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(0.4))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AppFont.caption).foregroundStyle(Color.primary.opacity(0.28))
                }
                .padding(.horizontal, AppSpacing.base).padding(.vertical, 13)
            }
            .buttonStyle(.plain)

            divider

            Button { showTrustedPersons = true } label: {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "person.badge.shield.checkmark.fill", color: .green)
                    Text("Trusted persons")
                        .font(AppFont.scaled(15)).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AppFont.caption).foregroundStyle(Color.primary.opacity(0.28))
                }
                .padding(.horizontal, AppSpacing.base).padding(.vertical, 13)
            }
            .buttonStyle(.plain)

            divider

            Button { showAuditLog = true } label: {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "list.clipboard.fill", color: .indigo)
                    Text("Activity log")
                        .font(AppFont.scaled(15)).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AppFont.caption).foregroundStyle(Color.primary.opacity(0.28))
                }
                .padding(.horizontal, AppSpacing.base).padding(.vertical, 13)
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
                            .font(AppFont.scaled(15)).foregroundStyle(.primary)
                        Text("Change password or email")
                            .font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(0.4))
                    }
                    Spacer()
                    if passwordResetSent {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(AppFont.caption).foregroundStyle(Color.primary.opacity(0.28))
                    }
                }
                .padding(.horizontal, AppSpacing.base).padding(.vertical, 13)
            }
            .buttonStyle(.plain)

            divider

            HStack(spacing: 12) {
                ColoredIconBadge(icon: "lock.shield.fill", color: .purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lockdown mode")
                        .font(AppFont.scaled(15)).foregroundStyle(.primary)
                    // Honest subtitle: this is what the toggle actually does
                    // (AppLockManager forces the lock on every background).
                    Text("Locks PRVIO every time you leave the app")
                        .font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(0.4))
                }
                Spacer()
                Toggle("", isOn: $lockModeEnabled)
                    .labelsHidden().tint(.purple)
            }
            .padding(.horizontal, AppSpacing.base).padding(.vertical, 13)
        }
    }

    // MARK: - Biometrics

    private var biometricSection: some View {
        secGroup(title: "PRVIO") {
            if biometricType != .none {
                HStack(spacing: 12) {
                    ColoredIconBadge(
                        icon: biometricType == .faceID ? "faceid" : "touchid",
                        color: Color.brandSuccess
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey(biometricType == .faceID ? "Require Face ID" : "Require Touch ID"))
                            .font(AppFont.scaled(15)).foregroundStyle(.primary)
                        Text("Face ID or passcode to access PRVIO")
                            .font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(0.4))
                    }
                    Spacer()
                    Toggle("", isOn: $biometricsEnabled)
                        .labelsHidden().tint(.accentColor)
                        .onChange(of: biometricsEnabled) { _, newVal in
                            if newVal { Task { await authenticateBiometric() } }
                        }
                }
                .padding(.horizontal, AppSpacing.base).padding(.vertical, 13)

                divider
            }

            Button { showAutoLockPicker = true } label: {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "timer", color: .cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-lock")
                            .font(AppFont.scaled(15)).foregroundStyle(.primary)
                        Text(LocalizedStringKey(autoLockDescription))
                            .font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(0.4))
                    }
                    Spacer()
                    Text(autoLockLabel)
                        .font(AppFont.scaled(14)).foregroundStyle(Color.primary.opacity(0.38))
                    Image(systemName: "chevron.right")
                        .font(AppFont.caption).foregroundStyle(Color.primary.opacity(0.28))
                }
                .padding(.horizontal, AppSpacing.base).padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Locked sections

    private var sectionLocksSection: some View {
        secGroup(
            title: "Locked sections",
            footer: "Require Face ID, Touch ID, or your passcode before these sections open. They re-lock every time you leave the app."
        ) {
            let sections = SectionLockManager.Section.allCases
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: section.icon, color: section.color)
                    Text(section.titleKey)
                        .font(AppFont.scaled(15)).foregroundStyle(.primary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { sectionLock.isProtected(section) },
                        set: { sectionLock.setProtected(section, $0) }
                    ))
                    .labelsHidden().tint(.accentColor)
                }
                .padding(.horizontal, AppSpacing.base).padding(.vertical, 13)

                if index < sections.count - 1 { divider }
            }
        }
    }

    // MARK: - Data & Privacy

    private var dataSection: some View {
        secGroup(title: "Data & Privacy") {
            Button { exportData() } label: {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "square.and.arrow.up.fill", color: .cyan)
                    Text("Export my data")
                        .font(AppFont.scaled(15)).foregroundStyle(.primary)
                    Spacer()
                    if isExporting {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(AppFont.caption).foregroundStyle(Color.primary.opacity(0.28))
                    }
                }
                .padding(.horizontal, AppSpacing.base).padding(.vertical, 13)
            }
            .buttonStyle(.plain)

            divider

            Button { showDeleteConfirm = true } label: {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "trash.fill", color: .red)
                    Text("Delete account")
                        .font(AppFont.scaled(15)).foregroundStyle(.red)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AppFont.caption).foregroundStyle(Color.primary.opacity(0.28))
                }
                .padding(.horizontal, AppSpacing.base).padding(.vertical, 13)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func secGroup<Content: View>(title: LocalizedStringKey, footer: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppFont.captionStrong)
                .foregroundStyle(.secondary)
                .padding(.leading, AppSpacing.sm)
                .textCase(.uppercase)

            VStack(spacing: 0) { content() }
                .liquidGlass(cornerRadius: AppRadius.xl)

            if let footer {
                Text(footer)
                    .font(AppFont.scaled(12))
                    .foregroundStyle(Color.primary.opacity(0.38))
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.top, 2)
            }
        }
    }

    // LocalizedStringKey, NOT String — plain String parameters rendered the
    // literals verbatim and silently skipped the Romanian translations that
    // already existed for them (IMG_8534).
    private func statusRow(icon: String, color: Color, title: LocalizedStringKey, status: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color)
            Text(title)
                .font(AppFont.scaled(15)).foregroundStyle(.primary)
            Spacer()
            Text(status)
                .font(AppFont.scaled(13)).foregroundStyle(Color.primary.opacity(0.38))
        }
        .padding(.horizontal, AppSpacing.base).padding(.vertical, 13)
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(AppOpacity.hairline)).frame(height: 0.4).padding(.leading, 52)
    }

    private var autoLockLabel: String {
        switch autoLockMinutes {
        case -1: return String(localized: "Immediately")
        case -2: return String(localized: "30 sec")
        case 0:  return String(localized: "Never")
        case 1:  return String(localized: "1 min")
        case 60: return String(localized: "1 hour")
        default: return String(localized: "\(autoLockMinutes) min")
        }
    }

    private var autoLockDescription: String {
        switch autoLockMinutes {
        case -1: return String(localized: "Locks every time the app backgrounds")
        case -2: return String(localized: "Locks after 30 seconds of inactivity")
        case 0:  return String(localized: "Never auto-locks")
        case 60: return String(localized: "Locks after 1 hour of inactivity")
        default: return String(localized: "Locks after \(autoLockMinutes) min of inactivity")
        }
    }
}
