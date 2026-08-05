import SwiftUI
import ActivityKit
import UserNotifications

// MARK: - Live Activity preferences
//
// Keys and accessors live in PRVIOLiveActivities.swift (compiled into both the
// app and the widgets target) so the extension that actually renders the
// activity reads the same app-group values this screen writes.

// The canonical LiveActivityKind — identity, tint, deep link, auto-start
// capability, preference keys — lives in
// Sources/LiveActivities/LiveActivityKind.swift, shared with the widgets
// target so the real activity views and this screen can never drift apart.
// This file adds only the preview sample data the mocks need.

extension LiveActivityKind {
    // MARK: Preview sample data — each kind mocks up as itself, so the user
    // sees exactly how THAT activity will look before customizing it.
    var previewHeadline: LocalizedStringKey {
        switch self {
        case .shopping:    return "Weekly shopping"
        case .delivery:    return "Garden bench"
        case .maintenance: return "Fix kitchen tap"
        case .plantCare:   return "Plant watering"
        case .workSession: return "Fix kitchen tap"
        case .emergency:   return "la_emergency_active"
        case .iotAlert:    return "Sensor alerts"
        case .energy:      return "Energy"
        case .cover:       return "Garage & gates"
        }
    }
    var previewStatus: LocalizedStringKey {
        switch self {
        case .shopping:    return "5 of 8 items"
        case .delivery:    return "In transit"
        case .maintenance: return "Step 3 of 5"
        case .plantCare:   return "3 of 5 watered"
        case .workSession: return "12:34"
        case .emergency:   return "02:41"
        case .iotAlert:    return "23.5 °C"
        case .energy:      return "2.8 kW"
        case .cover:       return "la_cover_moving"
        }
    }
    var previewProgress: Double {
        switch self {
        case .shopping:    return 0.62
        case .delivery:    return 0.65
        case .maintenance: return 0.6
        case .plantCare:   return 0.6
        case .workSession: return 0.5
        case .emergency:   return 0
        case .iotAlert:    return 0
        case .energy:      return 0
        case .cover:       return 0.5
        }
    }
    var showsETA: Bool { self == .delivery }
}

extension DynamicIslandStyle {
    var label: LocalizedStringKey {
        switch self {
        case .detailed: return "Detailed"
        case .compact:  return "Compact"
        case .minimal:  return "Minimal"
        }
    }
}

// MARK: - Live Activities settings screen

struct LiveActivitySettingsView: View {
    @AppStorage(LiveActivityPrefs.enabledKey, store: LiveActivityPrefs.store)     private var enabled       = true
    @AppStorage(LiveActivityPrefs.startOnOpenKey, store: LiveActivityPrefs.store) private var startOnOpen   = true

    @State private var systemEnabled = true
    @State private var previewKind: LiveActivityKind = .delivery

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {

                previewCard

                if !systemEnabled {
                    systemDisabledCard
                }

                // Master control
                settingsGroup {
                    LAToggleRow(icon: "bolt.badge.clock.fill", color: .blue,
                                title: "Live Activities",
                                subtitle: "Show real-time progress on the Lock Screen and Dynamic Island",
                                isOn: $enabled)
                }

                if enabled {
                    // Start behaviour. ("Start on a Schedule" is retired: a
                    // task merely scheduled for today is a plan, not a live
                    // event — plans belong to widgets and notifications.)
                    settingsGroup {
                        LAToggleRow(icon: "app.badge.checkmark.fill", color: .teal,
                                    title: "Start When App Opens",
                                    subtitle: "Resume any in-progress activity when you open PRVIO",
                                    isOn: $startOnOpen)
                    }

                    // All Live Activities the user has — each opens its own
                    // settings (auto-start + its own appearance) and shows live
                    // status.
                    Text("My Live Activities")
                        .font(AppFont.label)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, AppSpacing.xxs)

                    settingsGroup {
                        ForEach(Array(LiveActivityKind.allCases.enumerated()), id: \.element.id) { idx, kind in
                            KindNavRow(kind: kind)
                            if idx < LiveActivityKind.allCases.count - 1 { rowDivider }
                        }
                    }

                }

