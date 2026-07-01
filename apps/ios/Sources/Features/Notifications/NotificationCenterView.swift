import SwiftUI

struct AppNotification: Identifiable, Codable {
    let id: UUID
    var title: String
    var body: String?
    var priority: String
    var status: String
    var module: String?
    var actionUrl: String?
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, body, priority, status, module
        case actionUrl  = "action_url"
        case createdAt  = "created_at"
    }

    var isUnread: Bool { status == "unread" }

    var priorityColor: Color {
        switch priority {
        case "critical": return .red
        case "high":     return .orange
        case "normal":   return .blue
        default:         return Color.primary.opacity(0.4)
        }
    }

    var moduleIcon: String {
        switch module ?? "" {
        case "maintenance": return "wrench.fill"
        case "document":    return "doc.fill"
        case "finance":     return "creditcard.fill"
        case "security":    return "lock.shield.fill"
        case "garden":      return "leaf.fill"
        case "family":      return "person.2.fill"
        default:            return "bell.fill"
        }
    }

    var timeDisplay: String {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        guard let date = f1.date(from: createdAt) ?? f2.date(from: createdAt) else { return "" }
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return String(localized: "Just now") }
        if diff < 3600 { return String(localized: "\(Int(diff / 60))m ago") }
        if diff < 86400 { return String(localized: "\(Int(diff / 3600))h ago") }
        let df = DateFormatter(); df.dateStyle = .short; df.timeStyle = .none
        return df.string(from: date)
    }
}

struct NotificationCenterView: View {
    @Environment(AuthService.self) private var auth
    @State private var notifications: [AppNotification] = []
    @State private var isLoading = false
    @State private var errorMsg: String?

    var unreadCount: Int { notifications.filter(\.isUnread).count }

    var body: some View {
        Group {
            if isLoading {
                VStack { Spacer(); ProgressView().tint(.primary); Spacer() }
            } else if notifications.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if unreadCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Mark all read") { Task { await markAllRead() } }
                        .font(.system(size: 14))
                }
            }
        }
        .task { await load() }
    }

    private var list: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 10) {
                ForEach(notifications) { notif in
                    NotificationRow(notification: notif)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await dismiss(notif) }
                            } label: {
                                Label("Dismiss", systemImage: "xmark")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if notif.isUnread {
                                Button {
                                    Task { await markRead(notif) }
                                } label: {
                                    Label("Read", systemImage: "checkmark")
                                }
                                .tint(.blue)
                            }
                        }
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.xxs)
            .padding(.bottom, 110)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bell.slash")
                .font(.system(size: 48))
                .foregroundStyle(Color.primary.opacity(0.18))
            Text("No notifications")
                .font(AppFont.title3)
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            Text("You're all caught up!")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.3))
            Spacer()
        }
    }

    private func load() async {
        guard let uid = auth.session?.user.id else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            notifications = try await supabase
                .from("notifications")
                .select()
                .eq("user_id", value: uid.uuidString)
                .neq("status", value: "dismissed")
                .order("created_at", ascending: false)
                .limit(60)
                .execute()
                .value
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    private func markRead(_ notif: AppNotification) async {
        guard let idx = notifications.firstIndex(where: { $0.id == notif.id }) else { return }
        notifications[idx].status = "read"
        try? await supabase
            .from("notifications")
            .update(["status": "read"])
            .eq("id", value: notif.id.uuidString)
            .execute()
    }

    private func markAllRead() async {
        guard let uid = auth.session?.user.id else { return }
        for i in notifications.indices { notifications[i].status = "read" }
        try? await supabase
            .from("notifications")
            .update(["status": "read"])
            .eq("user_id", value: uid.uuidString)
            .eq("status", value: "unread")
            .execute()
    }

    private func dismiss(_ notif: AppNotification) async {
        notifications.removeAll { $0.id == notif.id }
        try? await supabase
            .from("notifications")
            .update(["status": "dismissed"])
            .eq("id", value: notif.id.uuidString)
            .execute()
    }
}

private struct NotificationRow: View {
    let notification: AppNotification

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(notification.priorityColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: notification.moduleIcon)
                    .font(AppFont.headline)
                    .foregroundStyle(notification.priorityColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(notification.title)
                        .font(.system(size: 14, weight: notification.isUnread ? .semibold : .regular))
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                    Spacer()
                    Text(LocalizedStringKey(notification.timeDisplay))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.38))
                }
                if let body = notification.body, !body.isEmpty {
                    Text(body)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .lineLimit(2)
                }
            }

            if notification.isUnread {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 7, height: 7)
                    .padding(.top, 5)
            }
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
        .background(
            notification.isUnread
                ? Color.primary.opacity(AppOpacity.hairline)
                : Color.primary.opacity(0.03),
            in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .strokeBorder(Color.primary.opacity(AppOpacity.hairline), lineWidth: 0.5)
        )
    }
}
