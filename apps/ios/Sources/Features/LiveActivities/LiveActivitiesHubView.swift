import SwiftUI
import ActivityKit

// MARK: - Live Activities Hub
//
// The command center for every Live Activity: a real-time dashboard over
// LiveActivityHubStore (which enumerates ActivityKit directly and keeps the
// persistent lifecycle log), rich cards for everything running right now,
// the nine activity categories, the power tools, and the master switches
// preserved from the legacy settings screen. HONESTY LAW: every number on
// this page is computed from the store's real snapshot or the real event
// log — zero activities reads as zero, no history reads as "none yet".

struct LiveActivitiesHubView: View {
    // Master preferences — the same keys and rows as the legacy settings
    // screen, preserved verbatim so nothing the user configured changes.
    @AppStorage(LiveActivityPrefs.enabledKey, store: LiveActivityPrefs.store)     private var enabled       = true
    @AppStorage(LiveActivityPrefs.startOnOpenKey, store: LiveActivityPrefs.store) private var startOnOpen   = false
    @AppStorage(LiveActivityPrefs.scheduleKey, store: LiveActivityPrefs.store)    private var startSchedule = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @State private var searchText = ""
    @State private var filter: HubFilter = .all
    @State private var systemEnabled = true

    /// Resolved in body (main actor); @Observable tracking hooks in on read.
    private var store: LiveActivityHubStore { .shared }

