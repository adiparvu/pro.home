import SwiftUI

// MARK: - Notification center
//
// Live inbox over the notifications table, grouped the way a person thinks:
// one row per chat conversation (not one per message), one row per task (the
// daily generator's duplicates coalesce), day sections (Today / Yesterday /
// This week / Earlier), module icons on every card, swipe to read/dismiss,
// and realtime updates shared with the dashboard bell badge.

struct NotificationCenterView: View {
    @Environment(AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismissSheet

    let service: NotificationService

    @State private var filter: String?   // nil = All, "unread", or a module
    @State private var searchText = ""
    @State private var expandedIds: Set<UUID> = []

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

    // MARK: Grouping (chat per sender, tasks per resource)

    private var sections: [InboxSection] {
        InboxSection.build(from: InboxGroup.coalesce(filtered))
    }

    var body: some View {
        Group {
            if service.isLoading && service.notifications.isEmpty {
                loadingSkeleton
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
            if service.unreadCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        HapticFeedback.impact(.light)
                        guard let uid = userId else { return }
                        Task { await service.markAllRead(userId: uid) }
                    } label: {
                        // No .glassCircle() here — iOS 26 already wraps a
                        // toolbar control in its own glass, so adding one drew
                        // a second overlapping circle (IMG_8315).
                        Image(systemName: "checkmark.circle")
                            .font(AppFont.subheadline)
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("Mark all read")
                }
            }
            if !service.notifications.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            guard let uid = userId else { return }
                            Task { await service.clearAll(userId: uid) }
                        } label: {
                            Label("Clear all", systemImage: "trash")
                        }
                    } label: {
                        // The toolbar supplies the glass; no custom circle.
                        Image(systemName: "ellipsis")
                            .font(AppFont.subheadline)
                            .foregroundStyle(.primary)
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
        // So a chat notification can show its sender's real avatar.
        .task { await MemberDirectory.shared.loadIfNeeded() }
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            filterChips
                .padding(.vertical, AppSpacing.sm)

            List {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.groups) { group in
                            row(group)
                        }
                    } header: {
                        Text(section.title)
                            .font(AppFont.label)
                            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                            .textCase(nil)
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

    private func row(_ group: InboxGroup) -> some View {
        NotificationRow(notification: group.latest,
                        groupCount: group.count,
                        isUnread: group.hasUnread,
                        showCategoryLabel: filter == nil,
                        isExpandable: isExpandable(group.latest),
                        isExpanded: expandedIds.contains(group.latest.id))
            .listRowInsets(EdgeInsets(top: 5, leading: AppSpacing.lg,
                                      bottom: 5, trailing: AppSpacing.lg))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .contentShape(Rectangle())
            .onTapGesture { tap(group) }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    Task { await service.dismiss(group.members) }
                } label: {
                    Label("Dismiss", systemImage: "xmark")
                }
            }
            .swipeActions(edge: .leading) {
                if group.hasUnread {
                    Button {
                        Task { await service.markRead(group.members) }
                    } label: {
                        Label("Read", systemImage: "checkmark")
                    }
                    .tint(.blue)
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

    /// Quiet placeholder rows while the first load runs — no floating
    /// spinner over half-rendered content.
    private var loadingSkeleton: some View {
        VStack(spacing: 10) {
            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: 14) {
                    Circle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 160, height: 12)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.05))
                            .frame(height: 10)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, AppSpacing.base)
                .padding(.vertical, AppSpacing.md)
                .background(Color.primary.opacity(0.03),
                            in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            }
            Spacer()
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.top, AppSpacing.md)
        .accessibilityLabel("Loading…")
    }

    // MARK: - Interactions

    /// Long digest bodies (the weekly recap) have no deeper destination —
    /// tapping unfolds them in place instead of pretending to navigate.
    private func isExpandable(_ n: AppNotification) -> Bool {
        let module = NotificationCategory.forModule(n.module).module
        return (module == "aria" || module == "system") && (n.body?.count ?? 0) > 80
    }

    private func tap(_ group: InboxGroup) {
        HapticFeedback.impact(.light)
        if isExpandable(group.latest) {
            withAnimation(.snappy) {
                if !expandedIds.insert(group.latest.id).inserted {
                    expandedIds.remove(group.latest.id)
                }
            }
            Task { await service.markRead(group.members) }
            return
        }
        open(group)
    }

    /// Marks the whole group read, parks the destination route on the router
    /// and closes the sheet — the presenting sheet's `onDismiss` drains
    /// `pendingRoute` once the dismissal actually finished, so the handoff is
    /// event-driven instead of racing a fixed sleep.
    private func open(_ group: InboxGroup) {
        let notif = group.latest
        Task { await service.markRead(group.members) }
        router.pendingRoute = router.route(forNotificationModule: notif.module,
                                           actionUrl: notif.actionUrl,
                                           resourceId: notif.resourceId)
        dismissSheet()
    }
}

// MARK: - Grouping model

