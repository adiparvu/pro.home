import SwiftUI
import UIKit

// MARK: - Design System
//
// Centralized typography, color-opacity, spacing, and corner-radius tokens.
// These codify the de facto scale already in use across the app (derived
// from a frequency audit of existing hardcoded values) so new and migrated
// code shares one consistent rhythm instead of hand-picking sizes per file.
//
// Existing call sites are not required to migrate immediately, but all new
// code and any file touched for other reasons should use these tokens
// instead of hardcoded `.font(.system(size:...))` / `Color.primary.opacity(...)`
// / `.padding(...)` / `cornerRadius:` literals.

// MARK: - Typography

/// Every token scales with the user's Dynamic Type setting — a plain
/// `Font.system(size:)` is frozen and silently opts the whole design system
/// out of accessibility text sizes. `Font.system` has no `relativeTo:`, so
/// each token routes its design size through `UIFontMetrics` anchored to the
/// nearest system text style; the sizes below are exact at the default
/// (Large) content size and grow/shrink with the user. The tokens are
/// computed properties on purpose: SwiftUI re-evaluates view bodies when
/// the content size category changes, so each access resolves against the
/// current setting.
enum AppFont {
    private static func scaled(_ size: CGFloat, weight: Font.Weight,
                               design: Font.Design = .default,
                               relativeTo style: UIFont.TextStyle) -> Font {
        Font.system(size: UIFontMetrics(forTextStyle: style).scaledValue(for: size),
                    weight: weight, design: design)
    }

    /// 11pt semibold — section headers, uppercase labels, tags.
    static var label: Font { scaled(11, weight: .semibold, relativeTo: .caption2) }
    /// 11pt medium — small metadata (timestamps, counts).
    static var caption2: Font { scaled(11, weight: .medium, relativeTo: .caption2) }
    /// 12–13pt medium — secondary body text, list subtitles.
    static var caption: Font { scaled(12, weight: .medium, relativeTo: .caption1) }
    /// 12pt semibold — chip/tag labels, compact emphasized captions.
    static var captionStrong: Font { scaled(12, weight: .semibold, relativeTo: .caption1) }
    /// 13pt semibold — emphasized captions, chip labels.
    static var captionEmphasis: Font { scaled(13, weight: .semibold, relativeTo: .footnote) }
    /// 14pt medium — standard secondary text.
    static var footnote: Font { scaled(14, weight: .medium, relativeTo: .footnote) }
    /// 14pt semibold — emphasized secondary text, compact buttons.
    static var footnoteEmphasis: Font { scaled(14, weight: .semibold, relativeTo: .footnote) }
    /// 14–15pt semibold — list row titles, form field values.
    static var subheadline: Font { scaled(15, weight: .semibold, relativeTo: .subheadline) }
    /// 15pt medium — default body text.
    static var body: Font { scaled(15, weight: .medium, relativeTo: .body) }
    /// 16–17pt semibold — card titles, prominent row titles.
    static var headline: Font { scaled(16, weight: .semibold, relativeTo: .headline) }
    /// 18–20pt semibold — section titles, sheet headers.
    static var title3: Font { scaled(18, weight: .semibold, relativeTo: .title3) }
    /// 20pt regular — large menu row labels (iMessage-style action menus).
    static var menuRow: Font { scaled(20, weight: .regular, relativeTo: .title3) }
    /// 22–26pt bold rounded — screen-level emphasis (stat numbers, hero values).
    static var title2: Font { scaled(22, weight: .bold, design: .rounded, relativeTo: .title2) }
    /// 28–34pt bold rounded — large navigation titles, page headers.
    static var title: Font { scaled(30, weight: .bold, design: .rounded, relativeTo: .largeTitle) }
}

// MARK: - Color opacity tiers

/// Semantic opacity tiers for `Color.primary`, matching the app's existing
/// visual hierarchy: hairline dividers, subtle fills, disabled/tertiary text,
/// secondary text, and emphasized text.
enum AppOpacity {
    /// Hairline borders, dividers between rows/sections.
    static let hairline: Double = 0.06
    /// Subtle background fills (pills, input backgrounds, card tints).
    static let subtleFill: Double = 0.07
    /// Disabled controls, placeholder/tertiary text.
    static let disabled: Double = 0.35
    /// Standard secondary text (subtitles, metadata).
    static let secondaryText: Double = 0.45
    /// Medium-emphasis text, slightly stronger than secondary.
    static let mediumText: Double = 0.5
    /// Emphasized text that's still not full-strength primary.
    static let emphasis: Double = 0.7
}

extension Color {
    /// `Color.primary` at the app's standard hairline-divider opacity.
    static var hairline: Color { Color.primary.opacity(AppOpacity.hairline) }
    /// `Color.primary` at the app's standard subtle-fill opacity.
    static var subtleFill: Color { Color.primary.opacity(AppOpacity.subtleFill) }
    /// `Color.primary` at the app's standard secondary-text opacity.
    static var secondaryTextColor: Color { Color.primary.opacity(AppOpacity.secondaryText) }
}

// MARK: - Brand colors

/// Named brand accents, consolidating the ~20 hand-typed near-duplicate
/// `Color(red:green:blue:)` triples found across the app into one source
/// of truth per hue.
extension Color {
    static let brandSuccess = Color(red: 0.25, green: 0.83, blue: 0.48)
    static let brandPrimaryBlue = Color(red: 0.25, green: 0.60, blue: 0.90)
    static let brandPurple = Color(red: 0.55, green: 0.45, blue: 0.95)
    static let brandWarning = Color(red: 1.0, green: 0.45, blue: 0.1)
    /// Error / destructive-emphasis red. Use for error states and danger
    /// accents; `.red` remains fine for system destructive roles/buttons.
    static let brandDanger = Color(red: 0.91, green: 0.3, blue: 0.24)
    /// Bright accent blue — the lighter, more saturated companion to
    /// `brandPrimaryBlue`, used for highlights and secondary accents.
    static let brandSkyBlue = Color(red: 0.35, green: 0.65, blue: 1.0)
}

// MARK: - Spacing

/// 4-point spacing rhythm matching the app's existing padding usage.
enum AppSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 6
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let base: CGFloat = 14
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
}

// MARK: - Corner radius

/// 4-point corner-radius rhythm matching the app's existing `cornerRadius:` usage.
enum AppRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    /// Large sheet/panel corners (iMessage-style translucent menus).
    static let sheet: CGFloat = 28
}