                Text("Live Activities appear on the Lock Screen and in the Dynamic Island while a task is running, and end automatically when it finishes.")
                    .font(.caption)
                    .foregroundStyle(Color.primary.opacity(0.3))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, AppSpacing.xxs)

                Spacer(minLength: 80)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Live Activities")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { systemEnabled = ActivityAuthorizationInfo().areActivitiesEnabled }
    }

    // MARK: - Preview card (kind selector + that kind's own live mock)

    private var previewCard: some View {
        VStack(spacing: 14) {
            // Kind chips — each activity previews as itself.
            HStack(spacing: 8) {
                ForEach(LiveActivityKind.allCases) { kind in
                    kindChip(kind)
                }
            }

            // Preview bound to the selected kind's EFFECTIVE appearance
            // (its own customization when enabled, otherwise the shared one).
            KindPreviewPane(
                kind: previewKind,
                lockScreen: LiveActivityPrefs.showOnLockScreen(for: previewKind.rawValue),
                dynamicIsland: LiveActivityPrefs.showDynamicIsland(for: previewKind.rawValue),
                showProgress: LiveActivityPrefs.showProgress(for: previewKind.rawValue),
                showETA: LiveActivityPrefs.showETA(for: previewKind.rawValue),
                showProperty: LiveActivityPrefs.showProperty(for: previewKind.rawValue),
                style: LiveActivityPrefs.islandStyle(for: previewKind.rawValue)
            )
            .id(previewKind)
            .transition(.opacity.combined(with: .scale(scale: 0.97)))

            NavigationLink {
                LiveActivityKindDetailView(kind: previewKind)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                    Text("Customize")
                }
                .font(AppFont.captionEmphasis)
                .foregroundStyle(enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.xs)
                .mediaGlass(in: Capsule(), interactive: true)
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
        }
        .animation(.snappy(duration: 0.3), value: previewKind)
        .animation(.easeInOut(duration: 0.2), value: enabled)
    }

    private func kindChip(_ kind: LiveActivityKind) -> some View {
        let selected = previewKind == kind
        return Button {
            HapticFeedback.selection()
            withAnimation(.snappy(duration: 0.3)) { previewKind = kind }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: kind.icon)
                    .font(AppFont.subheadline)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(kind.color)
                    .frame(width: 40, height: 40)
                    .mediaGlass(in: Circle(), interactive: true)
                    .overlay(
                        Circle().strokeBorder(
                            selected ? Color.primary.opacity(0.35) : Color.clear,
                            lineWidth: 1.2)
                    )
                Text(kind.title)
                    .font(AppFont.scaled(10, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : Color.secondaryTextColor)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var systemDisabledCard: some View {
        GlassCard {
            HStack(spacing: 14) {
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

    // MARK: - Reusable layout

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

// MARK: - Per-activity navigation row (opens its own settings + shows status)

private struct KindNavRow: View {
    let kind: LiveActivityKind
    @State private var isActive = false

    var body: some View {
        NavigationLink {
            LiveActivityKindDetailView(kind: kind)
        } label: {
            HStack(spacing: 12) {
                ColoredIconBadge(icon: kind.icon, color: kind.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title).font(AppFont.scaled(15)).foregroundStyle(.primary)
                    Text(kind.subtitle).font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(0.4))
                }
                Spacer()
                if isActive {
                    Text("Active")
                        .font(AppFont.captionEmphasis)
                        .foregroundStyle(Color.brandSuccess)
                        .padding(.horizontal, AppSpacing.sm).padding(.vertical, 3)
                        .background(Capsule().strokeBorder(Color.brandSuccess.opacity(0.45), lineWidth: 1))
                }
                Image(systemName: "chevron.right")
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(Color.primary.opacity(0.25))
            }
            .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear { isActive = LiveActivityService.shared.isActive(kind) }
    }
}

// MARK: - Per-activity detail (its own auto-start + appearance)

struct LiveActivityKindDetailView: View {
    let kind: LiveActivityKind

    @AppStorage private var autoStart: Bool
    @AppStorage private var custom: Bool
    @AppStorage private var lockScreen: Bool
    @AppStorage private var dynamicIsland: Bool
    @AppStorage private var showProgress: Bool
    @AppStorage private var showETA: Bool
    @AppStorage private var showProperty: Bool
    @AppStorage private var islandStyle: String
    @AppStorage private var priority: String
    @AppStorage private var notifyEnd: Bool

    @State private var isActive = false
    @State private var showEndConfirm = false

    init(kind: LiveActivityKind) {
        self.kind = kind
        let k = kind.rawValue
        let store = LiveActivityPrefs.store
        _autoStart     = AppStorage(wrappedValue: kind.defaultAuto, kind.storageKey, store: store)
        _custom        = AppStorage(wrappedValue: false, LiveActivityPrefs.customKey(k), store: store)
        _lockScreen    = AppStorage(wrappedValue: true, LiveActivityPrefs.scopedKey(LiveActivityPrefs.lockScreenKey, k), store: store)
        _dynamicIsland = AppStorage(wrappedValue: true, LiveActivityPrefs.scopedKey(LiveActivityPrefs.dynamicIslandKey, k), store: store)
        _showProgress  = AppStorage(wrappedValue: true, LiveActivityPrefs.scopedKey(LiveActivityPrefs.showProgressKey, k), store: store)
        _showETA       = AppStorage(wrappedValue: true, LiveActivityPrefs.scopedKey(LiveActivityPrefs.showETAKey, k), store: store)
        _showProperty  = AppStorage(wrappedValue: true, LiveActivityPrefs.scopedKey(LiveActivityPrefs.showPropertyKey, k), store: store)
        _islandStyle   = AppStorage(wrappedValue: DynamicIslandStyle.detailed.rawValue, LiveActivityPrefs.scopedKey(LiveActivityPrefs.islandStyleKey, k), store: store)
        _priority      = AppStorage(wrappedValue: "normal", LiveActivityPrefs.priorityKey(k), store: store)
        _notifyEnd     = AppStorage(wrappedValue: false, LiveActivityPrefs.notifyEndKey(k), store: store)
    }

    private var islandStyleValue: DynamicIslandStyle {
        DynamicIslandStyle(rawValue: islandStyle) ?? .detailed
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {

                statusCard

                // Live preview of THIS activity, reflecting its effective look
                // (its own customization when on, the shared one otherwise) —
                // updates instantly as the toggles below change.
                KindPreviewPane(
                    kind: kind,
                    lockScreen: custom ? lockScreen : LiveActivityPrefs.showOnLockScreen,
                    dynamicIsland: custom ? dynamicIsland : LiveActivityPrefs.showDynamicIsland,
                    showProgress: custom ? showProgress : LiveActivityPrefs.showProgress,
                    showETA: custom ? showETA : LiveActivityPrefs.showETA,
                    showProperty: custom ? showProperty : LiveActivityPrefs.showProperty,
                    style: custom ? islandStyleValue : LiveActivityPrefs.islandStyle
                )
                .animation(.snappy(duration: 0.28), value: appearanceToken)

                // The work session is always started by hand (task row or
                // watch), so it offers no auto-start switch.
                if kind.supportsAutoStart {
                    group {
                        LAToggleRow(icon: "play.circle.fill", color: kind.color,
                                    title: "Start automatically",
                                    subtitle: kind.subtitle,
                                    isOn: $autoStart)
                    }
                }

                // Favorite — the SAME pinned set the hub's active-card swipe
                // and context menu toggle (LiveActivityHubStore.favoriteKinds),
                // so idle kinds can be favorited from here too. The hub's
                // onAppear refresh picks the change up immediately.
                group {
                    favoriteRow
                }

                group {
                    LAToggleRow(icon: "slider.horizontal.3", color: .indigo,
                                title: "Custom appearance",
                                subtitle: "Give this activity its own look instead of the standard one",
                                isOn: $custom)
                }

                if custom {
                    Text("Show In")
                        .font(AppFont.label)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, AppSpacing.xxs)
                    group {
                        LAToggleRow(icon: "lock.fill", color: .blue,
                                    title: "Lock Screen",
                                    subtitle: "Show full details on the Lock Screen — off keeps a minimal banner",
                                    isOn: $lockScreen)
                        divider
                        LAToggleRow(icon: "capsule.fill", color: .purple,
                                    title: "Dynamic Island",
                                    subtitle: "Show live details around the camera — off keeps just the icon",
                                    isOn: $dynamicIsland)
                    }

                    Text("Display Options")
                        .font(AppFont.label)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, AppSpacing.xxs)
                    group {
                        LAToggleRow(icon: "chart.bar.fill", color: .green,
                                    title: "Progress Bar", subtitle: "Show a progress bar for ongoing tasks",
                                    isOn: $showProgress)
                        divider
                        LAToggleRow(icon: "clock.fill", color: .orange,
                                    title: "Estimated Time", subtitle: "Show ETA and remaining time",
                                    isOn: $showETA)
                        divider
                        LAToggleRow(icon: "house.fill", color: .teal,
                                    title: "Property Name", subtitle: "Include the property the activity belongs to",
                                    isOn: $showProperty)
                    }

                    if dynamicIsland {
                        Text("Dynamic Island")
                            .font(AppFont.label)
                            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, AppSpacing.xxs)
                        VStack(spacing: 14) {
                            Picker("", selection: $islandStyle) {
                                ForEach(DynamicIslandStyle.allCases) { style in
                                    Text(style.label).tag(style.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)
                            DynamicIslandMock(kind: kind, style: islandStyleValue, showProgress: showProgress)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppSpacing.xs)
                                .animation(.snappy(duration: 0.28), value: islandStyle)
                        }
                        .padding(AppSpacing.lg)
                        .liquidGlass(cornerRadius: AppRadius.lg)
                    }
                }

                // Hub priority — orders this kind within the hub and decides
                // whether its optional end notification carries a sound. It
                // deliberately claims nothing about how iOS itself presents
                // the activity.
                Text("la_hub_priority")
                    .font(AppFont.label)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, AppSpacing.xxs)
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Picker("", selection: $priority) {
                        Text("la_hub_priority_critical").tag("critical")
                        Text("la_hub_priority_high").tag("high")
                        Text("la_hub_priority_normal").tag("normal")
                        Text("la_hub_priority_silent").tag("silent")
                    }
                    .pickerStyle(.segmented)
                    Text("la_hub_priority_caption")
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(AppSpacing.lg)
                .liquidGlass(cornerRadius: AppRadius.lg)

                // Rules — real behaviour: the hub store posts a local
                // notification when this kind's activity ends or completes.
                Text("la_hub_rules")
                    .font(AppFont.label)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, AppSpacing.xxs)
                group {
                    LAToggleRow(icon: "bell.badge.fill", color: kind.color,
                                title: "la_hub_rule_notify_end",
                                subtitle: "la_hub_rule_notify_end_caption",
                                isOn: $notifyEnd)
                }

                Spacer(minLength: 80)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.large)
        .onAppear { isActive = LiveActivityService.shared.isActive(kind) }
        .onChange(of: custom) { _, on in
            if on { seedFromGlobal() }
            HapticFeedback.selection()
            LiveActivityService.shared.refreshAppearance()
        }
        .onChange(of: appearanceToken) { _, _ in
            LiveActivityService.shared.refreshAppearance()
        }
        .onChange(of: priority) { _, _ in
            HapticFeedback.selection()
        }
        .onChange(of: notifyEnd) { _, on in
            HapticFeedback.selection()
            // Make the rule real: without permission the end notification
            // could never appear, so ask the moment it's switched on.
            guard on else { return }
            UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        .confirmationDialog("End this Live Activity?", isPresented: $showEndConfirm, titleVisibility: .visible) {
            Button("End now", role: .destructive) {
                LiveActivityService.shared.end(kind)
                isActive = false
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var isFavorite: Bool {
        LiveActivityHubStore.shared.isFavorite(kind)
    }

    /// Star row mirroring the hub's favorite action for kinds with no
    /// active card to swipe.
    private var favoriteRow: some View {
        Button {
            HapticFeedback.selection()
            withAnimation(.snappy(duration: 0.25)) {
                LiveActivityHubStore.shared.toggleFavorite(kind)
            }
        } label: {
            HStack(spacing: 12) {
                ColoredIconBadge(icon: "star.fill", color: Color.brandGold)
                Text(isFavorite ? "la_hub_unfavorite" : "la_hub_favorite")
                    .font(AppFont.scaled(15)).foregroundStyle(.primary)
                Spacer()
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(isFavorite ? Color.brandGold : Color.primary.opacity(0.25))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isFavorite ? [.isSelected] : [])
    }

    private var statusCard: some View {
        HStack(spacing: 14) {
            ColoredIconBadge(icon: kind.icon, color: kind.color)
            VStack(alignment: .leading, spacing: 3) {
                Text(isActive ? "Running now" : "Not running")
                    .font(AppFont.subheadline).foregroundStyle(.primary)
                Text(isActive ? "Live on your Lock Screen and Dynamic Island"
                              : "Starts when there's activity to track")
                    .font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            }
            Spacer()
            if isActive {
                Button(role: .destructive) { showEndConfirm = true } label: {
                    Text("End").font(AppFont.captionEmphasis)
                        .foregroundStyle(Color.brandDanger)
                        .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.xs)
                        .mediaGlass(in: Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppSpacing.lg)
        .liquidGlass(cornerRadius: AppRadius.xl, thick: true)
    }

    /// Copies the current global appearance into this kind's scoped keys the
    /// first time custom is enabled, so it starts as a faithful copy the user
    /// can then tweak (rather than snapping to hardcoded defaults).
    private func seedFromGlobal() {
        guard !LiveActivityPrefs.store.bool(forKey: seedFlagKey) else { return }
        lockScreen    = LiveActivityPrefs.showOnLockScreen
        dynamicIsland = LiveActivityPrefs.showDynamicIsland
        showProgress  = LiveActivityPrefs.showProgress
        showETA       = LiveActivityPrefs.showETA
        showProperty  = LiveActivityPrefs.showProperty
        islandStyle   = LiveActivityPrefs.islandStyle.rawValue
        LiveActivityPrefs.store.set(true, forKey: seedFlagKey)
    }

    private var seedFlagKey: String { "prvio.la.seeded.\(kind.rawValue)" }

    private var appearanceToken: String {
        "\(custom)\(lockScreen)\(dynamicIsland)\(showProgress)\(showETA)\(showProperty)\(islandStyle)"
    }

    @ViewBuilder
    private func group<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }.liquidGlass(cornerRadius: AppRadius.lg)
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52)
    }
}

// MARK: - Toggle row
//
// Internal (not private): the Live Activities Hub reuses this exact row for
// its preserved master toggles and per-kind rules.

struct LAToggleRow: View {
    let icon: String
    let color: Color
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.scaled(15)).foregroundStyle(.primary)
                Text(subtitle).font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(0.4))
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden()
        }
        .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)
    }
}