/// One visual row: a chat sender's burst, a task's daily duplicates, or a
/// single notification. `members` are newest-first and include `latest`.
private struct InboxGroup: Identifiable {
    let latest: AppNotification
    let members: [AppNotification]

    var id: UUID { latest.id }
    var count: Int { members.count }
    var hasUnread: Bool { members.contains(where: \.isUnread) }

    /// Input is newest-first (the service's load order); output preserves
    /// each group's first appearance so the inbox stays chronological.
    static func coalesce(_ list: [AppNotification]) -> [InboxGroup] {
        var indexByKey: [String: Int] = [:]
        var buckets: [[AppNotification]] = []
        for n in list {
            let module = NotificationCategory.forModule(n.module).module
            let key: String?
            switch module {
            case "chat":
                key = "chat|" + n.title            // title = sender name
            case "tasks":
                key = n.resourceId.map { "task|" + $0.uuidString }
            default:
                key = nil
            }
            if let key {
                if let idx = indexByKey[key] {
                    buckets[idx].append(n)
                    continue
                }
                indexByKey[key] = buckets.count
            }
            buckets.append([n])
        }
        return buckets.map { InboxGroup(latest: $0[0], members: $0) }
    }
}

private struct InboxSection: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let groups: [InboxGroup]

    static func build(from groups: [InboxGroup]) -> [InboxSection] {
        let cal = Calendar.current
        let weekFloor = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: Date()))
        var today: [InboxGroup] = [], yesterday: [InboxGroup] = []
        var thisWeek: [InboxGroup] = [], earlier: [InboxGroup] = []
        for g in groups {
            guard let d = g.latest.date else { earlier.append(g); continue }
            if cal.isDateInToday(d) { today.append(g) }
            else if cal.isDateInYesterday(d) { yesterday.append(g) }
            else if let weekFloor, d >= weekFloor { thisWeek.append(g) }
            else { earlier.append(g) }
        }
        let all: [(String, LocalizedStringKey, [InboxGroup])] = [
            ("today", "Today", today),
            ("yesterday", "Yesterday", yesterday),
            ("week", "This week", thisWeek),
            ("earlier", "Earlier", earlier),
        ]
        return all.filter { !$0.2.isEmpty }
            .map { InboxSection(id: $0.0, title: $0.1, groups: $0.2) }
    }
}

// MARK: - Row

private struct NotificationRow: View {
    let notification: AppNotification
    let groupCount: Int
    let isUnread: Bool
    let showCategoryLabel: Bool
    let isExpandable: Bool
    let isExpanded: Bool

    private var category: NotificationCategory {
        NotificationCategory.forModule(notification.module)
    }

    // For a chat notification we know the sender only by the title; when it
    // resolves to exactly one real household member, show their live avatar
    // instead of the generic chat glyph. No match → the category icon, so a
    // wrong face is never shown.
    private var senderAvatar: MemberDirectory.Entry? {
        guard category.module == "chat" else { return nil }
        return MemberDirectory.shared.entry(matchingName: notification.title)
    }

    @ViewBuilder
    private var leadingIcon: some View {
        if let sender = senderAvatar, let urlStr = sender.avatarUrl, !urlStr.isEmpty {
            StorageImage(source: urlStr) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFill()
                } else { categoryGlyph }
            }
            .clipShape(Circle())
        } else {
            categoryGlyph
        }
    }

    private var categoryGlyph: some View {
        Image(systemName: category.icon)
            .font(AppFont.subheadline)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(category.color)
            .frame(width: 40, height: 40)
            .glassCircle()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            leadingIcon
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(ServerNotificationLocalizer.title(notification.title))
                        .font(AppFont.scaled(14, weight: isUnread ? .semibold : .regular))
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                    if groupCount > 1 {
                        Text("\(groupCount)")
                            .font(AppFont.scaled(11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(category.color.gradient, in: Capsule())
                            .accessibilityHidden(true)
                    }
                    Spacer()
                    Text(notification.timeDisplay)
                        .font(AppFont.scaled(11))
                        .foregroundStyle(Color.primary.opacity(0.38))
                }
                if let body = ServerNotificationLocalizer.body(notification.body), !body.isEmpty {
                    Text(body)
                        .font(AppFont.scaled(13))
                        .foregroundStyle(Color.primary.opacity(0.6))
                        .lineLimit(isExpanded ? nil : 2)
                }
                if isExpandable {
                    Image(systemName: "chevron.down")
                        .font(AppFont.scaled(9, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.35))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .padding(.top, 1)
                        .accessibilityHidden(true)
                } else if showCategoryLabel {
                    // The module tag earns its place only in the mixed "All"
                    // list; under a module filter it repeated the chip above.
                    HStack(spacing: 4) {
                        Image(systemName: category.icon)
                            .font(AppFont.scaled(8, weight: .semibold))
                        Text(category.label)
                            .font(AppFont.caption2)
                    }
                    .foregroundStyle(category.color.opacity(0.85))
                }
            }

            if isUnread {
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
            if isUnread {
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .strokeBorder(notification.priorityColor.opacity(0.3), lineWidth: 1)
            }
        }
    }
}
