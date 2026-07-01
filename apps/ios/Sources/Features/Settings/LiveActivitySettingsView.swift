import SwiftUI
import ActivityKit

// MARK: - Live Activity preferences (shared keys)
//
// The settings screen writes these via @AppStorage; LiveActivityService reads
// them through the static accessors below so the two stay in sync.

enum LiveActivityPrefs {
    static let enabledKey       = "prvio.la.enabled"
    static let startOnOpenKey   = "prvio.la.startOnOpen"
    static let scheduleKey      = "prvio.la.schedule"
    static let lockScreenKey    = "prvio.la.lockScreen"
    static let dynamicIslandKey = "prvio.la.dynamicIsland"
    static let showProgressKey  = "prvio.la.showProgress"
    static let showETAKey       = "prvio.la.showETA"
    static let showPropertyKey  = "prvio.la.showProperty"
    static let islandStyleKey   = "prvio.la.islandStyle"
    static let autoShoppingKey  = "prvio.la.auto.shopping"
    static let autoDeliveryKey  = "prvio.la.auto.delivery"
    static let autoMaintKey     = "prvio.la.auto.maintenance"
    static let autoPlantKey     = "prvio.la.auto.plant"

    private static func bool(_ key: String, default def: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? def
    }

    static var isEnabled:       Bool { bool(enabledKey,       default: true) }
    static var startOnOpen:     Bool { bool(startOnOpenKey,   default: false) }
    static var startOnSchedule: Bool { bool(scheduleKey,      default: false) }
    static var showOnLockScreen:Bool { bool(lockScreenKey,    default: true) }
    static var showDynamicIsland:Bool { bool(dynamicIslandKey, default: true) }
    static var showProgress:    Bool { bool(showProgressKey,  default: true) }
    static var showETA:         Bool { bool(showETAKey,       default: true) }
    static var showProperty:    Bool { bool(showPropertyKey,  default: true) }

    static func autoStart(for kind: LiveActivityKind) -> Bool {
        switch kind {
        case .shopping:    return bool(autoShoppingKey, default: true)
        case .delivery:    return bool(autoDeliveryKey, default: true)
        case .maintenance: return bool(autoMaintKey,    default: false)
        case .plantCare:   return bool(autoPlantKey,    default: false)
        }
    }

    static var islandStyle: DynamicIslandStyle {
        DynamicIslandStyle(rawValue: UserDefaults.standard.string(forKey: islandStyleKey) ?? "") ?? .detailed
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
        case .shopping:    return Color(red: 0.35, green: 0.65, blue: 1.0)
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

enum DynamicIslandStyle: String, CaseIterable, Identifiable {
    case detailed, compact, minimal
    var id: String { rawValue }
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
    @AppStorage(LiveActivityPrefs.enabledKey)     private var enabled       = true
    @AppStorage(LiveActivityPrefs.startOnOpenKey) private var startOnOpen   = false
    @AppStorage(LiveActivityPrefs.scheduleKey)    private var startSchedule = false

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

                    // Per-activity auto-start
                    Text("AUTOMATICALLY START")
                        .font(AppFont.label)
                        .foregroundStyle(Color.primary.opacity(0.35))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)

                    settingsGroup {
                        ForEach(Array(LiveActivityKind.allCases.enumerated()), id: \.element.id) { idx, kind in
                            AutoStartRow(kind: kind)
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
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Live Activities appear on the Lock Screen and in the Dynamic Island while a task is running, and end automatically when it finishes.")
                    .font(.caption)
                    .foregroundStyle(Color.primary.opacity(0.3))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)

                Spacer(minLength: 80)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
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
                        .foregroundStyle(Color.primary.opacity(0.5))
                }
                Spacer()
            }
        }
    }

    // MARK: - Reusable layout

    @ViewBuilder
    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .liquidGlass(cornerRadius: 16)
    }

    private var rowDivider: some View {
        Rectangle().fill(Color.primary.opacity(0.05))
            .frame(height: 0.5).padding(.leading, 52)
    }
}

