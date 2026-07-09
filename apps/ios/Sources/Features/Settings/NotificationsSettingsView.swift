import SwiftUI
import UserNotifications
import UIKit

struct NotificationsSettingsView: View {
    @Environment(NotificationScheduler.self) private var scheduler
    @Environment(TaskService.self) private var taskService
    @Environment(DocumentService.self) private var documentService

    @State private var authStatus: UNAuthorizationStatus = .notDetermined
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
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
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
            Text("Enable notifications in iOS Settings to receive alerts from PRVIO.")
        }
    }

    // MARK: - Permission card

    private var permissionCard: some View {
        GlassCard {
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    Image(systemName: statusIcon)
                        .font(AppFont.scaled(20, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .frame(width: 48, height: 48)
                        .glassRoundedRect(AppRadius.md)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusTitle)
                            .font(AppFont.subheadline)
                            .foregroundStyle(.primary)
                        Text(statusSubtitle)
                            .font(AppFont.scaled(12))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    }
                    Spacer()
                }

                if authStatus == .notDetermined {
                    Button {
                        Task { await requestPermission() }
                    } label: {
                        Text("Enable Notifications")
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppSpacing.md)
                            .glassRoundedRect(12)
                    }
                    .buttonStyle(.plain)
                } else if authStatus == .denied {
                    Button { showOpenSettings = true } label: {
                        Text("Open iOS Settings")
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppSpacing.md)
                            .glassRoundedRect(12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            group("TASKS & DOCUMENTS") {
                NotifToggleRow(icon: "checklist", color: .blue,
                               title: "Task reminders",
                               subtitle: "Due today, 3 days ahead and overdue",
                               value: bind(\.taskReminders, reschedule: true))
                divider
                NotifToggleRow(icon: "doc.badge.clock.fill", color: .orange,
                               title: "Document expiry",
                               subtitle: "Alerts 30 and 7 days before expiry",
                               value: bind(\.documentExpiry, reschedule: true))
            }

            group("PROPERTY & FINANCES") {
                NotifToggleRow(icon: "shield.lefthalf.filled", color: .teal,
                               title: "Object warranties",
                               subtitle: "Expiring warranties for objects in the twin",
                               value: bind(\.warrantyAlerts))
                divider
                NotifToggleRow(icon: "shippingbox.fill", color: .indigo,
                               title: "Inventory & loans",
                               subtitle: "Reminder to return borrowed items",
                               value: bind(\.inventoryLoans))
                divider
                NotifToggleRow(icon: "banknote.fill", color: Color.brandSuccess,
                               title: "Financial alerts",
                               subtitle: "Upcoming rents & large transactions",
                               value: bind(\.financialAlerts))
            }

            group("COMMUNICATION") {
                NotifToggleRow(icon: "bubble.left.and.bubble.right.fill", color: .blue,
                               title: "Chat",
                               subtitle: "New messages in chat",
                               value: bind(\.chatMessages))
                divider
                NotifToggleRow(icon: "at", color: .purple,
                               title: "Mentions",
                               subtitle: "When you are mentioned with @",
                               value: bind(\.mentions))
            }

            group("AUTOMATIONS") {
                NotifToggleRow(icon: "gearshape.2.fill", color: .yellow,
                               title: "Automations",
                               subtitle: "Alerts from property automations",
                               value: bind(\.automationAlerts))
            }

            group("SUMMARY") {
                NotifToggleRow(icon: "newspaper.fill", color: .purple,
                               title: "Weekly summary",
                               subtitle: "Every Monday at 9:00",
                               value: bind(\.weeklyDigest, reschedule: true))
            }

            Text("Notifications are scheduled locally on the device and fire even when the app is closed.")
                .font(.caption)
                .foregroundStyle(Color.primary.opacity(0.3))
                .padding(.leading, AppSpacing.xxs)
        }
    }

    private func group<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(AppFont.label)
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.leading, AppSpacing.xxs)
            VStack(spacing: 0) { content() }
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
        }
    }

    private func bind(_ keyPath: ReferenceWritableKeyPath<NotificationScheduler, Bool>, reschedule doReschedule: Bool = false) -> Binding<Bool> {
        Binding(
            get: { scheduler[keyPath: keyPath] },
            set: { newVal in
                scheduler[keyPath: keyPath] = newVal
                HapticFeedback.selection()
                if doReschedule { reschedule() }
            }
        )
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
        case .authorized, .provisional: return Color.brandSuccess
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

    private var statusTitle: LocalizedStringKey {
        switch authStatus {
        case .authorized, .provisional: return "Notifications Enabled"
        case .denied: return "Notifications Blocked"
        default: return "Notifications Off"
        }
    }

    private var statusSubtitle: LocalizedStringKey {
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
            if granted {
                reschedule()
                // Now that the user opted in, register for APNs push too.
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            #if DEBUG
            debugLog("[Notifications] permission error: \(error)")
            #endif
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
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @Binding var value: Bool

    var body: some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.scaled(15))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(AppFont.scaled(12))
                    .foregroundStyle(Color.primary.opacity(0.4))
            }
            Spacer()
            Toggle("", isOn: $value)
                .labelsHidden()
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
    }
}
