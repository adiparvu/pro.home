import SwiftUI
import ActivityKit

// MARK: - Live Activity preferences
//
// Keys and accessors live in PRVIOLiveActivities.swift (compiled into both the
// app and the widgets target) so the extension that actually renders the
// activity reads the same app-group values this screen writes.

extension LiveActivityPrefs {
    static func autoStart(for kind: LiveActivityKind) -> Bool {
        switch kind {
        case .shopping:    return bool(autoShoppingKey, default: true)
        case .delivery:    return bool(autoDeliveryKey, default: true)
        case .maintenance: return bool(autoMaintKey,    default: false)
        case .plantCare:   return bool(autoPlantKey,    default: false)
        }
    }
}

enum LiveActivityKind: String, CaseIterable, Identifiable {
    case shopping, delivery, maintenance, plantCare
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .shopping:    return "Shopping list"
        case .delivery:    return "Deliveries"
        case .maintenance: return "Maintenance tasks"
        case .plantCare:   return "Plant care"
        }
    }
    var subtitle: LocalizedStringKey {
        switch self {
        case .shopping:    return "Track items as you check them off"
        case .delivery:    return "Follow a package until it arrives"
        case .maintenance: return "Watch progress on an active task"
        case .plantCare:   return "Watering progress for your plants"
        }
    }
    var icon: String {
        switch self {
        case .shopping:    return "cart.fill"
        case .delivery:    return "shippingbox.fill"
        case .maintenance: return "wrench.and.screwdriver.fill"
        case .plantCare:   return "leaf.fill"
        }
    }
    var color: Color {
        switch self {
        case .shopping:    return Color.brandSkyBlue
        case .delivery:    return .orange
        case .maintenance: return .teal
        case .plantCare:   return Color(red: 0.15, green: 0.80, blue: 0.40)
        }
    }
    var storageKey: String {
        switch self {
        case .shopping:    return LiveActivityPrefs.autoShoppingKey
        case .delivery:    return LiveActivityPrefs.autoDeliveryKey
        case .maintenance: return LiveActivityPrefs.autoMaintKey
        case .plantCare:   return LiveActivityPrefs.autoPlantKey
        }
    }
    var defaultAuto: Bool {
        switch self {
        case .shopping, .delivery: return true
        case .maintenance, .plantCare: return false
        }
    }
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
    @AppStorage(LiveActivityPrefs.startOnOpenKey, store: LiveActivityPrefs.store) private var startOnOpen   = false
    @AppStorage(LiveActivityPrefs.scheduleKey, store: LiveActivityPrefs.store)    private var startSchedule = false

    @State private var systemEnabled = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                PageHeader(titleKey: "Live Activities")

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
                    // Start behaviour
                    settingsGroup {
                        LAToggleRow(icon: "calendar.badge.clock", color: .indigo,
                                    title: "Start on a Schedule",
                                    subtitle: "Begin activities automatically at their scheduled time",
                                    isOn: $startSchedule)
                        rowDivider
                        LAToggleRow(icon: "app.badge.checkmark.fill", color: .teal,
                                    title: "Start When App Opens",
                                    subtitle: "Resume any in-progress activity when you open PRV HOUSE",
                                    isOn: $startOnOpen)
                    }

                    // All Live Activities the user has — each opens its own
                    // settings (auto-start + its own appearance) and shows live
                    // status.
                    Text("MY LIVE ACTIVITIES")
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

                    // Appearance
                    settingsGroup {
                        NavigationLink {
                            LiveActivityAppearanceView()
                        } label: {
                            HStack(spacing: 12) {
                                ColoredIconBadge(icon: "paintpalette.fill", color: .pink)
                                Text("Customize Appearance")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(AppFont.captionEmphasis)
                                    .foregroundStyle(Color.primary.opacity(0.25))
                            }
                            .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { systemEnabled = ActivityAuthorizationInfo().areActivitiesEnabled }
    }

    // MARK: - Preview card

    private var previewCard: some View {
        LiveActivityPreview()
            .opacity(enabled ? 1 : 0.4)
            .animation(.easeInOut(duration: 0.2), value: enabled)
    }

    private var systemDisabledCard: some View {
        GlassCard {
            HStack(spacing: 14) {
                ColoredIconBadge(icon: "exclamationmark.triangle.fill", color: .orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Live Activities are off in iOS")
                        .font(AppFont.footnoteEmphasis)
                    Text("Enable them in Settings › Face ID & Passcode and per-app to see them here.")
                        .font(.system(size: 12))
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
                    Text(kind.title).font(.system(size: 15)).foregroundStyle(.primary)
                    Text(kind.subtitle).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.4))
                }
                Spacer()
                if isActive {
                    Text("Active")
                        .font(AppFont.captionEmphasis)
                        .foregroundStyle(Color.brandSuccess)
                        .padding(.horizontal, AppSpacing.sm).padding(.vertical, 3)
                        .background(Color.brandSuccess.opacity(0.15), in: Capsule())
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
    }

    private var islandStyleValue: DynamicIslandStyle {
        DynamicIslandStyle(rawValue: islandStyle) ?? .detailed
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                PageHeader(titleKey: kind.title)

                statusCard

                group {
                    LAToggleRow(icon: "play.circle.fill", color: kind.color,
                                title: "Start automatically",
                                subtitle: kind.subtitle,
                                isOn: $autoStart)
                }

                group {
                    LAToggleRow(icon: "slider.horizontal.3", color: .indigo,
                                title: "Custom appearance",
                                subtitle: "Give this activity its own look instead of the shared settings",
                                isOn: $custom)
                }

                if custom {
                    Text("SHOW IN")
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

                    Text("DISPLAY OPTIONS")
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
                        Text("DYNAMIC ISLAND")
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
                            DynamicIslandMock(style: islandStyleValue, showProgress: showProgress)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppSpacing.xs)
                                .animation(.snappy(duration: 0.28), value: islandStyle)
                        }
                        .padding(AppSpacing.lg)
                        .liquidGlass(cornerRadius: AppRadius.lg)
                    }
                }

                Spacer(minLength: 80)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { isActive = LiveActivityService.shared.isActive(kind) }
        .onChange(of: custom) { _, on in
            if on { seedFromGlobal() }
            HapticFeedback.selection()
            LiveActivityService.shared.refreshAppearance()
        }
        .onChange(of: appearanceToken) { _, _ in
            LiveActivityService.shared.refreshAppearance()
        }
        .confirmationDialog("End this Live Activity?", isPresented: $showEndConfirm, titleVisibility: .visible) {
            Button("End now", role: .destructive) {
                LiveActivityService.shared.end(kind)
                isActive = false
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var statusCard: some View {
        HStack(spacing: 14) {
            ColoredIconBadge(icon: kind.icon, color: kind.color)
            VStack(alignment: .leading, spacing: 3) {
                Text(isActive ? "Running now" : "Not running")
                    .font(AppFont.subheadline).foregroundStyle(.primary)
                Text(isActive ? "Live on your Lock Screen and Dynamic Island"
                              : "Starts when there's activity to track")
                    .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            }
            Spacer()
            if isActive {
                Button(role: .destructive) { showEndConfirm = true } label: {
                    Text("End").font(AppFont.captionEmphasis)
                        .foregroundStyle(Color.brandDanger)
                        .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.xs)
                        .background(Color.brandDanger.opacity(0.14), in: Capsule())
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

private struct LAToggleRow: View {
    let icon: String
    let color: Color
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15)).foregroundStyle(.primary)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.4))
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden()
        }
        .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)
    }
}

