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

    // Live Activity metrics — the rounded numerals in the Dynamic Island and
    // on Lock Screen cards (counts, percentages, timers). Rounded + bold like
    // Apple's own activities, and Dynamic-Type-relative like every token.
    /// Dynamic-Type-relative stand-in for a legacy `Font.system(size:)`
    /// literal: identical size/weight/design at the default (Large) content
    /// size, but scaling with the user's setting — anchored to the nearest
    /// system text style by size. New code should reach for the semantic
    /// tokens above; this exists so the ~1750 migrated legacy call sites
    /// gain accessibility without any visual change.
    static func scaled(_ size: CGFloat, weight: Font.Weight = .regular,
                       design: Font.Design = .default) -> Font {
        let style: UIFont.TextStyle = switch size {
        case ..<12:      .caption2
        case ..<14:      .caption1
        case ..<15:      .footnote
        case ..<16:      .subheadline
        case ..<18:      .body
        case ..<21:      .title3
        case ..<26:      .title2
        case ..<32:      .title1
        default:         .largeTitle
        }
        return scaled(size, weight: weight, design: design, relativeTo: style)
    }

    /// 12pt bold rounded — compact island trailing metric.
    static var metricSmall: Font { scaled(12, weight: .bold, design: .rounded, relativeTo: .caption1) }
    /// 15pt bold rounded — expanded island trailing metric.
    static var metric: Font { scaled(15, weight: .bold, design: .rounded, relativeTo: .subheadline) }
    /// 20pt bold rounded — Lock Screen hero metric (percent, timer).
    static var metricLarge: Font { scaled(20, weight: .bold, design: .rounded, relativeTo: .title3) }
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
    /// Soft tinted fill behind an icon in its accent color (icon discs).
    static let tintedFill: Double = 0.15

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
    /// Vibrant magenta-pink — the warm stop of the story-ring "unseen"
    /// gradient; usable for other semantic pink accents.
    static let brandPink = Color(red: 0.88, green: 0.19, blue: 0.42)

    /// System-teal anchor — work-session timers and other "focus" accents
    /// (codifies the `.teal` already used by the session Live Activity).
    static let brandTeal = Color(red: 0.19, green: 0.69, blue: 0.78)

    /// Electric gold — energy readings (codifies the hue the IoT current
    /// sensor tiles already use).
    static let brandGold = Color(red: 0.95, green: 0.75, blue: 0.15)

    /// Soft indigo — the conversations list's accent (unread dots, active
    /// times, the ARIA card gradient).
    static let brandIndigo = Color(red: 0.42, green: 0.47, blue: 0.98)
}

// MARK: - Smart-home warm glass theme

/// Tokens for the smart-home surfaces (home tab, device page, climate page)
/// — the one deliberately dark-warm skin in the app: a blurred property
/// photo under a warm-brown overlay, near-white warm text, cream contrast
/// cards, and a single amber accent. These surfaces do NOT follow
/// light/dark mode (the photo backdrop is the sanctioned exception); text
/// always uses the `smartText*` tokens for contrast over the backdrop.
/// Nothing here reaches for `Color.accentColor` or the brand blues.
enum SmartHomeTheme {
    /// Card corner radius on the smart-home surfaces (the reference's ~26pt).
    static let cardRadius: CGFloat = 26
    /// Filter/selector chip corner radius (the reference's ~14pt).
    static let chipRadius: CGFloat = 14
    /// Blur applied to the property cover photo behind these surfaces.
    static let backdropBlur: CGFloat = 40
    /// Radial glow opacity behind device icons (the lamp-photo mood).
    static let glowOpacity: Double = 0.25
    /// The vertical pill toggle's fixed footprint.
    static let pillToggleSize = CGSize(width: 30, height: 52)

    // MARK: Device card state (on / off)

    /// How much of the radial glow survives when the device is OFF — the
    /// lamp is out, only an ember of the mood remains.
    static let glowOffOpacity: Double = 0.15
    /// The reference's big light-weight live value (brightness %, sensor
    /// reading) on device hero cards.
    static let heroValueSize: CGFloat = 30

    // MARK: Widget strip (the classic dashboard's survivor, re-dressed)

