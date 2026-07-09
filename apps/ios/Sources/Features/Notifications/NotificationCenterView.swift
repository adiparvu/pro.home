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
    @State private var searchText = ""

    /// `initialFilter` pre-selects a module chip — the conversations bell
    /// opens the panel scoped to chat activity; All stays one tap away.
    init(service: NotificationService, initialFilter: String? = nil) {
        self.service = service
        _filter = State(initialValue: initialFilter)
    }

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
        let base: [AppNotification]
        switch filter {
        case nil:      base = service.notifications
        case "unread": base = service.notifications.filter(\.isUnread)
        case .some(let module):
            base = service.notifications.filter {
                NotificationCategory.forModule($0.module).module == module
            }
        }
        guard !searchText.isEmpty else { return base }
        return base.filter {
            $0.title.matchesSearch(searchText) || ($0.body ?? "").matchesSearch(searchText)
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
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: Text("Search…"))
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
                        Image(systemName: "ellipsis")
                            .font(AppFont.subheadline)
                            .foregroundStyle(.primary)
                            .frame(width: 34, height: 34)
                            .glassCircle()
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
            .refreshable {
                if let uid = userId {
                    await service.load(userId: uid)
                }
            }
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
            let content = HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(AppFont.scaled(10, weight: .semibold))
                }
                label.font(AppFont.captionEmphasis)
                Text("\(count)")
                    .font(AppFont.caption2)
                    .opacity(0.65)
            }
            .foregroundStyle(selected ? Color.white : color)
            .padding(.horizontal, 12).padding(.vertical, 7)

            // Selected keeps a solid tint for unmistakable state; the resting
            // chips are Liquid Glass so the row adapts to whatever scrolls
            // beneath instead of painting opaque pastel pills.
            if selected {
                content.background(color.gradient, in: Capsule())
            } else {
                content.glassCapsule()
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
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

    /// Marks the notification read, parks the destination route on the router
    /// and closes the sheet — the presenting sheet's `onDismiss` drains
    /// `pendingRoute` once the dismissal actually finished, so the handoff is
    /// event-driven instead of racing a fixed sleep.
    private func open(_ notif: AppNotification) {
        HapticFeedback.impact(.light)
        Task { await service.markRead(notif) }
        router.pendingRoute = router.route(forNotificationModule: notif.module,
                                           actionUrl: notif.actionUrl,
                                           resourceId: notif.resourceId)
        dismissSheet()
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
            Image(systemName: category.icon)
                .font(AppFont.subheadline)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(category.color)
                .frame(width: 40, height: 40)
                .glassCircle()

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ServerNotificationLocalizer.title(notification.title))
                        .font(AppFont.scaled(14, weight: notification.isUnread ? .semibold : .regular))
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                    Spacer()
                    Text(notification.timeDisplay)
                        .font(AppFont.scaled(11))
                        .foregroundStyle(Color.primary.opacity(0.38))
                }
                if let body = ServerNotificationLocalizer.body(notification.body), !body.isEmpty {
                    Text(body)
                        .font(AppFont.scaled(13))
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .lineLimit(2)
                }
                HStack(spacing: 4) {
                    Image(systemName: category.icon)
                        .font(AppFont.scaled(8, weight: .semibold))
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
        .liquidGlass(cornerRadius: AppRadius.lg)
        .overlay {
            // Unread keeps a quiet tinted edge — state must survive the
            // switch from opaque fills to adaptive glass.
            if notification.isUnread {
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .strokeBorder(notification.priorityColor.opacity(0.3), lineWidth: 1)
            }
        }
    }
}