// MARK: - Live Activity preview (mock Lock-Screen card)

struct LiveActivityPreview: View {
    @AppStorage(LiveActivityPrefs.lockScreenKey, store: LiveActivityPrefs.store)    private var lockScreen    = true
    @AppStorage(LiveActivityPrefs.dynamicIslandKey, store: LiveActivityPrefs.store) private var dynamicIsland = true
    @AppStorage(LiveActivityPrefs.showProgressKey, store: LiveActivityPrefs.store)  private var showProgress  = true
    @AppStorage(LiveActivityPrefs.showETAKey, store: LiveActivityPrefs.store)       private var showETA       = true
    @AppStorage(LiveActivityPrefs.showPropertyKey, store: LiveActivityPrefs.store)  private var showProperty  = true
    @AppStorage(LiveActivityPrefs.islandStyleKey, store: LiveActivityPrefs.store)   private var islandStyle   = DynamicIslandStyle.detailed.rawValue

    private var style: DynamicIslandStyle { DynamicIslandStyle(rawValue: islandStyle) ?? .detailed }

    var body: some View {
        VStack(spacing: 14) {
            // Lock Screen preview — full card, or the minimal banner when the
            // Lock Screen option is off.
            VStack(spacing: 6) {
                caption("LOCK SCREEN")
                if lockScreen {
                    lockScreenFull
                } else {
                    lockScreenMinimal
                }
            }

            // Dynamic Island preview — mirrors the Detailed / Compact / Minimal
            // choice, and disappears when the Dynamic Island option is off.
            if dynamicIsland {
                VStack(spacing: 8) {
                    caption("DYNAMIC ISLAND")
                    islandMock
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
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.primary.opacity(0.3))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Lock Screen mocks

    private var lockScreenFull: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                iconBadge
                VStack(alignment: .leading, spacing: 2) {
                    Text("Garden bench")
                        .font(AppFont.subheadline).foregroundStyle(.primary)
                    Text(showProperty ? "Lakeside House · DHL" : "DHL")
                        .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("In transit")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(.orange)
                    if showETA {
                        Text("ETA 14:30")
                            .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                    }
                }
            }
            if showProgress {
                ProgressView(value: 0.65).tint(.orange)
            }
        }
        .padding(AppSpacing.lg)
        .liquidGlass(cornerRadius: AppRadius.xl, thick: true)
    }