    private var anim: Animation? {
        reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.18)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: AppSpacing.lg) {
                heroSection
                filterChips
                if !visibleActive.isEmpty { activeSection }
                categoriesSection
                toolsSection
                settingsSection
                Spacer(minLength: 64)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
            .animation(anim, value: store.active)
            .animation(anim, value: filter)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("la_hub_title")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: Text("la_hub_search_prompt"))
        .refreshable {
            store.refresh()
            store.reloadEvents()
        }
        .task {
            systemEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
            store.refresh()
            store.reloadEvents()
            // Live pulse while the hub is visible; .task cancels on disappear.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                store.refresh()
            }
        }
        .onAppear {
            // Coming back from a detail screen: pick up priority/favorite/end
            // changes immediately instead of waiting for the next pulse.
            store.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            systemEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
            store.refresh()
            store.reloadEvents()
        }
    }

    // MARK: - 1. Hero dashboard (real metrics only)

    private var urgentCount: Int {
        store.active.filter { $0.kind == .emergency || $0.kind == .iotAlert }.count
    }
    private var runningCount: Int { store.active.count - urgentCount }
    private var finishedToday: Int {
        store.events.filter {
            ($0.phase == "ended" || $0.phase == "completed") && Calendar.current.isDateInToday($0.at)
        }.count
    }
    private var lastActivityText: String {
        store.events.first.map { $0.at.formatted(.relative(presentation: .named)) }
            ?? String(localized: "la_hub_never")
    }

    @ViewBuilder
    private var heroSection: some View {
        if systemEnabled {
            HeavyGlassCard(padding: AppSpacing.xl, cornerRadius: AppRadius.xxl) {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("la_hub_active_count \(store.active.count)")
                            .font(AppFont.title2)
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                        Spacer()
                        Image(systemName: "bolt.badge.clock.fill")
                            .font(AppFont.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.brandPrimaryBlue)
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: AppSpacing.md),
                                        GridItem(.flexible(), spacing: AppSpacing.md)],
                              alignment: .leading, spacing: AppSpacing.md) {
                        HubMetricCell(icon: "play.circle.fill", color: .brandPrimaryBlue,
                                      value: "\(runningCount)", label: "la_hub_metric_running")
                        HubMetricCell(icon: "exclamationmark.triangle.fill", color: .brandDanger,
                                      value: "\(urgentCount)", label: "la_hub_metric_urgent")
                        HubMetricCell(icon: "checkmark.circle.fill", color: .brandSuccess,
                                      value: "\(finishedToday)", label: "la_hub_metric_done_today")
                        HubMetricCell(icon: "clock.arrow.circlepath", color: .brandTeal,
                                      value: lastActivityText, label: "la_hub_metric_last")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            // Same copy as the legacy screen — never fake zeros when the
            // system switch is off.
            GlassCard {
                HStack(spacing: AppSpacing.base) {
                    ColoredIconBadge(icon: "exclamationmark.triangle.fill", color: .orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Live Activities are off in iOS")
                            .font(AppFont.footnoteEmphasis)
                        Text("Enable them in Settings › Face ID & Passcode and per-app to see them here.")
                            .font(AppFont.scaled(12))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - 2 + 3. Search & filter picker

    private var filterChips: some View {
        HStack(spacing: AppSpacing.sm) {
            GlassPopoverPicker(
                options: HubFilter.allCases.map { f in
                    GlassPickerOption(value: f,
                                      icon: f.icon,
                                      title: f.labelString,
                                      count: chipCount(for: f))
                },
                selection: $filter)
            Spacer()
        }
        .padding(.vertical, AppSpacing.xxs)
    }

    /// Real counts only — nil hides the badge rather than showing a made-up 0.
    private func chipCount(for f: HubFilter) -> Int? {
        switch f {
        case .all:       return nil
        case .active:    return store.active.count
        case .auto:      return LiveActivityKind.allCases.filter { isAutoOn($0) }.count
        case .favorites: return store.favoriteKinds.count
        case .today:     return store.events.filter { Calendar.current.isDateInToday($0.at) }.count
        }
    }

    // MARK: - Filtering & search plumbing

    private var query: String {
        hubFold(searchText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func matchesSearch(_ kind: LiveActivityKind) -> Bool {
        query.isEmpty || hubFold(kind.searchableTitle).contains(query)
    }

    private func matchesSearch(_ item: LiveActivityHubStore.HubActivity) -> Bool {
        if query.isEmpty { return true }
        return hubFold(item.title).contains(query)
            || hubFold(item.detail).contains(query)
            || hubFold(item.kind.searchableTitle).contains(query)
    }

    /// Auto badge/filter is honest: only kinds that HAVE an auto-start toggle
    /// count (manual-only kinds like the work session never claim "AUTO").
    private func isAutoOn(_ kind: LiveActivityKind) -> Bool {
        kind.supportsAutoStart && LiveActivityPrefs.autoStart(for: kind)
    }

    private var kindsForFilter: [LiveActivityKind] {
        switch filter {
        case .all:
            return LiveActivityKind.allCases
        case .active:
            return LiveActivityKind.allCases.filter { k in store.active.contains { $0.kind == k } }
        case .auto:
            return LiveActivityKind.allCases.filter { isAutoOn($0) }
        case .favorites:
            return LiveActivityKind.allCases.filter { store.isFavorite($0) }
        case .today:
            return LiveActivityKind.allCases.filter { k in
                store.events.contains { $0.kind == k.rawValue && Calendar.current.isDateInToday($0.at) }
            }
        }
    }

    private func priorityValue(_ kind: LiveActivityKind) -> String {
        LiveActivityPrefs.store.string(forKey: LiveActivityPrefs.priorityKey(kind.rawValue)) ?? "normal"
    }

    private func priorityRank(_ kind: LiveActivityKind) -> Int {
        switch priorityValue(kind) {
        case "critical": return 0
        case "high":     return 1
        case "silent":   return 3
        default:         return 2
        }
    }

    private func priorityDotColor(_ kind: LiveActivityKind) -> Color? {
        switch priorityValue(kind) {
        case "critical": return .brandDanger
        case "high":     return .brandWarning
        case "silent":   return .secondary
        default:         return nil
        }
    }

    /// Active cards, filtered by chip + search, ordered by the user's
    /// priority (critical → high → normal → silent), then newest first.
    private var visibleActive: [LiveActivityHubStore.HubActivity] {
        let kinds = Set(kindsForFilter)
        return store.active
            .filter { kinds.contains($0.kind) && matchesSearch($0) }
            .sorted { a, b in
                let pa = priorityRank(a.kind), pb = priorityRank(b.kind)
                if pa != pb { return pa < pb }
                switch (a.startedAt, b.startedAt) {
                case let (da?, db?) where da != db: return da > db
                case (.some, .none):                return true
                case (.none, .some):                return false
                default: return a.title.localizedCompare(b.title) == .orderedAscending
                }
            }
    }

    /// Category cells: favorites first, then priority, then canonical order.
    private var visibleKinds: [LiveActivityKind] {
        let all = LiveActivityKind.allCases
        return kindsForFilter
            .filter { matchesSearch($0) }
            .sorted { a, b in
                let fa = store.isFavorite(a), fb = store.isFavorite(b)
                if fa != fb { return fa }
                let pa = priorityRank(a), pb = priorityRank(b)
                if pa != pb { return pa < pb }
                return (all.firstIndex(of: a) ?? 0) < (all.firstIndex(of: b) ?? 0)
            }
    }

    // MARK: - 4. Active now

    /// Property groups, only when the running activities genuinely span more
    /// than one named property.
    private var activeGroups: [HubPropertyGroup]? {
        let items = visibleActive
        guard Set(items.compactMap(\.propertyName)).count > 1 else { return nil }
        return Dictionary(grouping: items) { $0.propertyName ?? "" }
            .sorted { a, b in
                if a.key.isEmpty != b.key.isEmpty { return !a.key.isEmpty } // named first
                return a.key.localizedCompare(b.key) == .orderedAscending
            }
            .map { HubPropertyGroup(id: $0.key, items: $0.value) }
    }

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            sectionHeader("la_hub_active_now")
            if let groups = activeGroups {
                ForEach(groups) { group in
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "house.fill")
                            .font(AppFont.scaled(10, weight: .semibold))
                        if group.id.isEmpty {
                            Text("la_hub_no_property")
                        } else {
                            Text(verbatim: group.id)
                        }
                    }
                    .font(AppFont.captionStrong)
                    .foregroundStyle(Color.secondaryTextColor)
                    .padding(.leading, AppSpacing.xxs)
                    .padding(.top, AppSpacing.xxs)
                    ForEach(group.items) { item in
                        activeCard(item)
                    }
                }
            } else {
                ForEach(visibleActive) { item in
                    activeCard(item)
                }
            }
        }
    }

    private func activeCard(_ item: LiveActivityHubStore.HubActivity) -> some View {
        HubActivityCard(
            item: item,
            isFavorite: store.isFavorite(item.kind),
            animated: !reduceMotion,
            onOpen: {
                if let url = item.kind.deepLink { openURL(url) }
            },
            onEnd: {
                HapticFeedback.impact(.medium)
                store.end(item)
            },
            onToggleFavorite: {
                HapticFeedback.selection()
                withAnimation(anim) { store.toggleFavorite(item.kind) }
            })
    }

    // MARK: - 5. Categories

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            sectionHeader("la_hub_categories")
            if visibleKinds.isEmpty {
                Text("la_hub_no_results")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.secondaryTextColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.xl)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: AppSpacing.md),
                                    GridItem(.flexible(), spacing: AppSpacing.md)],
                          spacing: AppSpacing.md) {
                    ForEach(visibleKinds) { kind in
                        HubKindCell(
                            kind: kind,
                            activeCount: store.active.filter { $0.kind == kind }.count,
                            isFavorite: store.isFavorite(kind),
                            isAuto: isAutoOn(kind),
                            priorityDot: priorityDotColor(kind),
                            onToggleFavorite: {
                                HapticFeedback.selection()
                                withAnimation(anim) { store.toggleFavorite(kind) }
                            })
                    }
                }
            }
        }
    }

    // MARK: - 6. Tools (built by the hub's companion views)

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            sectionHeader("la_hub_tools")
            settingsGroup {
                HubToolRow(icon: "rectangle.on.rectangle", color: .brandPurple,
                           title: "la_hub_tool_studio") { LiveActivityPreviewStudio() }
                rowDivider
                HubToolRow(icon: "play.rectangle.on.rectangle", color: .brandPrimaryBlue,
                           title: "la_hub_tool_simulator") { LiveActivitySimulatorView() }
                rowDivider
                HubToolRow(icon: "clock.arrow.circlepath", color: .brandTeal,
                           title: "la_hub_tool_timeline") { LiveActivityTimelineView() }
                rowDivider
                HubToolRow(icon: "chart.bar.xaxis", color: .brandGold,
                           title: "la_hub_tool_analytics") { LiveActivityAnalyticsView() }
            }
        }
    }

    // MARK: - 7. Settings (master toggles preserved from the legacy screen)

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            sectionHeader("la_hub_settings")
            settingsGroup {
                LAToggleRow(icon: "bolt.badge.clock.fill", color: .blue,
                            title: "Live Activities",
                            subtitle: "Show real-time progress on the Lock Screen and Dynamic Island",
                            isOn: $enabled)
            }
            if enabled {
                settingsGroup {
                    LAToggleRow(icon: "calendar.badge.clock", color: .indigo,
                                title: "Start on a Schedule",
                                subtitle: "Begin activities automatically at their scheduled time",
                                isOn: $startSchedule)
                    rowDivider
                    LAToggleRow(icon: "app.badge.checkmark.fill", color: .teal,
                                title: "Start When App Opens",
                                subtitle: "Resume any in-progress activity when you open PRVIO",
                                isOn: $startOnOpen)
                }
            }
            Text("Live Activities appear on the Lock Screen and in the Dynamic Island while a task is running, and end automatically when it finishes.")
                .font(.caption)
                .foregroundStyle(Color.primary.opacity(0.3))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, AppSpacing.xxs)
        }
    }

    // MARK: - Reusable layout

    private func sectionHeader(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(AppFont.label)
            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, AppSpacing.xxs)
    }

    @ViewBuilder
    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .liquidGlass(cornerRadius: AppRadius.lg)
    }

    private var rowDivider: some View {
        Rectangle().fill(Color.primary.opacity(0.05))
            .frame(height: 0.5).padding(.leading, 52)
    }
}

