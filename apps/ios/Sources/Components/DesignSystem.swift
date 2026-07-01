import SwiftUI

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

enum AppFont {
    /// 11pt semibold — section headers, uppercase labels, tags.
    static let label = Font.system(size: 11, weight: .semibold)
    /// 11pt medium — small metadata (timestamps, counts).
    static let caption2 = Font.system(size: 11, weight: .medium)
    /// 12–13pt medium — secondary body text, list subtitles.
    static let caption = Font.system(size: 12, weight: .medium)
    /// 12pt semibold — chip/tag labels, compact emphasized captions.
    static let captionStrong = Font.system(size: 12, weight: .semibold)
    /// 13pt semibold — emphasized captions, chip labels.
    static let captionEmphasis = Font.system(size: 13, weight: .semibold)
    /// 14pt medium — standard secondary text.
    static let footnote = Font.system(size: 14, weight: .medium)
    /// 14pt semibold — emphasized secondary text, compact buttons.
    static let footnoteEmphasis = Font.system(size: 14, weight: .semibold)
    /// 14–15pt semibold — list row titles, form field values.
    static let subheadline = Font.system(size: 15, weight: .semibold)
    /// 15pt medium — default body text.
    static let body = Font.system(size: 15, weight: .medium)
    /// 16–17pt semibold — card titles, prominent row titles.
    static let headline = Font.system(size: 16, weight: .semibold)
    /// 18–20pt semibold — section titles, sheet headers.
    static let title3 = Font.system(size: 18, weight: .semibold)
    /// 22–26pt bold rounded — screen-level emphasis (stat numbers, hero values).
    static let title2 = Font.system(size: 22, weight: .bold, design: .rounded)
    /// 28–34pt bold rounded — large navigation titles, page headers.
    static let title = Font.system(size: 30, weight: .bold, design: .rounded)
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
}
