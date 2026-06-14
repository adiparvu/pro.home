import SwiftUI
import UserNotifications

struct NotificationsSettingsView: View {
    @EnvironmentObject private var scheduler: NotificationScheduler
    @EnvironmentObject private var taskService: TaskService
    @EnvironmentObject private var documentService: DocumentService

    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var showOpenSettings = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Notificări")
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
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await checkStatus() }
        .alert("Open Settings", isPresented: $showOpenSettings) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enable notifications in iOS Settings to receive alerts from PRVIO.")
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
                            .foregroundStyle(.primary)
                        Text(statusSubtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.primary.opacity(0.5))
                    }
                    Spacer()
                }

                if authStatus == .notDetermined {
                    Button {
                        Task { await requestPermission() }
                    } label: {
                        Text("Enable Notifications")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(.blue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else if authStatus == .denied {
                    Button { showOpenSettings = true } label: {
                        Text("Open iOS Settings")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
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
                .foregroundStyle(Color.primary.opacity(0.35))
                .padding(.leading, 4)

            VStack(spacing: 0) {
                NotifToggleRow(
                    icon: "checklist",
                    color: .blue,
                    title: "Task Reminders",
                    subtitle: "Due today & 3 days ahead, overdue alerts",
                    value: Binding(
                        get: { scheduler.taskReminders },
                        set: { scheduler.taskReminders = $0; reschedule() }
                    )
                )
                divider
                NotifToggleRow(
                    icon: "doc.badge.clock.fill",
                    color: .orange,
                    title: "Document Expiry",
                    subtitle: "Alerts at 30 days and 7 days before expiry",
                    value: Binding(
                        get: { scheduler.documentExpiry },
                        set: { scheduler.documentExpiry = $0; reschedule() }
                    )
                )
                divider
                NotifToggleRow(
                    icon: "banknote.fill",
                    color: Color(red: 0.3, green: 0.85, blue: 0.5),
                    title: "Financial Alerts",
                    subtitle: "Rent due & large transactions",
                    value: Binding(
                        get: { scheduler.financialAlerts },
                        set: { scheduler.financialAlerts = $0 }
                    )
                )
                divider
                NotifToggleRow(
                    icon: "newspaper.fill",
                    color: .purple,
                    title: "Weekly Digest",
                    subtitle: "Every Monday at 9:00 AM",
                    value: Binding(
                        get: { scheduler.weeklyDigest },
                        set: { scheduler.weeklyDigest = $0; reschedule() }
                    )
                )
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
            )

            Text("Notifications are scheduled locally on your device and fire even when the app is closed.")
                .font(.caption)
                .foregroundStyle(Color.primary.opacity(0.3))
                .padding(.leading, 4)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.05))
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
        case .authorized, .provisional: return "Alerts are scheduled on your device"
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
            if granted { reschedule() }
        } catch {
            print("[Notifications] permission error: \(error)")
        }
    }

    private func reschedule() {
        Task {
            await scheduler.reschedule(
                tasks: taskService.tasks,
                documents: documentService.documents
            )
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
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.4))
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