// MARK: - Live Activity preview (kind-aware Lock Screen + Dynamic Island mocks)

/// One activity's full preview: Lock Screen card (or minimal banner) plus the
/// Dynamic Island pill, all themed to the kind and driven by explicit values so
/// callers can bind it to global, per-kind, or in-progress edits.
struct KindPreviewPane: View {
    let kind: LiveActivityKind
    var lockScreen = true
    var dynamicIsland = true
    var showProgress = true
    var showETA = true
    var showProperty = true
    var style: DynamicIslandStyle = .detailed

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                caption("LOCK SCREEN")
                KindLockScreenMock(kind: kind, full: lockScreen,
                                   showProgress: showProgress, showETA: showETA,
                                   showProperty: showProperty)
            }
            if dynamicIsland {
                VStack(spacing: 8) {
                    caption("DYNAMIC ISLAND")
                    DynamicIslandMock(kind: kind, style: style, showProgress: showProgress)
                        .frame(maxWidth: .infinity)
                        .animation(.snappy(duration: 0.28), value: style)
                }
            }
        }
        .animation(.snappy(duration: 0.28), value: lockScreen)
        .animation(.snappy(duration: 0.28), value: dynamicIsland)
    }

    private func caption(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(AppFont.scaled(10, weight: .bold))
            .foregroundStyle(Color.primary.opacity(0.3))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Lock Screen mock themed to an activity kind — the full notification card,
/// or the minimal banner when the Lock Screen option is off.
struct KindLockScreenMock: View {
    let kind: LiveActivityKind
    var full = true
    var showProgress = true
    var showETA = true
    var showProperty = true

    var body: some View {
        if full {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: kind.icon)
                        .font(AppFont.scaled(20)).foregroundStyle(kind.color)
                        .frame(width: 44, height: 44)
                        .glassRoundedRect(AppRadius.md)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.previewHeadline)
                            .font(AppFont.subheadline).foregroundStyle(.primary)
                        Text(showProperty ? "Lakeside House · PRVIO" : "PRVIO")
                            .font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(kind.previewStatus)
                            .font(AppFont.scaled(13, weight: .medium)).foregroundStyle(kind.color)
                        if showETA && kind.showsETA {
                            Text("ETA 14:30")
                                .font(AppFont.scaled(11)).foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                        }
                    }
                }
                if showProgress {
                    ProgressView(value: kind.previewProgress).tint(kind.color)
                }
            }
            .padding(AppSpacing.lg)
            .liquidGlass(cornerRadius: AppRadius.xl, thick: true)
        } else {
            HStack(spacing: 10) {
                Image(systemName: kind.icon)
                    .font(AppFont.subheadline).foregroundStyle(kind.color)
                Text(kind.previewHeadline)
                    .font(AppFont.scaled(13, weight: .medium)).foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
            .liquidGlass(cornerRadius: AppRadius.xl, thick: true)
        }
    }
}

