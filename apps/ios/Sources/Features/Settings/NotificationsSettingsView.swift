import SwiftUI
import UserNotifications

struct NotificationsSettingsView: View {
    @EnvironmentObject private var scheduler: NotificationScheduler
    @EnvironmentObject private var taskService: TaskService
    @EnvironmentObject private var documentService: DocumentService

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
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Notificări")
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
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                } else if authStatus == .denied {
                    Button { showOpenSettings = true } label: {
                        Text("Open iOS Settings")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            group("SARCINI & DOCUMENTE") {
                NotifToggleRow(icon: "checklist", color: .blue,
                               title: "Memento sarcini",
                               subtitle: "Scadente azi, cu 3 zile înainte și restante",
                               value: bind(\.taskReminders, reschedule: true))
                divider
                NotifToggleRow(icon: "doc.badge.clock.fill", color: .orange,
                               title: "Expirare documente",
                               subtitle: "Alerte cu 30 și 7 zile înainte de expirare",
                               value: bind(\.documentExpiry, reschedule: true))
            }

            group("PROPRIETATE & FINANȚE") {
                NotifToggleRow(icon: "shield.lefthalf.filled", color: .teal,
                               title: "Garanții obiecte",
                               subtitle: "Garanții care expiră pentru obiectele din twin",
                               value: bind(\.warrantyAlerts))
                divider
                NotifToggleRow(icon: "shippingbox.fill", color: .indigo,
                               title: "Inventar & împrumuturi",
                               subtitle: "Memento returnare obiecte împrumutate",
                               value: bind(\.inventoryLoans))
                divider
                NotifToggleRow(icon: "banknote.fill", color: Color(red: 0.3, green: 0.85, blue: 0.5),
                               title: "Alerte financiare",
                               subtitle: "Chirii scadente & tranzacții mari",
                               value: bind(\.financialAlerts))
            }

            group("COMUNICARE") {
                NotifToggleRow(icon: "bubble.left.and.bubble.right.fill", color: .blue,
                               title: "Chat familie",
                               subtitle: "Mesaje noi în chatul familiei",
                               value: bind(\.chatMessages))
                divider
                NotifToggleRow(icon: "at", color: .purple,
                               title: "Mențiuni",
                               subtitle: "Când ești menționat cu @",
                               value: bind(\.mentions))
            }

            group("AUTOMATIZĂRI") {
                NotifToggleRow(icon: "gearshape.2.fill", color: .yellow,
                               title: "Automatizări",
                               subtitle: "Alerte de la automatizările proprietății",
                               value: bind(\.automationAlerts))
            }

            group("REZUMAT") {
                NotifToggleRow(icon: "newspaper.fill", color: .purple,
                               title: "Rezumat săptămânal",
                               subtitle: "În fiecare luni la 9:00",
                               value: bind(\.weeklyDigest, reschedule: true))
            }

            Text("Notificările sunt programate local pe dispozitiv și se declanșează chiar și când aplicația este închisă.")
                .font(.caption)
                .foregroundStyle(Color.primary.opacity(0.3))
                .padding(.leading, 4)
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.35))
                .padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
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
                .tint(.tint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
