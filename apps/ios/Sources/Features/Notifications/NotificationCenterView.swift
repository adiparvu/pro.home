import SwiftUI

// MARK: - Notification center
//
// Live inbox over the notifications table: category chips derived from the
// modules actually present (chat, tasks, garden, documents… and any module a
// future feature starts writing), tap-to-navigate deep links, swipe to read/
// dismiss, and realtime updates shared with the dashboard bell badge.

struct NotificationCenterView: View {
    @Environment(AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismissSheet

    let service: NotificationService

    @State private var filter: String?   // nil = All, "unread", or a module

    private var userId: UUID? { auth.session?.user.id }

    private var categories: [NotificationCategory] {
        var seen = Set<String>()
        var result: [NotificationCategory] = []
        for n in service.notifications {
            let cat = NotificationCategory.forModule(n.module)
            if seen.insert(cat.module).inserted { result.append(cat) }
        }
        return result
    }

    private var filtered: [AppNotification] {
        switch filter {
        case nil:      return service.notifications
        case "unread": return service.notifications.filter(\.isUnread)
        case .some(let module):
            return service.notifications.filter {
                NotificationCategory.forModule($0.module).module == module
            }
        }
    }

    var body: some View {
        Group {
            if service.isLoading {
                VStack { Spacer(); ProgressView().tint(.primary); Spacer() }
            } else if service.notifications.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !service.notifications.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if service.unreadCount > 0 {
                            Button {
                                guard let uid = userId else { return }
                                Task { await service.markAllRead(userId: uid) }
                            } label: {
                                Label("Mark all read", systemImage: "checkmark.circle")
                            }
                        }
                        Button(role: .destructive) {
                            guard let uid = userId else { return }
                            Task { await service.clearAll(userId: uid) }
                        } label: {
                            Label("Clear all", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
        }
        .task {
            if let uid = userId {
                await service.load(userId: uid)
                await service.subscribeRealtime(userId: uid)
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            filterChips
                .padding(.vertical, AppSpacing.sm)

            List {
                ForEach(filtered) { notif in
                    NotificationRow(notification: notif)
                        .listRowInsets(EdgeInsets(top: 5, leading: AppSpacing.lg,
                                                  bottom: 5, trailing: AppSpacing.lg))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .contentShape(Rectangle())
                        .onTapGesture { open(notif) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { await service.dismiss(notif) }
                            } label: {
                                Label("Dismiss", systemImage: "xmark")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if notif.isUnread {
                                Button {
                                    Task { await service.markRead(notif) }
                                } label: {
                                    Label("Read", systemImage: "checkmark")
                                }
                                .tint(.blue)
                            }
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(label: Text("All"), icon: nil, color: .accentColor, key: nil,
                     count: service.notifications.count)
                if service.unreadCount > 0 {
                    chip(label: Text("Unread"), icon: "circle.fill", color: .blue,
                         key: "unread", count: service.unreadCount)
                }
                ForEach(categories) { cat in
                    chip(label: Text(cat.label), icon: cat.icon, color: cat.color,
                         key: cat.module,
                         count: service.notifications.filter {
                             NotificationCategory.forModule($0.module).module == cat.module
                         }.count)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
        }
    }

    private func chip(label: Text, icon: String?, color: Color, key: String?, count: Int) -> some View {
        let selected = filter == key
        return Button {
            HapticFeedback.selection()
            withAnimation(.smooth(duration: 0.22)) { filter = key }
        } label: {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                }
                label.font(AppFont.captionEmphasis)
                Text("\(count)")
                    .font(AppFont.caption2)
                    .opacity(0.65)
            }
            .foregroundStyle(selected ? Color.white : color)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(selected ? color : color.opacity(0.13), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "bell.slash",
            title: "No notifications",
            message: "You're all caught up!"
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Navigation

    /// Marks the notification read, closes the sheet and routes to the thing
    /// it's about. Router is captured before dismiss (same pattern as global
    /// search) because the environment dies with the view.
    private func open(_ notif: AppNotification) {
        HapticFeedback.impact(.light)
        Task { await service.markRead(notif) }
        let r = router
        dismissSheet()
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            r.handle(notificationModule: notif.module,
                     actionUrl: notif.actionUrl,
                     resourceId: notif.resourceId)
        }
    }
}

// MARK: - Row

private struct NotificationRow: View {
    let notification: AppNotification

    private var category: NotificationCategory {
        NotificationCategory.forModule(notification.module)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(category.color.opacity(0.13))
                    .frame(width: 40, height: 40)
                Image(systemName: category.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(category.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(notification.title)
                        .font(.system(size: 14, weight: notification.isUnread ? .semibold : .regular))
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                    Spacer()
                    Text(notification.timeDisplay)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.38))
                }
                if let body = notification.body, !body.isEmpty {
                    Text(body)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .lineLimit(2)
                }
                HStack(spacing: 4) {
                    Image(systemName: category.icon)
                        .font(.system(size: 8, weight: .semibold))
                    Text(category.label)
                        .font(AppFont.caption2)
                }
                .foregroundStyle(category.color.opacity(0.85))
            }

            if notification.isUnread {
                Circle()
                    .fill(notification.priorityColor)
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
