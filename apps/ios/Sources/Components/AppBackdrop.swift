import SwiftUI

// MARK: - AppBackdrop — the one living background
//
// Renders the resolved mood's palette: a vertical ground wash plus two
// static ambient radial accents, and — on live backdrops, when the engine
// has a fresh weather tone — one extra flat low-opacity weather wash. Mood
// and tone changes crossfade with `.smooth(1.2)` (instant under Reduce
// Motion). There is no continuous animation and no blur — off a change
// this costs what the old flat color did.
//
// Live backdrops additionally compose `AppBackdropEffectsLayer` ABOVE the
// gradients — every mood's signature atmospheric effect (rain / snow /
// night stars / morning dust / passing day clouds / sunset flock + glow /
// one-shot event shimmer). The layer renders nothing at all unless the
// energy policy allows it (user toggle, Reduce Motion, Low Power Mode — see
// AtmosphericEffectsPolicy), so the static backdrop's cost is untouched. Fixed previews get `AppBackdropEffectsHint` instead: a few
// pre-baked static marks, never a live scene per thumbnail.
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
        // A mismatched classic substitutes its own classic twin, never an
        // atmosphere — the user asked for the flat look, keep it flat.
        case (.light, .dark): return desired.isClassic ? .classicDark : .night
        case (.dark, .light): return desired.isClassic ? .classicLight : .day
        default:              return desired
        }
    }

    var body: some View {
        let mood = effectiveMood
        let palette = mood.palette
        // Weather modulates LIVE backdrops only (fixed settings previews
        // stay the pure mood): one extra flat low-opacity wash, derived by
        // the engine from the property's fresh cached weather. It is always
        // in the tree for live backdrops (clear when no tone) so tone
        // changes crossfade instead of inserting/removing a layer. The rain
        // MOOD is itself the weather statement, so the rain wash never
        // doubles up on it — an extra gray layer would push the deliberate
        // rain atmosphere toward gloom.
        let engineTone: AppWeatherTone? = fixed == nil ? AppMoodEngine.shared.weatherTone : nil
        let tone: AppWeatherTone? = (mood == .rain && engineTone == .rain) ? nil : engineTone
        ZStack {
            // The sky itself: a multi-stop atmospheric wash (horizon bands,
            // compressed color where real skies compress it) instead of the
            // old two-color ramp that read as a flat poster.
            LinearGradient(stops: palette.resolvedSkyStops,
                           startPoint: .top, endPoint: .bottom)
            ForEach(Array(palette.accents.enumerated()), id: \.offset) { _, accent in
                // Every light pool renders twice: a wide falloff (the ambient
                // spill) plus a tighter, brighter core — real light has a
                // source, not a uniform blob.
                RadialGradient(colors: [accent.color.opacity(accent.opacity), .clear],
                               center: accent.center,
                               startRadius: 0, endRadius: accent.radius)
                RadialGradient(colors: [accent.color.opacity(min(accent.opacity * 0.9, 0.5)), .clear],
                               center: accent.center,
                               startRadius: 0, endRadius: accent.radius * 0.38)
            }
            if fixed == nil {
                // Classics are flat by definition: no weather wash, no live
                // effects — the whole point of picking one (IMG_8622).
                if !mood.isClassic {
                    tone?.wash(for: palette.colorScheme) ?? Color.clear
                    AppBackdropEffectsLayer(mood: mood)
                }
            } else {
                AppBackdropEffectsHint(mood: mood)
            }
            // Photographic finish: a lens-like edge falloff pulls the eye to
            // the center, and a whisper of film grain breaks the vector-flat
            // banding that made the gradients read as drawings. Both layers
            // are static — no animation, no blur, one composite each.
            EllipticalGradient(colors: [.clear,
                                        .black.opacity(palette.colorScheme == .dark ? 0.16 : 0.05)],
                               center: .center,
                               startRadiusFraction: 0.55,
                               endRadiusFraction: 1.05)
            BackdropGrainOverlay(scheme: palette.colorScheme)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 1.2), value: mood)
        .animation(reduceMotion ? nil : .smooth(duration: 1.2), value: tone)
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

// MARK: - Sheet backdrop (transient chrome)

/// Lightweight backdrop for SHEETS and other transient surfaces: the mood's
/// sky gradient alone — no light pools, no weather wash, no effects layer,
/// no grain, no vignette, no animation, no engine callbacks. The full
/// `appBackground` stacks ~8 composited layers (grain blends over the whole
/// screen, the effects layer animates), and iOS re-composites all of it on
/// every frame of a sheet's present/dismiss transition — which visibly
/// stuttered (IMG_8573, Notifications). One static gradient keeps the
/// mood's color identity at one-layer cost.
struct AppSheetBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Same scheme-safety substitution as AppBackdrop: never render a
        // light ground under a dark scheme (or vice versa).
        let desired = AppMoodEngine.shared.resolved
        let mood: AppMood = switch (desired.palette.colorScheme, colorScheme) {
        case (.light, .dark): desired.isClassic ? .classicDark : .night
        case (.dark, .light): desired.isClassic ? .classicLight : .day
        default:              desired
        }
        return LinearGradient(stops: mood.palette.resolvedSkyStops,
                              startPoint: .top, endPoint: .bottom)
            .accessibilityHidden(true)
    }
}

var sheetBackground: some View { AppSheetBackdrop() }
