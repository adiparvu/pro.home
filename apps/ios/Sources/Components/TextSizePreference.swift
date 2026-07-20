import SwiftUI
import Observation

// MARK: - In-app text size (Settings → Aspect → Mărimea textului)
//
// The single authority for the app's Dynamic Type override — PRVIO's
// equivalent of iOS Settings → Display & Brightness → Text Size, scoped to
// this app only. `override == nil` (the default) follows the system setting;
// a non-nil value pins every screen to that size.
//
// The override reaches text through two cooperating paths, both of which
// collapse to "exactly the system behavior" while `override` is nil:
//
// 1. `.appTextSize()` at the app root re-exports the SwiftUI environment:
//    `dynamicTypeSize = override ?? system`. This drives every native
//    text-style font (`.font(.body)`, system controls, `relativeTo:` fonts).
// 2. `AppTextScale.shared` (the hook in DesignSystem.swift, shared with the
//    widget target) carries the matching `UIContentSizeCategory`, because
//    the `AppFont` tokens resolve through `UIFontMetrics`, which follows the
//    app-global category and never sees a SwiftUI environment override.
//    AppFont reads the hook inside view bodies, so Observation re-resolves
//    every token call site the moment the override changes.
//
// Persistence: UserDefaults "app.textSize" stores a STABLE case name
// ("xLarge", "accessibility3", …) — never an ordinal that could silently
// remap if the case list ever changes. Absent key = follow the system.

@MainActor
@Observable
final class TextSizePreference {
    static let shared = TextSizePreference()

    private static let storageKey = "app.textSize"

    /// The pinned Dynamic Type size; nil follows the system (the default).
    /// Persisted across launches.
    var override: DynamicTypeSize? {
        didSet {
            if let override {
                UserDefaults.standard.set(Self.storageName(for: override),
                                          forKey: Self.storageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.storageKey)
            }
            pushToFontSystem()
        }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey) ?? ""
        override = Self.size(forStorageName: stored)
        // didSet does not fire during init — prime the AppFont hook so the
        // persisted size applies from the very first rendered frame.
        pushToFontSystem()
    }

    /// Mirrors the override into the design-system hook that `AppFont`
    /// resolves its `UIFontMetrics` against (nil = system category).
    private func pushToFontSystem() {
        AppTextScale.shared.category = override.map(Self.contentSizeCategory(for:))
    }

    // MARK: Size catalog

    /// The seven standard Dynamic Type sizes, smallest → largest — the
    /// slider's default range (matches iOS Settings → Text Size).
    static let standardSizes: [DynamicTypeSize] = [
        .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
    ]

    /// The five accessibility sizes, revealed by the "Mărimi mai mari
    /// pentru accesibilitate" toggle — exactly like iOS does.
    static let accessibilitySizes: [DynamicTypeSize] = [
        .accessibility1, .accessibility2, .accessibility3,
        .accessibility4, .accessibility5,
    ]

    /// All twelve sizes, smallest → largest.
    static let allSizes: [DynamicTypeSize] = standardSizes + accessibilitySizes

    /// True while the pinned size (if any) is an accessibility size.
    var isAccessibilityOverride: Bool { override?.isAccessibilitySize ?? false }

    /// Settings-row value, stated the way iOS states a row's value:
    /// "Sistem" while following the system, else the chosen size's name.
    var rowValue: String {
        guard let override else { return String(localized: "textsize_value_system") }
        return Self.localizedName(for: override)
    }

    // MARK: Mappings

    /// Stable persistence name for a size (survives OS case-list growth;
    /// unknown stored names simply fall back to "follow the system").
    static func storageName(for size: DynamicTypeSize) -> String {
        switch size {
        case .xSmall:         "xSmall"
        case .small:          "small"
        case .medium:         "medium"
        case .large:          "large"
        case .xLarge:         "xLarge"
        case .xxLarge:        "xxLarge"
        case .xxxLarge:       "xxxLarge"
        case .accessibility1: "accessibility1"
        case .accessibility2: "accessibility2"
        case .accessibility3: "accessibility3"
        case .accessibility4: "accessibility4"
        case .accessibility5: "accessibility5"
        @unknown default:     "large"
        }
    }

    static func size(forStorageName name: String) -> DynamicTypeSize? {
        allSizes.first { storageName(for: $0) == name }
    }

    /// The UIKit category equivalent — what `UIFontMetrics` (and therefore
    /// every `AppFont` token) scales against.
    static func contentSizeCategory(for size: DynamicTypeSize) -> UIContentSizeCategory {
        switch size {
        case .xSmall:         .extraSmall
        case .small:          .small
        case .medium:         .medium
        case .large:          .large
        case .xLarge:         .extraLarge
        case .xxLarge:        .extraExtraLarge
        case .xxxLarge:       .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default:     .large
        }
    }

    /// Human-readable size name — the settings-row value and the slider's
    /// VoiceOver value.
    static func localizedName(for size: DynamicTypeSize) -> String {
        switch size {
        case .xSmall:         String(localized: "textsize_size_xsmall")
        case .small:          String(localized: "textsize_size_small")
        case .medium:         String(localized: "textsize_size_medium")
        case .large:          String(localized: "textsize_size_large")
        case .xLarge:         String(localized: "textsize_size_xlarge")
        case .xxLarge:        String(localized: "textsize_size_xxlarge")
        case .xxxLarge:       String(localized: "textsize_size_xxxlarge")
        case .accessibility1: String(localized: "textsize_size_ax1")
        case .accessibility2: String(localized: "textsize_size_ax2")
        case .accessibility3: String(localized: "textsize_size_ax3")
        case .accessibility4: String(localized: "textsize_size_ax4")
        case .accessibility5: String(localized: "textsize_size_ax5")
        @unknown default:     String(localized: "textsize_size_large")
        }
    }
}

// MARK: - Root application

/// Re-exports the Dynamic Type environment as `override ?? system`.
///
/// Reading `@Environment(\.dynamicTypeSize)` ABOVE the modifier's own
/// `.dynamicTypeSize(...)` write yields the true system value, so:
/// - override == nil → the system size is re-applied unchanged (identity;
///   system setting changes keep flowing through live), and
/// - override != nil → the whole subtree — including sheets and covers
///   presented from it — is pinned to the chosen size.
///
/// Reading `TextSizePreference.shared.override` here registers Observation,
/// so the environment re-applies the moment the user moves the slider.
private struct AppTextSizeModifier: ViewModifier {
    @Environment(\.dynamicTypeSize) private var systemSize

    func body(content: Content) -> some View {
        content.dynamicTypeSize(TextSizePreference.shared.override ?? systemSize)
    }
}

extension View {
    /// Apply ONCE at the app root (next to `.preferredColorScheme` in
    /// PRVIOApp) — the in-app text-size preference, following the system
    /// while no override is set.
    func appTextSize() -> some View { modifier(AppTextSizeModifier()) }
}