// MARK: - Auto-start row (reads/writes its own key)

private struct AutoStartRow: View {
    let kind: LiveActivityKind
    @State private var on = false

    var body: some View {
        LAToggleRow(icon: kind.icon, color: kind.color,
                    title: kind.title, subtitle: kind.subtitle,
                    isOn: Binding(
                        get: { on },
                        set: { newVal in
                            on = newVal
                            UserDefaults.standard.set(newVal, forKey: kind.storageKey)
                            HapticFeedback.selection()
                        }))
        .onAppear {
            on = UserDefaults.standard.object(forKey: kind.storageKey) as? Bool ?? kind.defaultAuto
        }
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
        .padding(.horizontal, 14).padding(.vertical, 12)
    }
}

// MARK: - Live Activity preview (mock Lock-Screen card)

struct LiveActivityPreview: View {
    @AppStorage(LiveActivityPrefs.showProgressKey) private var showProgress = true
    @AppStorage(LiveActivityPrefs.showETAKey)      private var showETA      = true
    @AppStorage(LiveActivityPrefs.showPropertyKey) private var showProperty = true

    var body: some View {
        VStack(spacing: 8) {
            Text("PREVIEW")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.primary.opacity(0.3))
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.orange.opacity(0.2)).frame(width: 44, height: 44)
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 20)).foregroundStyle(.orange)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Garden bench")
                            .font(AppFont.subheadline).foregroundStyle(.primary)
                        if showProperty {
                            Text("Lakeside House · DHL")
                                .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.5))
                        } else {
                            Text("DHL").font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.5))
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("In transit")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(.orange)
                        if showETA {
                            Text("ETA 14:30")
                                .font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.45))
                        }
                    }
                }
                if showProgress {
                    ProgressView(value: 0.65)
                        .tint(.orange)
                }
            }
            .padding(16)
            .liquidGlass(cornerRadius: 20, thick: true)
        }
    }
}

// MARK: - Customize Appearance sub-screen

struct LiveActivityAppearanceView: View {
    @AppStorage(LiveActivityPrefs.lockScreenKey)    private var lockScreen    = true
    @AppStorage(LiveActivityPrefs.dynamicIslandKey) private var dynamicIsland = true
    @AppStorage(LiveActivityPrefs.showProgressKey)  private var showProgress  = true
    @AppStorage(LiveActivityPrefs.showETAKey)       private var showETA       = true
    @AppStorage(LiveActivityPrefs.showPropertyKey)  private var showProperty  = true
    @AppStorage(LiveActivityPrefs.islandStyleKey)   private var islandStyle   = DynamicIslandStyle.detailed.rawValue

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                PageHeader(titleKey: "Appearance")

                LiveActivityPreview()

                Text("SHOW IN")
                    .font(AppFont.label)
                    .foregroundStyle(Color.primary.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 4)
                group {
                    LAToggleRow(icon: "lock.fill", color: .blue,
                                title: "Lock Screen",
                                subtitle: "Show the activity banner on the Lock Screen",
                                isOn: $lockScreen)
                    divider
                    LAToggleRow(icon: "capsule.fill", color: .purple,
                                title: "Dynamic Island",
                                subtitle: "Show live status around the camera",
                                isOn: $dynamicIsland)
                }

                Text("DISPLAY OPTIONS")
                    .font(AppFont.label)
                    .foregroundStyle(Color.primary.opacity(0.35))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 4)
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
                        .foregroundStyle(Color.primary.opacity(0.35))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 4)
                    VStack(spacing: 12) {
                        Picker("", selection: $islandStyle) {
                            ForEach(DynamicIslandStyle.allCases) { style in
                                Text(style.label).tag(style.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text("Choose how much detail appears in the Dynamic Island when expanded.")
                            .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.4))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(16)
                    .liquidGlass(cornerRadius: 16)
                }

                Spacer(minLength: 80)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func group<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }.liquidGlass(cornerRadius: 16)
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52)
    }
}
