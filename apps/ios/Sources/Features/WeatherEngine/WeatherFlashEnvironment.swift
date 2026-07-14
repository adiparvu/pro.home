import SwiftUI

// MARK: - Weather Engine · lightning → Liquid Glass card illumination hook
//
// The engine already BROADCASTS the live lightning brightness
// (`WeatherEngine.flashLevel`). This file is the clean, documented SwiftUI
// mechanism that lets ANY Liquid Glass card brighten with a strike — the same
// way Apple Weather's storm lights the whole UI — without every card owning a
// clock or reaching into the engine.
//
// TWO PIECES:
//   1. `\.weatherFlash` — an EnvironmentValue (0…1) carrying the live flash.
//      A card reads it with `@Environment(\.weatherFlash)` or, more simply,
//      the `.weatherFlashResponsive()` modifier below.
//   2. `WeatherFlashProvider` — wrap a subtree in this ONCE. It publishes the
//      live flash into `\.weatherFlash` for everything beneath it, driven by a
//      paused-aware TimelineView that ticks ONLY while a flashing condition is
//      on-screen and motion is allowed (energy contract). When it is not a
//      storm — or Reduce Motion / Low Power / backdrop off-screen — it injects
//      a constant 0 with NO timeline, so non-storm UI pays exactly nothing.
//
// WHERE IT PLUGS IN APP-WIDE (deferred to the integration phase, NOT wired now):
//   Wrap a high-level container once — e.g. AppBackdrop's content root, or a
//   screen's root — in `WeatherFlashProvider { … }`, and add
//   `.weatherFlashResponsive()` to the Liquid Glass surfaces that should react
//   (GlassCard / `.liquidGlass(...)`). That is the whole integration: one
//   provider high up, the modifier on the cards. This phase wires it ONLY into
//   the audition gallery's own preview cards as the proof-of-concept.

// MARK: - Environment value

private struct WeatherFlashKey: EnvironmentKey {
    static let defaultValue: Double = 0
}

extension EnvironmentValues {
    /// Live lightning brightness, 0 (dark) … 1 (peak), for the current subtree.
    /// 0 unless a `WeatherFlashProvider` above is publishing an active strike.
    var weatherFlash: Double {
        get { self[WeatherFlashKey.self] }
        set { self[WeatherFlashKey.self] = newValue }
    }
}

// MARK: - Provider (publishes the live flash into the environment)

/// Publishes `WeatherEngine.flashLevel` into `\.weatherFlash` for its content.
/// The internal TimelineView is mounted ONLY while the current condition
/// flashes and the atmospheric policy allows motion and the scene is active —
/// so between storms (the overwhelming common case) there is no clock at all
/// and descendants see a constant 0.
struct WeatherFlashProvider<Content: View>: View {
    private let content: Content

    private var engine = WeatherEngine.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let flashing = engine.current.parameters.flashEnabled
        let motion = AtmosphericEffectsPolicy.shared.allowsMounting(reduceMotion: reduceMotion)
        let active = scenePhase == .active

        Group {
            if flashing && motion && active {
                // Ticks only during an on-screen storm. (A future refinement can
                // pause between strikes; a storm is already the rare case.)
                TimelineView(.animation) { timeline in
                    content.environment(\.weatherFlash, engine.flashLevel(at: timeline.date))
                }
            } else {
                content.environment(\.weatherFlash, 0)
            }
        }
    }
}

// MARK: - Card modifier

extension View {
    /// Makes a Liquid Glass surface brighten with the live lightning flash it
    /// receives from an enclosing `WeatherFlashProvider`. A subtle brightness
    /// lift plus a cool plusLighter wash scaled by the flash — nothing at all
    /// when `weatherFlash` is 0, so it is free outside a storm.
    ///
    /// - Parameter strength: 0…1 scale on the effect (a hero card can take more
    ///   than a dense list of chips).
    func weatherFlashResponsive(strength: Double = 1) -> some View {
        modifier(WeatherFlashResponsive(strength: strength))
    }
}

private struct WeatherFlashResponsive: ViewModifier {
    let strength: Double
    @Environment(\.weatherFlash) private var flash

    func body(content: Content) -> some View {
        let f = max(0, min(1, flash)) * strength
        content
            .overlay {
                if f > 0.001 {
                    WeatherLight.flashTint.opacity(0.30 * f)
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)
                }
            }
            .brightness(0.12 * f)
    }
}