    /// Corner radius for the dashboard's widget cards — tighter than the
    /// hero cards (the widgets are denser), same glass language.
    static let widgetCardRadius: CGFloat = 20

    // MARK: Motion

    /// Pressed-card scale for the shared press micro-interaction.
    static let pressedScale: CGFloat = 0.97
    /// The hero grid's one-time entrance: rise distance per card…
    static let entranceRise: CGFloat = 8
    /// …and the per-card stagger delay (seconds).
    static let entranceStagger: Double = 0.035

    // MARK: Backdrop ambient light (static, two RadialGradients — no blur)

    /// The warm lamp-light pooling top-leading behind the greeting.
    static let ambientTopGlowOpacity: Double = 0.18
    /// The deeper ember warmth bottom-trailing, balancing the page.
    static let ambientBottomGlowOpacity: Double = 0.14
    /// Deep ember red-brown — the bottom ambient glow's hue (warmer and
    /// darker than `smartAmber`, so the two glows read as different lights).
    static let ambientEmber = Color(red: 0.55, green: 0.28, blue: 0.12)
    /// Radius of the top-leading amber pool, in points.
    static let ambientTopGlowRadius: CGFloat = 420
    /// Radius of the bottom-trailing ember pool, in points.
    static let ambientBottomGlowRadius: CGFloat = 460

    // MARK: Glass card depth (fill gradient, hairline, lift shadow)

    /// Glass fill gradient, top edge — laid over `.ultraThinMaterial`.
    static let glassFillTopOpacity: Double = 0.10
    /// Glass fill gradient, bottom edge.
    static let glassFillBottomOpacity: Double = 0.04
    /// Hairline stroke where light catches the card's top-leading edge.
    static let glassStrokeTopOpacity: Double = 0.22
    /// Hairline stroke fading out toward the bottom-trailing edge.
    static let glassStrokeBottomOpacity: Double = 0.03
    /// Soft lift shadow under every glass card.
    static let cardShadowOpacity: Double = 0.15
    static let cardShadowRadius: CGFloat = 10
    static let cardShadowY: CGFloat = 4

