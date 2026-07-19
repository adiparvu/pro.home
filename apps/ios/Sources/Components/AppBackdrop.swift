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

/// The app-wide background every screen layers under its content: the F1
/// real-time weather stage (user-decreed return, 2026-07-20) — procedural
/// GPU sky driven by the property's real weather and the real sun. Sheets
/// keep the flat classic ground (one layer; the IMG_8573 transition lesson).
var appBackground: some View { WeatherStageView() }

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