// MARK: - Dynamic Island mock (black pill, themed to the kind + chosen density)

struct DynamicIslandMock: View {
    var kind: LiveActivityKind = .delivery
    let style: DynamicIslandStyle
    var showProgress: Bool = true

    var body: some View {
        Group {
            switch style {
            case .detailed:
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: kind.icon)
                            .font(AppFont.captionEmphasis).foregroundStyle(kind.color)
                        Text(kind.previewHeadline)
                            .font(AppFont.captionEmphasis).foregroundStyle(.white)
                        Spacer()
                        Text(kind.previewStatus)
                            .font(AppFont.captionStrong).foregroundStyle(kind.color)
                    }
                    if showProgress {
                        ProgressView(value: kind.previewProgress).tint(kind.color)
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            case .compact:
                HStack(spacing: 8) {
                    Image(systemName: kind.icon)
                        .font(AppFont.captionEmphasis).foregroundStyle(kind.color)
                    Text("\(Int(kind.previewProgress * 100))%")
                        .font(AppFont.scaled(13, weight: .bold, design: .rounded)).foregroundStyle(.white)
                }
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(Capsule().fill(Color.black))
            case .minimal:
                Image(systemName: kind.icon)
                    .font(AppFont.footnoteEmphasis).foregroundStyle(kind.color)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.black))
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
    }
}
