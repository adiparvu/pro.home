import SwiftUI
import UserNotifications
import UIKit

struct NotificationsSettingsView: View {
    @Environment(NotificationScheduler.self) private var scheduler
    @Environment(TaskService.self) private var taskService
    @Environment(DocumentService.self) private var documentService
    @Environment(ApplianceService.self) private var applianceService
    @Environment(FamilyService.self) private var familyService
    @Environment(FinancialService.self) private var financialService
    @Environment(PlantService.self) private var plantService

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
                deadlineRow(icon: "checklist", color: .blue,
                            title: "Task reminders",
                            subtitle: "notif_sub_tasks",
                            enabled: bind(\.taskReminders, reschedule: true),
                            lead: leadBind(\.taskLeadDays),
                            isOn: scheduler.taskReminders)
                divider
                deadlineRow(icon: "doc.badge.clock.fill", color: .orange,
                            title: "Document expiry",
                            subtitle: "notif_sub_documents",
                            enabled: bind(\.documentExpiry, reschedule: true),
                            lead: leadBind(\.documentLeadDays),
                            isOn: scheduler.documentExpiry)
            }

            group("PROPERTY & FINANCES") {
                deadlineRow(icon: "shield.lefthalf.filled", color: .teal,
                            title: "Object warranties",
                            subtitle: "notif_sub_warranties",
                            enabled: bind(\.warrantyAlerts, reschedule: true),
                            lead: leadBind(\.warrantyLeadDays),
                            isOn: scheduler.warrantyAlerts)
                divider
                NotifToggleRow(icon: "shippingbox.fill", color: .indigo,
                               title: "Inventory & loans",
                               subtitle: "Reminder to return borrowed items",
                               value: bind(\.inventoryLoans))
                divider
                deadlineRow(icon: "banknote.fill", color: Color.brandSuccess,
                            title: "Financial alerts",
                            subtitle: "notif_sub_financial",
                            enabled: bind(\.financialAlerts, reschedule: true),
                            lead: leadBind(\.financialLeadDays),
                            isOn: scheduler.financialAlerts)
                divider
                deadlineRow(icon: "key.fill", color: Color.brandSkyBlue,
                            title: "notif_leases_title",
                            subtitle: "notif_sub_leases",
                            enabled: bind(\.leaseAlerts, reschedule: true),
                            lead: leadBind(\.leaseLeadDays),
                            isOn: scheduler.leaseAlerts)
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

    /// A deadline category: its on/off toggle, and — while on — a "notify N
    /// days before" picker. Both changes re-run the scheduler so the effect is
    /// immediate, matching what the calendar shows.
    @ViewBuilder
    private func deadlineRow(icon: String, color: Color,
                             title: LocalizedStringKey, subtitle: LocalizedStringKey,
                             enabled: Binding<Bool>, lead: Binding<Int>, isOn: Bool) -> some View {
        VStack(spacing: 0) {
            NotifToggleRow(icon: icon, color: color, title: title, subtitle: subtitle, value: enabled)
            if isOn {
                leadDivider
                NotifLeadRow(lead: lead)
            }
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

    /// A lead-time picker binding — every change reschedules so the new lead
    /// takes effect right away.
    private func leadBind(_ keyPath: ReferenceWritableKeyPath<NotificationScheduler, Int>) -> Binding<Int> {
        Binding(
            get: { scheduler[keyPath: keyPath] },
            set: { newVal in
                scheduler[keyPath: keyPath] = newVal
                HapticFeedback.selection()
                reschedule()
            }
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, 52)
    }

    /// Tighter divider between a toggle and its own lead-time picker.
    private var leadDivider: some View {
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
        let agenda = HouseAgenda.upcomingYear(
            tasks: taskService.tasks, documents: documentService.documents,
            appliances: applianceService.appliances, members: familyService.members,
            financial: financialService.records, plants: plantService.plants,
            leases: Array(familyService.leases.values))
        Task { await scheduler.reschedule(agenda: agenda) }
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

// MARK: - Lead-time picker row

/// "Notify … days before" — a compact Menu that reads like an inline value,
/// aligned with the toggle above it. Options come from the scheduler so the
/// list stays in one place.
private struct NotifLeadRow: View {
    @Binding var lead: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.badge")
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.35))
                .frame(width: 40, alignment: .center)
            Text("notif_notify_before")
                .font(AppFont.scaled(13))
                .foregroundStyle(Color.primary.opacity(0.5))
            Spacer()
            Menu {
                ForEach(NotificationScheduler.leadOptions, id: \.self) { days in
                    Button {
                        lead = days
                    } label: {
                        if days == lead { Label(daysLabel(days), systemImage: "checkmark") }
                        else { Text(daysLabel(days)) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(daysLabel(lead))
                        .font(AppFont.scaled(13, weight: .medium))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(AppFont.scaled(10, weight: .semibold))
                }
                .foregroundStyle(Color.brandPrimaryBlue)
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, 5)
                .background(Color.brandPrimaryBlue.opacity(0.12),
                            in: Capsule())
            }
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, 8)
    }

    private func daysLabel(_ days: Int) -> String {
        String(format: String(localized: "notif_days_count"), days)
    }
}
