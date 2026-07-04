import SwiftUI
import Observation
import Supabase

// MARK: - Model

struct AppNotification: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var body: String?
    var priority: String
    var status: String
    var module: String?
    var actionUrl: String?
    var resourceType: String?
    var resourceId: UUID?
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, body, priority, status, module
        case actionUrl    = "action_url"
        case resourceType = "resource_type"
        case resourceId   = "resource_id"
        case createdAt    = "created_at"
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

    var date: Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f1.date(from: createdAt) ?? f2.date(from: createdAt)
    }

    var timeDisplay: String {
        guard let date else { return "" }
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return String(localized: "Just now") }
        if diff < 3600 { return String(localized: "\(Int(diff / 60))m ago") }
        if diff < 86400 { return String(localized: "\(Int(diff / 3600))h ago") }
        let df = DateFormatter(); df.dateStyle = .short; df.timeStyle = .short
        return df.string(from: date)
    }
}

// MARK: - Category metadata
//
// Categories derive from the `module` column, so any module a future feature
// starts writing shows up as its own filter chip automatically — unknown
// modules get a generic bell + their raw name instead of being hidden.

struct NotificationCategory: Identifiable, Hashable {
    let module: String
    let label: LocalizedStringKey
    let icon: String
    let color: Color

    var id: String { module }

    // LocalizedStringKey isn't Hashable, so synthesis can't be used — identity
    // is the module slug alone.
    static func == (lhs: NotificationCategory, rhs: NotificationCategory) -> Bool {
        lhs.module == rhs.module
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(module)
    }

    static func forModule(_ module: String?) -> NotificationCategory {
        let m = module ?? "system"
        if let known = known[m] { return known }
        return NotificationCategory(module: m, label: LocalizedStringKey(m.capitalized),
                                    icon: "bell.fill", color: .blue)
    }

    private static let known: [String: NotificationCategory] = [
        "chat":        .init(module: "chat", label: "Chat",
                             icon: "bubble.left.and.bubble.right.fill", color: .blue),
        "maintenance": .init(module: "maintenance", label: "Tasks",
                             icon: "wrench.fill", color: .orange),
        "garden":      .init(module: "garden", label: "Garden",
                             icon: "leaf.fill", color: Color(red: 0.15, green: 0.80, blue: 0.40)),
        "documents":   .init(module: "documents", label: "Documents",
                             icon: "doc.fill", color: .orange),
        "document":    .init(module: "document", label: "Documents",
                             icon: "doc.fill", color: .orange),
        "finance":     .init(module: "finance", label: "Finances",
                             icon: "creditcard.fill", color: Color(red: 0.20, green: 0.78, blue: 0.35)),
        "inventory":   .init(module: "inventory", label: "Inventory",
                             icon: "archivebox.fill", color: .brown),
        "security":    .init(module: "security", label: "Security",
                             icon: "lock.shield.fill", color: .red),
        "family":      .init(module: "family", label: "Family",
                             icon: "person.2.fill", color: .purple),
        "aria":        .init(module: "aria", label: "System",
                             icon: "sparkles", color: Color(red: 0.45, green: 0.30, blue: 0.95)),
        "system":      .init(module: "system", label: "System",
                             icon: "gearshape.fill", color: Color(.systemGray)),
        "delivery":    .init(module: "delivery", label: "Deliveries",
                             icon: "shippingbox.fill", color: .orange),
    ]
}

// MARK: - Service

@MainActor
@Observable
final class NotificationService {
    var notifications: [AppNotification] = []
    var isLoading = false
    var error: String?

    var unreadCount: Int { notifications.filter(\.isUnread).count }

    private var realtimeChannel: RealtimeChannelV2?
    private var postgresSubs: [RealtimeSubscription] = []
    private var reloadTask: Task<Void, Never>?

    func load(userId: UUID) async {
        isLoading = notifications.isEmpty
        defer { isLoading = false }
        do {
            notifications = try await supabase
                .from("notifications")
                .select("id, title, body, priority, status, module, action_url, resource_type, resource_id, created_at")
                .eq("user_id", value: userId.uuidString)
                .neq("status", value: "dismissed")
                .order("created_at", ascending: false)
                .limit(100)
                .execute()
                .value
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Keeps the list and the dashboard badge live while the app is open.
    func subscribeRealtime(userId: UUID) async {
        guard realtimeChannel == nil else { return }
        let channel = supabase.realtimeV2.channel("notifications:\(userId.uuidString)")
        postgresSubs.append(channel.onPostgresChange(
            InsertAction.self,
            schema: "public",
            table: "notifications",
            filter: "user_id=eq.\(userId.uuidString)"
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleReload(userId: userId) }
        })
        try? await channel.subscribeWithError()
        realtimeChannel = channel
    }

    func unsubscribe() async {
        postgresSubs.removeAll()
        if let ch = realtimeChannel {
            await supabase.realtimeV2.removeChannel(ch)
            realtimeChannel = nil
        }
    }

    /// Coalesces bursts of inserts (e.g. a lively chat) into one reload.
    private func scheduleReload(userId: UUID) {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.load(userId: userId)
        }
    }

    func markRead(_ notification: AppNotification) async {
        guard notification.isUnread,
              let idx = notifications.firstIndex(where: { $0.id == notification.id }) else { return }
        notifications[idx].status = "read"
        _ = try? await supabase
            .from("notifications")
            .update(["status": "read"])
            .eq("id", value: notification.id.uuidString)
            .execute()
    }

    func markAllRead(userId: UUID) async {
        for i in notifications.indices { notifications[i].status = "read" }
        _ = try? await supabase
            .from("notifications")
            .update(["status": "read"])
            .eq("user_id", value: userId.uuidString)
            .eq("status", value: "unread")
            .execute()
    }

    func dismiss(_ notification: AppNotification) async {
        notifications.removeAll { $0.id == notification.id }
        _ = try? await supabase
            .from("notifications")
            .update(["status": "dismissed"])
            .eq("id", value: notification.id.uuidString)
            .execute()
    }

    func clearAll(userId: UUID) async {
        notifications.removeAll()
        _ = try? await supabase
            .from("notifications")
            .update(["status": "dismissed"])
            .eq("user_id", value: userId.uuidString)
            .neq("status", value: "dismissed")
            .execute()
    }
}
