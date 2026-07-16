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

/// In-app text-size override hook (Settings → Aspect → Mărimea textului).
///
/// `UIFontMetrics` follows the app-global content size category and never
/// sees a SwiftUI `.dynamicTypeSize` environment override, so the `AppFont`
/// tokens resolve against this hook instead: nil (the default, and always
/// the case in the widget/watch extensions, where nothing ever writes it)
/// means "follow the system"; the app target's `TextSizePreference` mirrors
/// its persisted override here.
///
/// Observable on purpose: AppFont tokens read `category` inside view bodies,
/// so every token call site re-resolves the moment the override changes —
/// the same invalidation the system gives us for free on a system-wide
/// content-size change. Main-thread writes only.
@Observable
final class AppTextScale {
    static let shared = AppTextScale()

    /// The pinned content size category; nil follows the system.
    var category: UIContentSizeCategory?
}

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
        let metrics = UIFontMetrics(forTextStyle: style)
        // In-app override first (Settings → Aspect → Mărimea textului);
        // without one, the system's own category applies — the pre-existing
        // behavior, byte for byte.
        let resolved: CGFloat = if let category = AppTextScale.shared.category {
            metrics.scaledValue(for: size,
                                compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
        } else {
            metrics.scaledValue(for: size)
        }
        return Font.system(size: resolved, weight: weight, design: design)
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

// DEPRECATED (Liquid Glass re-skin): the live smart-home surfaces moved to
// the app's native adaptive glass language (`liquidGlass`/`GlassCard`,
// `.primary`/`.secondary`, the mood backdrop) and no longer read these
// tokens. Only the retired, unreferenced Digital Twin files still compile
// against `SmartHomeTheme`/`smart*`; this whole block is deleted with them
// in the twin cleanup pass. Do not use in new code.

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

// MARK: - Mood palettes (the living app background)

/// Full-screen background palettes for the app's seven moods (dimineața /
/// zi / apus / noapte / ploaie / iarnă / eveniment) — the glassmorphism
/// ground every adaptive Liquid Glass component sits on. Each palette is a
/// quiet vertical wash plus at most two static ambient radial accents (no
/// blur, no animation — compositor cost stays near a flat fill).
/// `AppBackdrop` renders these; `AppMood` maps mood → palette.
///
/// Every palette declares the `ColorScheme` the app should adopt while it
/// shows: morning/day/sunset/rain/winter are light grounds and night/event
/// are dark ones, and native materials/text only keep AA contrast when the
/// scheme follows the ground — that pairing is the honest contract, not a
/// styling suggestion.
struct AppMoodPalette {
    /// One static ambient light pool (rendered as a RadialGradient fading
    /// to clear). Two per palette at most.
    struct Accent {
        let color: Color
        let opacity: Double
        let center: UnitPoint
        let radius: CGFloat
    }

    let colorScheme: ColorScheme
    /// Vertical ground wash, top → bottom.
    let baseTop: Color
    let baseBottom: Color
    let accents: [Accent]
    /// The full atmospheric wash — real skies compress color near the
    /// horizon and change slowly at the zenith, which a 2-stop gradient
    /// flattens into a poster. Every mood declares 4-5 stops that stay
    /// inside the baseTop/baseBottom lightness envelope (the accent AA
    /// contracts keep holding); an empty array falls back to the plain
    /// two-stop wash.
    var skyStops: [Gradient.Stop] = []

    var resolvedSkyStops: [Gradient.Stop] {
        skyStops.isEmpty
            ? [.init(color: baseTop, location: 0), .init(color: baseBottom, location: 1)]
            : skyStops
    }
    /// The mood's interactive tint — what the app's accent becomes when the
    /// user picks "Automat" in Settings → Aspect. Each value is AA-legible
    /// (≥ 4.5:1) as text/tint against BOTH stops of its own ground wash in
    /// its own color scheme: morning gold #8F5C10 (5.1:1 / 4.9:1), day sky
    /// #1B6C9C (5.5:1 / 5.0:1), night ember #E8A45C (7.8:1 / 9.1:1),
    /// sunset ember #7E430F (6.2:1 / 5.7:1), rain slate #3C5B74
    /// (6.4:1 / 5.5:1), winter glacier #1F6580 (6.2:1 / 5.6:1), event gold
    /// #E9C15E (9.5:1 / 11.1:1).
    let accent: Color

    /// Dimineața — a soft gold-rose wash over near-white warm ground:
    /// sunrise light pooling top-leading, a faint rose answering low.
    /// Ground #FBF2E7 → #F6ECE9; accents gold #EFBE8B, rose #E3A29D.
    static let morning = AppMoodPalette(
        colorScheme: .light,
        baseTop: Color(red: 0.984, green: 0.949, blue: 0.906),
        baseBottom: Color(red: 0.965, green: 0.925, blue: 0.914),
        accents: [
            Accent(color: Color(red: 0.937, green: 0.745, blue: 0.545),
                   opacity: 0.32, center: UnitPoint(x: 0.15, y: 0.10), radius: 420),
            Accent(color: Color(red: 0.890, green: 0.635, blue: 0.616),
                   opacity: 0.20, center: UnitPoint(x: 0.90, y: 0.88), radius: 460),
        ],
        // Sunrise physics: a cooler pale zenith, the gold arriving as a BAND
        // (not a uniform wash), a rose flush near the ground.
        skyStops: [
            .init(color: Color(red: 0.973, green: 0.957, blue: 0.937), location: 0.0),
            .init(color: Color(red: 0.984, green: 0.949, blue: 0.906), location: 0.34),
            .init(color: Color(red: 0.982, green: 0.933, blue: 0.876), location: 0.62),
            .init(color: Color(red: 0.976, green: 0.916, blue: 0.890), location: 0.84),
            .init(color: Color(red: 0.965, green: 0.925, blue: 0.914), location: 1.0),
        ],
        // Warm sunrise gold #8F5C10.
        accent: Color(red: 0.561, green: 0.361, blue: 0.063))

    /// Zi — the brightest ground: airy warm neutral, a whisper of sky
    /// top-trailing and warm sand low so white cards never float on void.
    /// Ground #FBFAF7 → #F1EFEA; accents sky #BED7ED, sand #EBDCC0.
    static let day = AppMoodPalette(
        colorScheme: .light,
        baseTop: Color(red: 0.984, green: 0.980, blue: 0.969),
        baseBottom: Color(red: 0.945, green: 0.937, blue: 0.918),
        accents: [
            Accent(color: Color(red: 0.745, green: 0.843, blue: 0.929),
                   opacity: 0.22, center: UnitPoint(x: 0.85, y: 0.08), radius: 440),
            Accent(color: Color(red: 0.922, green: 0.863, blue: 0.753),
                   opacity: 0.20, center: UnitPoint(x: 0.10, y: 0.92), radius: 480),
        ],
        // Daylight: a faint blue cast high (thin air), warming toward a
        // hazier sand tone at the ground line.
        skyStops: [
            .init(color: Color(red: 0.949, green: 0.961, blue: 0.973), location: 0.0),
            .init(color: Color(red: 0.984, green: 0.980, blue: 0.969), location: 0.32),
            .init(color: Color(red: 0.973, green: 0.965, blue: 0.949), location: 0.68),
            // Interpolated waypoint — every palette carries exactly five
            // stops so the mood crossfade animates instead of snapping.
            .init(color: Color(red: 0.959, green: 0.951, blue: 0.934), location: 0.84),
            .init(color: Color(red: 0.945, green: 0.937, blue: 0.918), location: 1.0),
        ],
        // Deep sky blue #1B6C9C.
        accent: Color(red: 0.106, green: 0.424, blue: 0.612))

    /// Noaptea — deep warm dark, deliberately NOT the smart-home bronze skin:
    /// a plum-charcoal ground with a single ember warmth high and a dusty
    /// mauve low. Ground #241C21 → #100C11; accents ember #C98B52,
    /// mauve #6E4E63 — both ≤ 12% so dark glass and white text stay AA.
    static let night = AppMoodPalette(
        colorScheme: .dark,
        baseTop: Color(red: 0.141, green: 0.110, blue: 0.129),
        baseBottom: Color(red: 0.063, green: 0.047, blue: 0.067),
        accents: [
            Accent(color: Color(red: 0.788, green: 0.545, blue: 0.322),
                   opacity: 0.10, center: UnitPoint(x: 0.85, y: 0.06), radius: 420),
            Accent(color: Color(red: 0.431, green: 0.306, blue: 0.388),
                   opacity: 0.12, center: UnitPoint(x: 0.12, y: 0.90), radius: 460),
        ],
        // Real night: DARKEST at the zenith, the plum warmth living as a
        // low band (city glow near the horizon), falling dark again at the
        // ground. White text only gains contrast from the deeper zenith.
        skyStops: [
            .init(color: Color(red: 0.047, green: 0.039, blue: 0.059), location: 0.0),
            .init(color: Color(red: 0.094, green: 0.075, blue: 0.096), location: 0.30),
            .init(color: Color(red: 0.141, green: 0.110, blue: 0.129), location: 0.62),
            .init(color: Color(red: 0.104, green: 0.078, blue: 0.098), location: 0.86),
            .init(color: Color(red: 0.063, green: 0.047, blue: 0.067), location: 1.0),
        ],
        // Warm ember amber #E8A45C.
        accent: Color(red: 0.910, green: 0.643, blue: 0.361))

    /// Apus — golden hour: a warm amber-rose dusk, deliberately deeper than
    /// morning's near-white (the light is lower, the color richer) while
    /// staying a light ground. The ember pool sits LOW (the sun is at the
    /// horizon) and a violet answer sits high where dusk is already arriving.
    /// Ground #F7E2C8 → #EFD6D6; pools ember #E8975A, violet #9B7BB8.
    static let sunset = AppMoodPalette(
        colorScheme: .light,
        baseTop: Color(red: 0.969, green: 0.886, blue: 0.784),
        baseBottom: Color(red: 0.937, green: 0.839, blue: 0.839),
        accents: [
            Accent(color: Color(red: 0.910, green: 0.592, blue: 0.353),
                   opacity: 0.26, center: UnitPoint(x: 0.12, y: 0.80), radius: 440),
            Accent(color: Color(red: 0.608, green: 0.482, blue: 0.722),
                   opacity: 0.16, center: UnitPoint(x: 0.88, y: 0.10), radius: 460),
        ],
        // Golden hour: dusk violet already claiming the zenith, the amber
        // compressing into an intense band just above the rose horizon —
        // the one gradient where the banding IS the subject.
        skyStops: [
            .init(color: Color(red: 0.902, green: 0.867, blue: 0.898), location: 0.0),
            .init(color: Color(red: 0.953, green: 0.890, blue: 0.835), location: 0.30),
            .init(color: Color(red: 0.969, green: 0.886, blue: 0.784), location: 0.55),
            .init(color: Color(red: 0.976, green: 0.863, blue: 0.757), location: 0.78),
            .init(color: Color(red: 0.937, green: 0.839, blue: 0.839), location: 1.0),
        ],
        // Deep ember #7E430F — AA even over the ember pool's blended ground.
        accent: Color(red: 0.494, green: 0.263, blue: 0.059))

    /// Ploaie — deliberate rain atmosphere, not gloom: a cool gray-blue
    /// washed ground that stays bright (light scheme), a slate-blue pool
    /// high like a rain sky and a soft teal answering low like wet ground.
    /// Ground #F0F3F6 → #DDE3E9; pools slate #7A93AC, teal #7FB0A8.
    static let rain = AppMoodPalette(
        colorScheme: .light,
        baseTop: Color(red: 0.941, green: 0.953, blue: 0.965),
        baseBottom: Color(red: 0.867, green: 0.890, blue: 0.914),
        accents: [
            Accent(color: Color(red: 0.478, green: 0.576, blue: 0.675),
                   opacity: 0.22, center: UnitPoint(x: 0.15, y: 0.08), radius: 440),
            Accent(color: Color(red: 0.498, green: 0.690, blue: 0.659),
                   opacity: 0.16, center: UnitPoint(x: 0.88, y: 0.90), radius: 480),
        ],
        // Rain sky: the cloud deck presses down — heavier gray high, a
        // brighter diffuse band where light scatters through, cooling again
        // toward the wet ground.
        skyStops: [
            .init(color: Color(red: 0.882, green: 0.902, blue: 0.922), location: 0.0),
            .init(color: Color(red: 0.941, green: 0.953, blue: 0.965), location: 0.36),
            .init(color: Color(red: 0.914, green: 0.929, blue: 0.945), location: 0.70),
            // Interpolated waypoint — five stops everywhere (see day).
            .init(color: Color(red: 0.890, green: 0.910, blue: 0.930), location: 0.85),
            .init(color: Color(red: 0.867, green: 0.890, blue: 0.914), location: 1.0),
        ],
        // Slate blue #3C5B74.
        accent: Color(red: 0.235, green: 0.357, blue: 0.455))

    /// Iarnă — the brightest cool ground: near-white with an ice-blue pool
    /// high (winter sky) and a pale silver sheen low (snow light). Cool
    /// where day is warm, so the two never read as the same backdrop.
    /// Ground #F7FAFC → #E8EFF5; pools ice #BFE0F0, silver #D7DEE5.
    static let winter = AppMoodPalette(
        colorScheme: .light,
        baseTop: Color(red: 0.969, green: 0.980, blue: 0.988),
        baseBottom: Color(red: 0.910, green: 0.937, blue: 0.961),
        accents: [
            Accent(color: Color(red: 0.749, green: 0.878, blue: 0.941),
                   opacity: 0.30, center: UnitPoint(x: 0.85, y: 0.08), radius: 440),
            Accent(color: Color(red: 0.843, green: 0.871, blue: 0.898),
                   opacity: 0.26, center: UnitPoint(x: 0.12, y: 0.90), radius: 480),
        ],
        // Winter light: an icy zenith, the bright snow-lit middle, a cold
        // blue shadow settling at the ground.
        skyStops: [
            .init(color: Color(red: 0.929, green: 0.953, blue: 0.973), location: 0.0),
            .init(color: Color(red: 0.969, green: 0.980, blue: 0.988), location: 0.40),
            .init(color: Color(red: 0.941, green: 0.957, blue: 0.973), location: 0.74),
            // Interpolated waypoint — five stops everywhere (see day).
            .init(color: Color(red: 0.926, green: 0.947, blue: 0.967), location: 0.87),
            .init(color: Color(red: 0.910, green: 0.937, blue: 0.961), location: 1.0),
        ],
        // Glacier blue #1F6580.
        accent: Color(red: 0.122, green: 0.396, blue: 0.502))

    /// Eveniment — celebratory dark: a plum-charcoal ground one shade richer
    /// than night, with TWO warm festive pools — gold high, magenta low —
    /// both ≤ 12% so dark glass and white text stay AA and the room reads
    /// elegant, never kitsch. Static like every palette: no animation.
    /// Ground #2A1B2E → #140D18; pools gold #E3B354, magenta #C2478F.
    static let event = AppMoodPalette(
        colorScheme: .dark,
        baseTop: Color(red: 0.165, green: 0.106, blue: 0.180),
        baseBottom: Color(red: 0.078, green: 0.051, blue: 0.094),
        accents: [
            Accent(color: Color(red: 0.890, green: 0.702, blue: 0.329),
                   opacity: 0.12, center: UnitPoint(x: 0.15, y: 0.08), radius: 420),
            Accent(color: Color(red: 0.761, green: 0.278, blue: 0.561),
                   opacity: 0.10, center: UnitPoint(x: 0.88, y: 0.90), radius: 460),
        ],
        // Celebration dark: deep above, the rich plum living as a band
        // (stage light, not a flat wall), settling dark at the floor.
        skyStops: [
            .init(color: Color(red: 0.086, green: 0.055, blue: 0.106), location: 0.0),
            .init(color: Color(red: 0.165, green: 0.106, blue: 0.180), location: 0.36),
            .init(color: Color(red: 0.125, green: 0.082, blue: 0.141), location: 0.72),
            // Interpolated waypoint — five stops everywhere (see day).
            .init(color: Color(red: 0.102, green: 0.066, blue: 0.118), location: 0.86),
            .init(color: Color(red: 0.078, green: 0.051, blue: 0.094), location: 1.0),
        ],
        // Festive gold #E9C15E.
        accent: Color(red: 0.914, green: 0.757, blue: 0.369))
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
