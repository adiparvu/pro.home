import SwiftUI
import Observation
import Supabase
import UIKit
import UserNotifications

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

    var date: Date? { ISODate.date(from: createdAt) }

    // The system relative formatter owns pluralization ("acum 1 oră" /
    // "acum 5 ore" / "ieri") — hand-built "%lld h ago" keys can't, because
    // the xcstrings pipeline has no plural support.
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        f.dateTimeStyle = .named
        return f
    }()

    var timeDisplay: String {
        guard let date else { return "" }
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return String(localized: "Just now") }
        // Within a week the human phrase wins; older items get a short date —
        // never the technical write-time clock.
        if diff < 6 * 86400 {
            return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
        }
        return AppDate.medium.string(from: date)
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
        var m = module ?? "system"
        // Two writers, one product concept: the generator writes
        // "maintenance", the assignment trigger writes "tasks". Without the
        // alias the panel grew two chips both labelled "Tasks".
        if m == "maintenance" { m = "tasks" }
        if let known = known[m] { return known }
        return NotificationCategory(module: m, label: LocalizedStringKey(m.capitalized),
                                    icon: "bell.fill", color: .blue)
    }

    private static let known: [String: NotificationCategory] = [
        "chat":        .init(module: "chat", label: "Chat",
                             icon: "bubble.left.and.bubble.right.fill", color: .blue),
        "tasks":       .init(module: "tasks", label: "Tasks",
                             icon: "checklist", color: .orange),
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

    // Each mutation is optimistic but rolls back on a failed write, so an
    // offline "read"/"dismiss" doesn't lie: without this, dismissed rows
    // resurrected and the badge snapped back on the next load.

    func markRead(_ notification: AppNotification) async {
        guard notification.isUnread,
              let idx = notifications.firstIndex(where: { $0.id == notification.id }) else { return }
        notifications[idx].status = "read"
        do {
            try await supabase
                .from("notifications")
                .update(["status": "read"])
                .eq("id", value: notification.id.uuidString)
                .execute()
        } catch {
            if let i = notifications.firstIndex(where: { $0.id == notification.id }) {
                notifications[i].status = "unread"
            }
            self.error = error.localizedDescription
        }
    }

    /// One write for a whole inbox group (a coalesced chat sender or a
    /// task's daily duplicates) — same optimistic/rollback contract as the
    /// single-row path.
    func markRead(_ group: [AppNotification]) async {
        let ids = group.filter(\.isUnread).map(\.id)
        guard !ids.isEmpty else { return }
        let snapshot = notifications
        for i in notifications.indices where ids.contains(notifications[i].id) {
            notifications[i].status = "read"
        }
        do {
            try await supabase
                .from("notifications")
                .update(["status": "read"])
                .in("id", values: ids.map(\.uuidString))
                .execute()
        } catch {
            notifications = snapshot
            self.error = error.localizedDescription
        }
    }

    func dismiss(_ group: [AppNotification]) async {
        let ids = Set(group.map(\.id))
        guard !ids.isEmpty else { return }
        let snapshot = notifications
        notifications.removeAll { ids.contains($0.id) }
        do {
            try await supabase
                .from("notifications")
                .update(["status": "dismissed"])
                .in("id", values: ids.map(\.uuidString))
                .execute()
        } catch {
            notifications = snapshot
            self.error = error.localizedDescription
        }
    }

    func markAllRead(userId: UUID) async {
        let snapshot = notifications
        for i in notifications.indices { notifications[i].status = "read" }
        do {
            try await supabase
                .from("notifications")
                .update(["status": "read"])
                .eq("user_id", value: userId.uuidString)
                .eq("status", value: "unread")
                .execute()
        } catch {
            notifications = snapshot
            self.error = error.localizedDescription
        }
    }

    /// Marks every unread notification for one module read — called when the
    /// user opens that module's surface (e.g. a chat thread), so the in-app bell
    /// and the springboard badge stop claiming items the user is now looking at.
    /// Any rows already loaded flip optimistically; the server is always updated;
    /// then the icon badge is reconciled to the TRUE remaining unread count.
    func markModuleRead(_ module: String, userId: UUID) async {
        for i in notifications.indices
        where notifications[i].module == module && notifications[i].isUnread {
            notifications[i].status = "read"
        }
        do {
            try await supabase
                .from("notifications")
                .update(["status": "read"])
                .eq("user_id", value: userId.uuidString)
                .eq("module", value: module)
                .eq("status", value: "unread")
                .execute()
        } catch {
            // Leave the optimistic flip; a later load() reconciles. (Matches the
            // rest of this type: local stays authoritative, the server catches up.)
            self.error = error.localizedDescription
        }
        await reconcileBadge(userId: userId)
    }

    /// Sets the springboard icon badge to the real number of unread
    /// notifications on the server — never a blind 0. If the count can't be
    /// confirmed (offline), it falls back to the best local truth rather than
    /// fabricating a value.
    func reconcileBadge(userId: UUID) async {
        struct IDRow: Decodable { let id: UUID }
        let remaining: Int
        if let rows: [IDRow] = try? await supabase
            .from("notifications")
            .select("id")
            .eq("user_id", value: userId.uuidString)
            .eq("status", value: "unread")
            .execute()
            .value {
            remaining = rows.count
        } else {
            remaining = unreadCount
        }
        // Springboard badge lives on the notification center in iOS 17+
        // (UIApplication.setBadgeCount doesn't exist).
        try? await UNUserNotificationCenter.current().setBadgeCount(remaining)
    }

    func dismiss(_ notification: AppNotification) async {
        let snapshot = notifications
        notifications.removeAll { $0.id == notification.id }
        do {
            try await supabase
                .from("notifications")
                .update(["status": "dismissed"])
                .eq("id", value: notification.id.uuidString)
                .execute()
        } catch {
            notifications = snapshot
            self.error = error.localizedDescription
        }
    }

    func clearAll(userId: UUID) async {
        let snapshot = notifications
        notifications.removeAll()
        do {
            try await supabase
                .from("notifications")
                .update(["status": "dismissed"])
                .eq("user_id", value: userId.uuidString)
                .neq("status", value: "dismissed")
                .execute()
        } catch {
            notifications = snapshot
            self.error = error.localizedDescription
        }
    }
}