// MARK: - Property group (Active Now sections)

private struct HubPropertyGroup: Identifiable {
    let id: String                                   // property name; "" = none
    let items: [LiveActivityHubStore.HubActivity]
}

// MARK: - Filter model

private enum HubFilter: String, CaseIterable, Identifiable {
    case all, active, auto, favorites, today

    var id: String { rawValue }

    var labelString: String {
        switch self {
        case .all:       return String(localized: "la_hub_filter_all")
        case .active:    return String(localized: "la_hub_filter_active")
        case .auto:      return String(localized: "la_hub_filter_auto")
        case .favorites: return String(localized: "la_hub_filter_favorites")
        case .today:     return String(localized: "la_hub_filter_today")
        }
    }

    var icon: String? {
        switch self {
        case .all:       return nil
        case .active:    return "dot.radiowaves.left.and.right"
        case .auto:      return "sparkles"
        case .favorites: return "star.fill"
        case .today:     return "calendar"
        }
    }
}

// MARK: - Hero metric cell

private struct HubMetricCell: View {
    let icon: String
    let color: Color
    let value: String
    let label: LocalizedStringKey

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(AppFont.scaled(13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .glassCircle()
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: value)
                    .font(AppFont.metricSmall)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(AppFont.scaled(10, weight: .medium))
                    .foregroundStyle(Color.secondaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Active activity card (swipe: end / favorite; tap: deep link)

private struct HubActivityCard: View {
    let item: LiveActivityHubStore.HubActivity
    let isFavorite: Bool
    let animated: Bool
    var onOpen: () -> Void
    var onEnd: () -> Void
    var onToggleFavorite: () -> Void

    @State private var offsetX: CGFloat = 0
    @State private var revealed = false

    private let actionSpan: CGFloat = 116

    var body: some View {
        ZStack(alignment: .trailing) {
            swipeActionButtons
                .opacity(offsetX < -12 ? 1 : 0)
                .accessibilityHidden(offsetX >= -12)
            card
                .offset(x: offsetX)
                .gesture(swipeGesture)
                .onTapGesture {
                    if revealed { close() } else { onOpen() }
                }
        }
        .contextMenu {
            Button { onOpen() } label: {
                Label("la_hub_open", systemImage: "arrow.up.forward.app")
            }
            Button { onToggleFavorite() } label: {
                Label(isFavorite ? "la_hub_unfavorite" : "la_hub_favorite",
                      systemImage: isFavorite ? "star.slash" : "star")
            }
            Button(role: .destructive) { onEnd() } label: {
                Label("End now", systemImage: "xmark.circle")
            }
        }
        .accessibilityAction(named: Text("End now")) { onEnd() }
        .accessibilityAction(named: Text(isFavorite ? "la_hub_unfavorite" : "la_hub_favorite")) {
            onToggleFavorite()
        }
    }

    private var card: some View {
        GlassCard(padding: AppSpacing.lg, cornerRadius: AppRadius.xl) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: item.kind.icon)
                        .font(AppFont.scaled(16, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(item.kind.color)
                        .frame(width: 42, height: 42)
                        .glassCircle()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: item.title)
                            .font(AppFont.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(verbatim: item.detail)
                            .font(AppFont.caption)
                            .foregroundStyle(item.kind.color)
                            .lineLimit(1)
                    }
                    Spacer(minLength: AppSpacing.sm)
                    VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                        HStack(spacing: 4) {
                            Circle().fill(Color.brandSuccess).frame(width: 6, height: 6)
                            Text("la_hub_live")
                                .font(AppFont.scaled(10, weight: .bold))
                                .foregroundStyle(Color.brandSuccess)
                        }
                        if isFavorite {
                            Image(systemName: "star.fill")
                                .font(AppFont.scaled(10))
                                .foregroundStyle(Color.brandGold)
                        }
                    }
                }
                if let progress = item.progress {
                    ProgressView(value: min(max(progress, 0), 1))
                        .tint(item.kind.color)
                }
                if item.propertyName != nil || item.startedAt != nil {
                    HStack(spacing: AppSpacing.sm) {
                        if let property = item.propertyName {
                            HStack(spacing: 4) {
                                Image(systemName: "house.fill")
                                    .font(AppFont.scaled(10))
                                Text(verbatim: property)
                                    .font(AppFont.caption2)
                                    .lineLimit(1)
                            }
                            .foregroundStyle(Color.secondaryTextColor)
                        }
                        Spacer()
                        if let startedAt = item.startedAt {
                            Text("la_hub_since \(startedAt.formatted(.relative(presentation: .named)))")
                                .font(AppFont.caption2)
                                .foregroundStyle(Color.secondaryTextColor)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }

    private var swipeActionButtons: some View {
        HStack(spacing: AppSpacing.sm) {
            Button {
                onToggleFavorite()
                close()
            } label: {
                Image(systemName: isFavorite ? "star.slash.fill" : "star.fill")
                    .font(AppFont.scaled(15, weight: .semibold))
                    .foregroundStyle(Color.brandGold)
                    .frame(width: 46, height: 46)
                    .glassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(isFavorite ? "la_hub_unfavorite" : "la_hub_favorite"))

            Button(role: .destructive) {
                onEnd()
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(AppFont.scaled(15, weight: .semibold))
                    .foregroundStyle(Color.brandDanger)
                    .frame(width: 46, height: 46)
                    .glassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("End now"))
        }
        .padding(.trailing, AppSpacing.xxs)
    }

    /// Horizontal-only swipe that reveals the actions; vertical drags stay
    /// with the ScrollView.
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let base: CGFloat = revealed ? -actionSpan : 0
                offsetX = max(-actionSpan - 20, min(0, base + value.translation.width))
            }
            .onEnded { _ in
                let open = offsetX < -actionSpan / 2
                withAnimation(animated ? .snappy(duration: 0.28) : nil) {
                    revealed = open
                    offsetX = open ? -actionSpan : 0
                }
            }
    }

    private func close() {
        withAnimation(animated ? .snappy(duration: 0.28) : nil) {
            revealed = false
            offsetX = 0
        }
    }
}

// MARK: - Category cell

private struct HubKindCell: View {
    let kind: LiveActivityKind
    let activeCount: Int
    let isFavorite: Bool
    let isAuto: Bool
    let priorityDot: Color?
    var onToggleFavorite: () -> Void

    var body: some View {
        NavigationLink {
            LiveActivityKindDetailView(kind: kind)
        } label: {
            GlassCard(padding: AppSpacing.base, cornerRadius: AppRadius.xl) {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    HStack(alignment: .top) {
                        Image(systemName: kind.icon)
                            .font(AppFont.scaled(15, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(kind.color)
                            .frame(width: 38, height: 38)
                            .glassCircle()
                            .overlay(alignment: .topTrailing) {
                                if let priorityDot {
                                    Circle().fill(priorityDot)
                                        .frame(width: 7, height: 7)
                                        .offset(x: 1, y: -1)
                                }
                            }
                        Spacer()
                        Button {
                            onToggleFavorite()
                        } label: {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .font(AppFont.scaled(13, weight: .semibold))
                                .foregroundStyle(isFavorite ? Color.brandGold
                                                            : Color.primary.opacity(AppOpacity.disabled))
                                .frame(width: 30, height: 30)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(isFavorite ? "la_hub_unfavorite" : "la_hub_favorite"))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(kind.title)
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        HStack(spacing: AppSpacing.xs) {
                            if activeCount > 0 {
                                Text("la_hub_kind_active \(activeCount)")
                                    .font(AppFont.scaled(11, weight: .semibold))
                                    .foregroundStyle(Color.brandSuccess)
                                    .contentTransition(.numericText())
                            } else {
                                Text("la_hub_none_running")
                                    .font(AppFont.scaled(11))
                                    .foregroundStyle(Color.secondaryTextColor)
                            }
                            if isAuto {
                                Text(verbatim: "AUTO")
                                    .font(AppFont.scaled(9, weight: .bold))
                                    .foregroundStyle(kind.color)
                                    .padding(.horizontal, AppSpacing.xs)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().strokeBorder(kind.color.opacity(0.45), lineWidth: 1))
                            }
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tool row

private struct HubToolRow<Destination: View>: View {
    let icon: String
    let color: Color
    let title: LocalizedStringKey
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                ColoredIconBadge(icon: icon, color: color)
                Text(title)
                    .font(AppFont.scaled(15))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(Color.primary.opacity(0.25))
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Search helpers

/// Case- and diacritic-insensitive folding ("Bucătărie" matches "bucatarie").
private func hubFold(_ s: String) -> String {
    s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
}

private extension LiveActivityKind {
    /// `title` as a plain String for search folding — same localization keys
    /// as the LocalizedStringKey `title`, which can't be folded or compared.
    var searchableTitle: String {
        switch self {
        case .shopping:    return String(localized: "Shopping list")
        case .delivery:    return String(localized: "Deliveries")
        case .maintenance: return String(localized: "Maintenance tasks")
        case .plantCare:   return String(localized: "Plant care")
        case .workSession: return String(localized: "Work session")
        case .emergency:   return String(localized: "Emergency")
        case .iotAlert:    return String(localized: "Sensor alerts")
        case .energy:      return String(localized: "Energy")
        case .cover:       return String(localized: "Garage & gates")
        }
    }
}