    /// The glass card's fill: a subtle white gradient (brighter at the top,
    /// like light entering the pane) instead of a flat wash.
    static var glassFillGradient: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(glassFillTopOpacity),
                     Color.white.opacity(glassFillBottomOpacity)],
            startPoint: .top, endPoint: .bottom)
    }

    /// The 1pt hairline around glass cards — light catching the top edge,
    /// vanishing toward the bottom.
    static var glassStrokeGradient: LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(glassStrokeTopOpacity),
                     Color.white.opacity(glassStrokeBottomOpacity)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: Empty temperature dial (honest no-reading state)

    /// The empty dial ring: a faint warm gradient instead of dead gray.
    static let dialEmptyAmberOpacity: Double = 0.30
    static let dialEmptyFadeOpacity: Double = 0.08
    static var dialEmptyGradient: LinearGradient {
        LinearGradient(
            colors: [Color.smartAmber.opacity(dialEmptyAmberOpacity),
                     Color.white.opacity(dialEmptyFadeOpacity)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: Now-playing media card

    /// Artwork footprint on the media card.
    static let mediaArtSize: CGFloat = 64
    /// Artwork corner radius (continuous).
    static let mediaArtRadius: CGFloat = 14
    /// Soft shadow that lifts the artwork off the glass.
    static let mediaArtShadowOpacity: Double = 0.25
    static let mediaArtShadowRadius: CGFloat = 6
    static let mediaArtShadowY: CGFloat = 3
    /// The 3pt progress capsule's amber→cream fill.
    static var mediaProgressGradient: LinearGradient {
        LinearGradient(colors: [.smartAmber, .smartCream],
                       startPoint: .leading, endPoint: .trailing)
    }

    /// Fallback backdrop when the property has no cover photo yet:
    /// dark bronze, top #3A2E22 → bottom #14100C.
    static var fallbackGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.227, green: 0.180, blue: 0.133),
                     Color(red: 0.078, green: 0.063, blue: 0.047)],
            startPoint: .top, endPoint: .bottom)
    }

    // MARK: Estate scene gradients (Estate OS E1)
    //
    // Per-`SpaceKind` warm backdrops for spaces without a photo — each as
    // dark as `fallbackGradient` so the `smartText*` tokens keep AA
    // contrast, tinted toward its scene while staying in the warm family.
    // House and custom spaces reuse `fallbackGradient` (the home's own hue).

    /// Garden: warm olive-green, top #293418 → bottom #0D1108.
    static var sceneGardenGradient: LinearGradient {
        sceneGradient(Color(red: 0.161, green: 0.204, blue: 0.094),
                      Color(red: 0.051, green: 0.067, blue: 0.031))
    }
    /// Pond: deep warm teal, top #17333A → bottom #081114.
    static var scenePondGradient: LinearGradient {
        sceneGradient(Color(red: 0.090, green: 0.200, blue: 0.227),
                      Color(red: 0.031, green: 0.067, blue: 0.078))
    }
    /// Forest: deep fir green, top #1A2C1C → bottom #08100A.
    static var sceneForestGradient: LinearGradient {
        sceneGradient(Color(red: 0.102, green: 0.173, blue: 0.110),
                      Color(red: 0.031, green: 0.063, blue: 0.039))
    }
    /// Greenhouse: sunlit olive-gold, top #37361B → bottom #12120A.
    static var sceneGreenhouseGradient: LinearGradient {
        sceneGradient(Color(red: 0.216, green: 0.212, blue: 0.106),
                      Color(red: 0.071, green: 0.071, blue: 0.039))
    }
    /// Garage: warm slate, top #2E2B28 → bottom #100F0E.
    static var sceneGarageGradient: LinearGradient {
        sceneGradient(Color(red: 0.180, green: 0.169, blue: 0.157),
                      Color(red: 0.063, green: 0.059, blue: 0.055))
    }
    /// Basement: deep umber, top #281E16 → bottom #0B0806.
    static var sceneBasementGradient: LinearGradient {
        sceneGradient(Color(red: 0.157, green: 0.118, blue: 0.086),
                      Color(red: 0.043, green: 0.031, blue: 0.024))
    }

    private static func sceneGradient(_ top: Color, _ bottom: Color) -> LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    // MARK: Space detail hero (Estate OS E2)

    /// Breathing room of pure scene above the space page's floating title.
    static let spaceHeroBreath: CGFloat = 140
    /// The free-floating space name — large and light, tracking tight.
    static let spaceNameSize: CGFloat = 36
    static let spaceNameTracking: CGFloat = -0.5
    /// Metric tile live-value size on the space page.
    static let spaceMetricValueSize: CGFloat = 22

    /// Warm-brown darkening laid over the blurred cover photo — dark enough
    /// that warm-white text keeps AA contrast, light enough that the photo's
    /// texture survives (the ambient glows add the rest of the mood).
    static var overlayGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.165, green: 0.122, blue: 0.078).opacity(0.40),
                     Color(red: 0.078, green: 0.059, blue: 0.039).opacity(0.60)],
            startPoint: .top, endPoint: .bottom)
    }
}

extension Color {
    /// #F2ECE3 — the near-white warm contrast card (the reference's "Alarm"
    /// card); pair with `smartInk` text only.
    static let smartCream = Color(red: 0.949, green: 0.925, blue: 0.890)
    /// #E1975F — the single amber accent: toggles, dial arcs, glows.
    static let smartAmber = Color(red: 0.882, green: 0.592, blue: 0.373)
    /// White at 8% — the flat glass fill laid over `.ultraThinMaterial` on
    /// chips, slim rows, and small tiles. Full-size cards use
    /// `SmartHomeTheme.glassFillGradient` instead.
    static let smartGlassFill = Color.white.opacity(0.08)
    /// #F7F3ED — warm-white primary text over the dark backdrop.
    static let smartTextPrimary = Color(red: 0.969, green: 0.953, blue: 0.929)
    /// Secondary text over the backdrop — the warm white at 60%.
    static let smartTextSecondary = Color(red: 0.969, green: 0.953, blue: 0.929).opacity(0.6)
    /// #2B241C — warm near-black ink for text ON `smartCream` surfaces.
    static let smartInk = Color(red: 0.169, green: 0.141, blue: 0.110)
    /// Secondary ink on cream surfaces.
    static let smartInkSecondary = Color(red: 0.169, green: 0.141, blue: 0.110).opacity(0.6)
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
