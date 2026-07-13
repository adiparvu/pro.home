import SwiftUI

// MARK: - AppBackdrop — the one living background
//
// Renders the resolved mood's palette: a vertical ground wash plus two
// static ambient radial accents. Mood changes crossfade with `.smooth(1.2)`
// (instant under Reduce Motion). There is no continuous animation and no
// blur — off a mood change this costs what the old flat color did.
//
// Lifecycle: live backdrops (fixed == nil) ref-count themselves into
// `AppMoodEngine` so its 15-minute re-resolution timer runs only while at
// least one backdrop is actually on screen, and they nudge the engine when
// the scene becomes active (the clock may have drifted hours in background).
//
// Previews (`fixed != nil`) render one mood statically — the settings page's
// hero and thumbnails — and never touch the engine or its timer.

struct AppBackdrop: View {
    /// Pin one mood (settings previews). nil = follow the engine, live.
    var fixed: AppMood? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    /// Safety inversion: each palette declares the color scheme it needs
    /// (light grounds ↔ light scheme, night ↔ dark). When the app's actual
    /// scheme disagrees — the root `.preferredColorScheme` doesn't follow
    /// the mood yet, or the user pinned a Theme — rendering the mismatched
    /// ground would put white text on near-white (or black on near-black)
    /// everywhere. Glass must never reduce readability, so a live backdrop
    /// substitutes the nearest scheme-compatible mood instead: dark scheme →
    /// night, light scheme → day. Once the root scheme follows the mood,
    /// the schemes always agree and this never fires. Fixed previews are
    /// exempt (the settings page forces the matching scheme itself).
    private var effectiveMood: AppMood {
        if let fixed { return fixed }
        let desired = AppMoodEngine.shared.resolved
        switch (desired.palette.colorScheme, colorScheme) {
        case (.light, .dark): return .night
        case (.dark, .light): return .day
        default:              return desired
        }
    }

    var body: some View {
        let mood = effectiveMood
        let palette = mood.palette
        ZStack {
            LinearGradient(colors: [palette.baseTop, palette.baseBottom],
                           startPoint: .top, endPoint: .bottom)
            ForEach(Array(palette.accents.enumerated()), id: \.offset) { _, accent in
                RadialGradient(colors: [accent.color.opacity(accent.opacity), .clear],
                               center: accent.center,
                               startRadius: 0, endRadius: accent.radius)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 1.2), value: mood)
        .accessibilityHidden(true)   // pure atmosphere — nothing to announce
        .onAppear { if fixed == nil { AppMoodEngine.shared.backdropAppeared() } }
        .onDisappear { if fixed == nil { AppMoodEngine.shared.backdropDisappeared() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, fixed == nil { AppMoodEngine.shared.refresh() }
        }
    }
}

// MARK: - Shared background (moved here from DashboardComponents.swift)
//
// The app-wide `appBackground` every screen already layers under its
// content. It used to be a flat adaptive color; it is now the living mood
// backdrop — same call sites (`appBackground.ignoresSafeArea()`,
// `.background(appBackground)`), zero per-screen edits.
var appBackground: some View { AppBackdrop() }
