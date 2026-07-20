import SwiftUI

// MARK: - AppBackdrop — the classic flat ground
//
// The living mood backdrop was RETIRED (user-decreed, 2026-07-19): the app
// returns to the classic flat themes — Automatic / Light / Dark (Settings →
// Aspect → Temă). One flat classic palette per scheme, driven by the
// environment scheme, which the Theme controls at the root.
//
// The public surface is unchanged on purpose — `AppBackdrop(fixed:)`,
// `appBackground`, `AppSheetBackdrop`, `sheetBackground` — so the hundreds
// of `.background(appBackground.ignoresSafeArea())` call sites needed zero
// edits, exactly like when the living backdrop first replaced the flat
// color. A `fixed` mood now renders the classic ground of that mood's
// scheme (YearWrapped's night hero stays a dark page).

struct AppBackdrop: View {
    /// Source compatibility with fixed-preview call sites; only the mood's
    /// SCHEME matters now — the ground is always the flat classic.
    var fixed: AppMood? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let scheme = fixed?.palette.colorScheme ?? colorScheme
        let palette: AppMoodPalette = scheme == .dark ? .classicDark : .classicLight
        LinearGradient(stops: palette.resolvedSkyStops,
                       startPoint: .top, endPoint: .bottom)
            .accessibilityHidden(true)
    }
}

// MARK: - Shared background

/// The app-wide background every screen layers under its content — the
/// owner's CHOICE (user-decreed, 2026-07-20): the F1 real-time weather
/// stage by default, or a curated gradient, or their own photo
/// (BackgroundStyle in AppBackgroundStyle.swift). Sheets keep the flat
/// classic ground (one layer; the IMG_8573 transition lesson).
var appBackground: some View { AppBackgroundView() }

// MARK: - Sheet backdrop

/// Sheets share the same flat classic ground — one gradient, one layer.
struct AppSheetBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette: AppMoodPalette = colorScheme == .dark ? .classicDark : .classicLight
        LinearGradient(stops: palette.resolvedSkyStops,
                       startPoint: .top, endPoint: .bottom)
            .accessibilityHidden(true)
    }
}

var sheetBackground: some View { AppSheetBackdrop() }

// MARK: - On-backdrop text (IMG_8734)
//
// Text sitting NAKED on the live weather stage cannot color itself by the
// app's color scheme: at dusk (or under a storm deck) the sky is already
// dark while the scheme — driven by the user's custom hours — is still
// light, and a scheme-gray header disappears into it. These tiers read
// the STAGE's own luminance instead (the same snapshot signal the widgets
// wear), so naked headers follow the real sky, not the clock. Both are
// `@MainActor` computed properties over the `@Observable` engine: any
// body that touches them re-renders when the sky's target changes. They
// live HERE (not in DesignSystem.swift) because the widget extension
// compiles DesignSystem without the weather stage.
extension Color {
    /// Full-strength text directly on the live backdrop (day titles).
    /// The signal comes from the CHOSEN background's own luminance —
    /// live sky, gradient preset or the measured photo alike.
    @MainActor
    static var backdropPrimaryText: Color {
        BackgroundStyle.shared.wantsDarkGround
            ? Color.white.opacity(0.96)
            : Color.black.opacity(0.82)
    }

    /// Secondary-tier text directly on the live backdrop (section headers,
    /// counts, eyebrow labels).
    @MainActor
    static var backdropSecondaryText: Color {
        BackgroundStyle.shared.wantsDarkGround
            ? Color.white.opacity(0.72)
            : Color.black.opacity(0.55)
    }
}

extension View {
    /// The decreed presentation ground for content sheets: the flat classic
    /// gradient instead of bare `.thinMaterial`. A material presentation
    /// ground puts the whole sheet in a vibrancy context that borrows its
    /// light from whatever sits BEHIND the sheet — over the black night
    /// backdrop every hierarchical `.secondary`/`.tertiary` label rendered
    /// invisible while `.primary` and explicit colors survived
    /// (IMG_8688–8690). An opaque classic ground gives the glass the
    /// luminance it needs, in both schemes.
    func sheetGround() -> some View {
        presentationBackground { AppSheetBackdrop().ignoresSafeArea() }
    }
}
