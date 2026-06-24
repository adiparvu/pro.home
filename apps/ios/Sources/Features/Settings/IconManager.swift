import SwiftUI

// MARK: - Theme group (what the user picks — one entry per style)

enum AppIconThemeGroup: String, CaseIterable, Identifiable {
    case clasic
    case padure
    case smarald
    case roseGold
    case arctic
    case carbon
    case midnight
    case lavender
    case crimson
    case sunset

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .clasic:    return "Classic"
        case .padure:    return "Pădure"
        case .smarald:   return "Smarald"
        case .roseGold:  return "Rose Gold"
        case .arctic:    return "Arctic"
        case .carbon:    return "Carbon"
        case .midnight:  return "Midnight"
        case .lavender:  return "LavandR"
        case .crimson:   return "Crimson"
        case .sunset:    return "Sunset"
        }
    }

    var lightColors: [Color] {
        switch self {
        case .clasic:    return [Color(red:0.18,green:0.51,blue:1.0),   Color(red:0.08,green:0.38,blue:0.9)]
        case .padure:    return [Color(red:0.12,green:0.52,blue:0.28),  Color(red:0.06,green:0.32,blue:0.16)]
        case .smarald:   return [Color(red:0.05,green:0.72,blue:0.62),  Color(red:0.02,green:0.52,blue:0.44)]
        case .roseGold:  return [Color(red:0.95,green:0.58,blue:0.68),  Color(red:0.82,green:0.62,blue:0.28)]
        case .arctic:    return [Color(red:0.62,green:0.88,blue:0.98),  Color(red:0.38,green:0.72,blue:0.92)]
        case .carbon:    return [Color(red:0.75,green:0.75,blue:0.78),  Color(red:0.5,green:0.5,blue:0.52)]
        case .midnight:  return [Color(red:0.12,green:0.14,blue:0.35),  Color(red:0.06,green:0.07,blue:0.22)]
        case .lavender:  return [Color(red:0.6,green:0.38,blue:0.95),   Color(red:0.45,green:0.2,blue:0.85)]
        case .crimson:   return [Color(red:0.82,green:0.08,blue:0.14),  Color(red:0.62,green:0.04,blue:0.08)]
        case .sunset:    return [Color(red:1.0,green:0.65,blue:0.2),    Color(red:0.9,green:0.2,blue:0.2)]
        }
    }

    var darkColors: [Color] {
        switch self {
        case .clasic:    return [Color(red:0.08,green:0.12,blue:0.35),  Color(red:0.04,green:0.06,blue:0.22)]
        case .padure:    return [Color(red:0.06,green:0.28,blue:0.14),  Color(red:0.03,green:0.16,blue:0.08)]
        case .smarald:   return [Color(red:0.02,green:0.42,blue:0.36),  Color(red:0.01,green:0.28,blue:0.24)]
        case .roseGold:  return [Color(red:0.55,green:0.28,blue:0.38),  Color(red:0.38,green:0.28,blue:0.1)]
        case .arctic:    return [Color(red:0.15,green:0.38,blue:0.62),  Color(red:0.08,green:0.22,blue:0.48)]
        case .carbon:    return [Color(red:0.14,green:0.14,blue:0.16),  Color(red:0.06,green:0.06,blue:0.08)]
        case .midnight:  return [Color(red:0.06,green:0.08,blue:0.2),   Color(red:0.02,green:0.04,blue:0.14)]
        case .lavender:  return [Color(red:0.35,green:0.18,blue:0.72),  Color(red:0.22,green:0.1,blue:0.55)]
        case .crimson:   return [Color(red:0.52,green:0.04,blue:0.08),  Color(red:0.35,green:0.02,blue:0.04)]
        case .sunset:    return [Color(red:0.65,green:0.22,blue:0.06),  Color(red:0.42,green:0.08,blue:0.08)]
        }
    }

    var hasPair: Bool {
        switch self {
        case .midnight, .lavender, .crimson, .sunset: return false
        default: return true
        }
    }

    /// Returns the alternateIconName for UIApplication (nil = default icon)
    func iconName(isDarkMode: Bool) -> String? {
        switch self {
        case .clasic:
            return isDarkMode ? "AppIconClassicDark" : nil
        case .padure:
            return isDarkMode ? "AppIconForestDark" : "AppIconForest"
        case .smarald:
            return isDarkMode ? "AppIconEmeraldDark" : "AppIconEmerald"
        case .roseGold:
            return isDarkMode ? "AppIconRoseGoldDark" : "AppIconRoseGold"
        case .arctic:
            return isDarkMode ? "AppIconArcticDark" : "AppIconArctic"
        case .carbon:
            return isDarkMode ? "AppIconCarbonDark" : "AppIconCarbon"
        case .midnight:
            return "AppIconMidnight"
        case .lavender:
            return "AppIconLavender"
        case .crimson:
            return "AppIconCrimson"
        case .sunset:
            return "AppIconSunset"
        }
    }

    static func from(iconName: String?) -> AppIconThemeGroup {
        guard let name = iconName else { return .clasic }
        for group in AppIconThemeGroup.allCases {
            if group.iconName(isDarkMode: false) == name { return group }
            if group.iconName(isDarkMode: true) == name { return group }
        }
        return .clasic
    }
}

// MARK: - Color scheme watcher (placed as .background() in root view)

struct IconColorSchemeWatcher: View {
    @ObservedObject var iconManager: IconManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color.clear
            .onChange(of: colorScheme) { _, scheme in
                iconManager.colorSchemeChanged(isDark: scheme == .dark)
            }
            .onAppear {
                iconManager.colorSchemeChanged(isDark: colorScheme == .dark)
            }
    }
}

// MARK: - Icon Manager

@MainActor
final class IconManager: ObservableObject {
    @Published var selectedGroup: AppIconThemeGroup

    @AppStorage("prvio.selectedIconGroup") private var savedGroupId: String = "clasic"
    @AppStorage("prvio.autoSwitchIcon") var autoSwitch: Bool = true

    private var lastAppliedName: String? = UIApplication.shared.alternateIconName

    init() {
        let saved = AppIconThemeGroup(rawValue: UserDefaults.standard.string(forKey: "prvio.selectedIconGroup") ?? "clasic") ?? .clasic
        selectedGroup = saved
    }

    func apply(_ group: AppIconThemeGroup, isDark: Bool, force: Bool = false) {
        let name = group.iconName(isDarkMode: isDark)
        guard force || name != lastAppliedName else { return }
        UIApplication.shared.setAlternateIconName(name) { [weak self] error in
            if error == nil {
                Task { @MainActor [weak self] in
                    self?.lastAppliedName = name
                    self?.selectedGroup = group
                    self?.savedGroupId = group.rawValue
                }
            }
        }
    }

    func select(_ group: AppIconThemeGroup, isDark: Bool) {
        apply(group, isDark: isDark, force: true)
    }

    func colorSchemeChanged(isDark: Bool) {
        guard autoSwitch, selectedGroup.hasPair else { return }
        apply(selectedGroup, isDark: isDark)
    }
}
