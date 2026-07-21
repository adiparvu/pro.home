import SwiftUI
import WidgetKit

// MARK: - Mood-aware widget ground
//
// The app's living backdrop reaches the home screen. Every time the app
// resolves its mood (dimineața / zi / apus / noapte / ploaie / iarnă /
// eveniment), it writes the raw AppMood
// value into the shared App Group under "app.mood.current"; widgets read
// that key when their views are rendered (timeline archive time) and stand
// on the matching palette. `AppMoodPalette` itself compiles into this
// target from Sources/Components/DesignSystem.swift — the single source of
// truth for every palette value; nothing is duplicated here.
//
// Honesty contract:
// - Key absent (the app never ran, or a build that predates the mood
//   engine): the widget keeps exactly today's appearance — a clear ground
//   under the system scheme. No mood is ever invented from the widget's
//   own clock.
// - Only the home-screen full-color ground changes. Accented and vibrant
//   rendering (lock screen, tinted home screens, StandBy) keep the
//   system's treatment untouched.
// - The palette's declared ColorScheme travels with its ground, so
//   `.primary`/`.secondary` content keeps AA contrast on it — the same
//   honest pairing AppMoodPalette documents for the app.

enum WidgetMood {
    /// Written by the app's mood engine into the shared App Group
    /// (same suite the snapshot pipeline uses).
    private static let moodKey = "app.mood.current"

    /// The palette for the mood the app last resolved, or nil when no mood
    /// has ever been written (the honest "no mood" state). Raw values
    /// mirror `AppMood`'s cases 1:1; anything unknown (a future mood this
    /// build predates) falls back to the neutral ground rather than
    /// guessing.
    static func currentPalette() -> AppMoodPalette? {
        guard let raw = UserDefaults(suiteName: SharedDataStore.suiteName)?
            .string(forKey: moodKey) else { return nil }
        switch raw {
        case "morning": return .morning
        case "day":     return .day
        case "sunset":  return .sunset
        case "night":   return .night
        case "rain":    return .rain
        case "winter":  return .winter
        case "event":   return .event
        case "classic_light": return .classicLight
        case "classic_dark":  return .classicDark
        default:        return nil
        }
    }
}

// MARK: - The ground itself

/// The widget-scale rendering of the app backdrop's composition: the
/// palette's vertical wash plus its (at most two) ambient light pools.
/// Color, opacity and center come 1:1 from the palette; only the pool's
/// extent is expressed as a fraction of the tile instead of the app's
/// absolute point radii, because those were sized for a full phone screen.
/// Static gradients only — no blur, no animation, near-flat compositor cost.
struct WidgetMoodGround: View {
    let palette: AppMoodPalette

    var body: some View {
        ZStack {
            LinearGradient(colors: [palette.baseTop, palette.baseBottom],
                           startPoint: .top, endPoint: .bottom)
            ForEach(palette.accents.indices, id: \.self) { index in
                let accent = palette.accents[index]
                EllipticalGradient(
                    colors: [accent.color.opacity(accent.opacity), .clear],
                    center: accent.center,
                    startRadiusFraction: 0,
                    endRadiusFraction: 0.9)
            }
        }
    }
}

// MARK: - Container-background modifier

extension View {
    /// Drop-in replacement for the widgets' former flat
    /// `.containerBackground(for: .widget) { Color.clear }`. Content,
    /// layout and deep links stay identical; only the ground (and the color
    /// scheme that keeps text legible on it) follows the app's mood.
    func moodContainerBackground() -> some View {
        modifier(MoodContainerBackground())
    }
}

private struct MoodContainerBackground: ViewModifier {
    @Environment(\.widgetRenderingMode) private var renderingMode

    @ViewBuilder
    func body(content: Content) -> some View {
        if renderingMode == .fullColor,
           let sky = SharedDataStore.readBackdropSky() ?? SharedDataStore.freshWeatherSky() {
            // The owner's CHOSEN backdrop (gradient endpoints or the
            // photo's measured thirds) — the same ground the app renders,
            // with its darkGround driving the tile's scheme. No TTL: a
            // static choice stays honest until changed. The weather sky
            // remains only as the legacy TTL-bound fallback.
            content
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [skyColor(sky.top), skyColor(sky.bottom)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .environment(\.colorScheme, sky.darkGround ? .dark : .light)
        } else if renderingMode == .fullColor, let palette = WidgetMood.currentPalette() {
            content
                .containerBackground(for: .widget) { WidgetMoodGround(palette: palette) }
                .environment(\.colorScheme, palette.colorScheme)
        } else {
            // Today's neutral look: exactly what these widgets rendered
            // before the mood ground existed.
            content
                .containerBackground(for: .widget) { Color.clear }
        }
    }

    /// A validated [r,g,b] triplet (freshWeatherSky guarantees count == 3).
    private func skyColor(_ rgb: [Double]) -> Color {
        Color(red: rgb[0], green: rgb[1], blue: rgb[2])
    }
}