    private var lockScreenMinimal: some View {
        HStack(spacing: 10) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.orange)
            Text("Garden bench")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
        .liquidGlass(cornerRadius: AppRadius.xl, thick: true)
    }

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(Color.orange.opacity(0.2)).frame(width: 44, height: 44)
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 20)).foregroundStyle(.orange)
        }
    }

    private var islandMock: some View {
        DynamicIslandMock(style: style, showProgress: showProgress)
    }
}

// MARK: - Dynamic Island mock (black pill, styled to the chosen density)

/// Standalone so it can be shown both in the top preview and directly under the
/// Detailed / Compact / Minimal picker, giving in-context feedback as the user
/// taps each option.
struct DynamicIslandMock: View {
    let style: DynamicIslandStyle
    var showProgress: Bool = true

    var body: some View {
        Group {
            switch style {
            case .detailed:
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.orange)
                        Text("Garden bench")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        Spacer()
                        Text("In transit")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
                    }
                    if showProgress {
                        ProgressView(value: 0.65).tint(.orange)
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            case .compact:
                HStack(spacing: 8) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.orange)
                    Text("65%")
                        .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white)
                }
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(Capsule().fill(Color.black))
            case .minimal:
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.orange)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.black))
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
    }
}

// MARK: - Customize Appearance sub-screen

struct LiveActivityAppearanceView: View {
    @AppStorage(LiveActivityPrefs.lockScreenKey, store: LiveActivityPrefs.store)    private var lockScreen    = true
    @AppStorage(LiveActivityPrefs.dynamicIslandKey, store: LiveActivityPrefs.store) private var dynamicIsland = true
    @AppStorage(LiveActivityPrefs.showProgressKey, store: LiveActivityPrefs.store)  private var showProgress  = true
    @AppStorage(LiveActivityPrefs.showETAKey, store: LiveActivityPrefs.store)       private var showETA       = true
    @AppStorage(LiveActivityPrefs.showPropertyKey, store: LiveActivityPrefs.store)  private var showProperty  = true
    @AppStorage(LiveActivityPrefs.islandStyleKey, store: LiveActivityPrefs.store)   private var islandStyle   = DynamicIslandStyle.detailed.rawValue

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                PageHeader(titleKey: "Appearance")

                LiveActivityPreview()

                Text("SHOW IN")
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

                Text("DISPLAY OPTIONS")
                    .font(AppFont.label)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, AppSpacing.xxs)
                group {
                    LAToggleRow(icon: "chart.bar.fill", color: .green,
                                title: "Progress Bar",
                                subtitle: "Show a progress bar for ongoing tasks",
                                isOn: $showProgress)
                    divider
                    LAToggleRow(icon: "clock.fill", color: .orange,
                                title: "Estimated Time",
                                subtitle: "Show ETA and remaining time",
                                isOn: $showETA)
                    divider
                    LAToggleRow(icon: "house.fill", color: .teal,
                                title: "Property Name",
                                subtitle: "Include the property the activity belongs to",
                                isOn: $showProperty)
                }

                if dynamicIsland {
                    Text("DYNAMIC ISLAND")
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

                        // Live in-context preview: updates as the segment changes
                        // so the effect is visible right here at the picker.
                        DynamicIslandMock(style: islandStyleValue, showProgress: showProgress)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppSpacing.xs)
                            .animation(.snappy(duration: 0.28), value: islandStyle)

                        Text("Choose how much detail appears in the Dynamic Island when expanded.")
                            .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.4))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(AppSpacing.lg)
                    .liquidGlass(cornerRadius: AppRadius.lg)
                }

                Spacer(minLength: 80)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        // Any appearance change re-pushes running activities so the new look
        // applies immediately on the Lock Screen / Dynamic Island, not just at
        // the next natural content update.
        .onChange(of: appearanceToken) { _, _ in
            HapticFeedback.selection()
            LiveActivityService.shared.refreshAppearance()
        }
    }

    private var islandStyleValue: DynamicIslandStyle {
        DynamicIslandStyle(rawValue: islandStyle) ?? .detailed
    }

    /// Single value that changes whenever any appearance preference does, so one
    /// onChange can drive the live refresh.
    private var appearanceToken: String {
        "\(lockScreen)\(dynamicIsland)\(showProgress)\(showETA)\(showProperty)\(islandStyle)"
    }

    @ViewBuilder
    private func group<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }.liquidGlass(cornerRadius: AppRadius.lg)
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52)
    }
}
