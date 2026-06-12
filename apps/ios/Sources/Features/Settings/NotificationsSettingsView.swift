import SwiftUI
import UserNotifications

struct NotificationsSettingsView: View {
    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var taskReminders = true
    @State private var documentExpiry = true
    @State private var financialAlerts = true
    @State private var weeklyDigest = false
    @State private var showOpenSettings = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                permissionCard
                if authStatus == .authorized || authStatus == .provisional {
                    preferencesSection
                }
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.large)
        .task { await checkStatus() }
        .alert("Open Settings", isPresented: $showOpenSettings) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enable notifications in iOS Settings to receive alerts from PRVHouse.")
        }
    }

    // MARK: - Permission card

    private var permissionCard: some View {
        GlassCard {
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(statusColor.opacity(0.18))
                            .frame(width: 48, height: 48)
                        Image(systemName: statusIcon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(statusColor)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(statusSubtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                }

                if authStatus == .notDetermined {
                    Button {
                        Task { await requestPermission() }
                    } label: {
                        Text("Enable Notifications")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(.blue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else if authStatus == .denied {
                    Button { showOpenSettings = true } label: {
                        Text("Open iOS Settings")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(.orange, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ALERT TYPES")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
                .padding(.leading, 4)

            VStack(spacing: 0) {
                NotifToggleRow(
                    icon: "checklist",
                    color: .blue,
                    title: "Task Reminders",
                    subtitle: "Overdue & upcoming tasks",
                    value: $taskReminders
                )
                divider
                NotifToggleRow(
                    icon: "doc.badge.clock.fill",
                    color: .orange,
                    title: "Document Expiry",
                    subtitle: "30 days before expiration",
                    value: $documentExpiry
                )
                divider
                NotifToggleRow(
                    icon: "banknote.fill",
                    color: Color(red: 0.3, green: 0.85, blue: 0.5),
                    title: "Financial Alerts",
                    subtitle: "Rent due & large transactions",
                    value: $financialAlerts
                )
                divider
                NotifToggleRow(
                    icon: "newspaper.fill",
                    color: .purple,
                    title: "Weekly Digest",
                    subtitle: "Summary every Monday",
                    value: $weeklyDigest
                )
            }
            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.07), lineWidth: 0.5)
            )
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, 52)
    }

    // MARK: - Status helpers

    private var statusColor: Color {
        switch authStatus {
        case .authorized, .provisional: return Color(red: 0.3, green: 0.85, blue: 0.5)
        case .denied: return .orange
        default: return .blue
        }
    }

    private var statusIcon: String {
        switch authStatus {
        case .authorized, .provisional: return "bell.badge.fill"
        case .denied: return "bell.slash.fill"
        default: return "bell.fill"
        }
    }

    private var statusTitle: String {
        switch authStatus {
        case .authorized, .provisional: return "Notifications Enabled"
        case .denied: return "Notifications Blocked"
        default: return "Notifications Off"
        }
    }

    private var statusSubtitle: String {
        switch authStatus {
        case .authorized, .provisional: return "You'll receive alerts from PRVHouse"
        case .denied: return "Enable in iOS Settings to receive alerts"
        default: return "Tap below to enable alerts"
        }
    }

    // MARK: - Actions

    private func checkStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authStatus = settings.authorizationStatus
    }

    private func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            authStatus = granted ? .authorized : .denied
        } catch {
            print("[Notifications] permission error: \(error)")
        }
    }
}

// MARK: - Row

private struct NotifToggleRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    @Binding var value: Bool

    var body: some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
            Toggle("", isOn: $value)
                .labelsHidden()
                .tint(.blue)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
