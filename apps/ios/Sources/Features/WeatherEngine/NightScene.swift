import SwiftUI

// MARK: - Weather Engine · NightScene (flagship · Composite tier)
//
// The night sky. It extends the mood system's baked-star-field APPROACH
// (fixed-seed constellation + twinkles) into a pure-Canvas implementation that
// is a function of the stage clock, and adds a REAL moon phase drawn in Canvas
// and dark drifting clouds. Ambient blue comes from the stage's base gradient.
//
// The star field is fixed-seed (SplitMix64) so the constellation is identical
// across mounts, frames, and rotations — never a dice roll per frame. Twinkles
// are per-star sinusoids off the shared clock. The moon phase is computed by
// MoonPhase (documented astronomy source there) and drawn with a scanline
// terminator so the lit lune is geometrically faithful, waxing or waning.
struct NightScene: WeatherScene {
    let context: WeatherSceneContext
    /// `.fullMoon` forces a full disc regardless of tonight's real phase; the
    /// stage passes this. `.night` uses the real computed phase.
    let forceFull: Bool

    init(context: WeatherSceneContext) {
        self.context = context
        self.forceFull = false
    }
    init(context: WeatherSceneContext, forceFull: Bool) {
        self.context = context
        self.forceFull = forceFull
    }

    var body: some View {
        let p = context.parameters
        ZStack {
            if p.starVisibility > 0.05 {
                StarFieldCanvas(visibility: p.starVisibility, time: context.time)
            }
            MoonCanvas(phase: forceFull ? .fullOverride : MoonPhase.renderPhaseNow(),
                       brightness: forceFull ? 1 : max(0.35, p.starVisibility))
                .allowsHitTesting(false)
            // Dark drifting clouds pass IN FRONT of the stars/moon at night.
            if p.cloudCover > 0.02 {
                CloudField(cover: p.cloudCover, darkness: max(p.cloudDarkness, 0.55),
                           warmth: 0, wind: p.windStrength, time: context.time,
                           band: 0.05...0.45)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(Text(moonAccessibilityKey))
    }

    private var moonAccessibilityKey: LocalizedStringKey {
        LocalizedStringKey(forceFull ? "weather_moon_full"
                                     : MoonPhase.current(at: .now).nameKey)
    }
}

// MARK: - Star field (Canvas, fixed seed + twinkle)

/// A fixed-seed constellation of ~90 stars twinkling off the shared clock.
/// Deterministic layout (SplitMix64) so the sky never jumps; a pure function of
/// `time`, so the still frame is a valid night. `visibility` fades the whole
/// field in as dusk deepens.
private struct StarFieldCanvas: View {
    var visibility: Double
    var time: TimeInterval

    private struct Star { let x, y, size, baseAlpha, twinkleAmp, speed, phase: Double }

    private static let stars: [Star] = {
        var rng = SystemRandomNumberGeneratorSeeded(seed: 0x5EED_57A2_F1E1D)
        return (0..<90).map { _ in
            Star(x: .random(in: 0.01...0.99, using: &rng),
                 y: .random(in: 0.01...0.72, using: &rng), // stars sit in the upper sky
                 size: .random(in: 0.6...1.7, using: &rng),
                 baseAlpha: .random(in: 0.25...0.9, using: &rng),
                 twinkleAmp: .random(in: 0.05...0.35, using: &rng),
                 speed: .random(in: 0.6...2.2, using: &rng),
                 phase: .random(in: 0...(2 * .pi), using: &rng))
        }
    }()

    var body: some View {
        Canvas { context, size in
            for star in Self.stars {
                let tw = star.baseAlpha
                    + star.twinkleAmp * sin(time * star.speed + star.phase)
                let alpha = max(0, min(1, tw)) * visibility
                guard alpha > 0.01 else { continue }
                let r = star.size
                let rect = CGRect(x: star.x * size.width - r, y: star.y * size.height - r,
                                  width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect),
                             with: .color(.white.opacity(alpha)))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Moon (Canvas, real phase + scanline terminator)

/// Draws the moon: an earthshine base disc, the lit lune bounded by a scanline
/// terminator, and a soft halo. The lit boundary uses the illumination test
///   waxing: u ≥ cos(P)      waning: u ≤ −cos(P)
/// (u is the normalised x within each scanline, P the phase angle), so the lune
/// is correct through crescent → quarter → gibbous on both limbs.
private struct MoonCanvas: View {
    var phase: MoonRenderPhase
    var brightness: Double

    var body: some View {
        Canvas { context, size in
            let radius = max(14, min(size.width, size.height) * 0.052)
            // Upper-right seat, clear of most constellations.
            let center = CGPoint(x: size.width * 0.76, y: size.height * 0.20)

            // Halo — a soft glow that grows with illumination.
            let haloR = radius * (2.4 + phase.illuminated * 1.2)
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - haloR, y: center.y - haloR,
                                       width: haloR * 2, height: haloR * 2)),
                with: .radialGradient(
                    Gradient(colors: [Color(red: 0.85, green: 0.89, blue: 1.0)
                                        .opacity(0.16 * brightness * (0.4 + phase.illuminated)),
                                      .clear]),
                    center: center, startRadius: radius * 0.6, endRadius: haloR))

            // Earthshine base disc (the dark side is faintly visible).
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                       width: radius * 2, height: radius * 2)),
                with: .color(Color(red: 0.16, green: 0.18, blue: 0.24)
                    .opacity(0.85 * brightness)))

            // Lit lune, built from scanlines.
            let litColor = Color(red: 0.97, green: 0.97, blue: 0.92)
                .opacity(brightness)
            let path = litPath(center: center, radius: radius)
            context.fill(path, with: .color(litColor))
            // A gentle limb darkening on the lit side.
            context.fill(path, with: .radialGradient(
                Gradient(colors: [.clear, Color.black.opacity(0.10 * brightness)]),
                center: center, startRadius: radius * 0.2, endRadius: radius))
        }
        .allowsHitTesting(false)
    }

    /// Polygon of the illuminated region, sampled across scanlines.
    private func litPath(center: CGPoint, radius R: CGFloat) -> Path {
        var path = Path()
        guard phase.illuminated > 0.005 else { return path }
        let steps = 48
        let P = 2 * Double.pi * phase.phaseFraction
        let c = cos(P)
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let y = (t * 2 - 1) * Double(R)     // -R … R
            let w = (Double(R) * Double(R) - y * y)
            guard w > 0 else { continue }
            let halfW = w.squareRoot()
            let uLeft: Double, uRight: Double
            if phase.isWaxing {
                uLeft = c * halfW; uRight = halfW        // lit on the right
            } else {
                uLeft = -halfW; uRight = -c * halfW      // lit on the left
            }
            guard uRight > uLeft else { continue }
            let py = center.y + CGFloat(y)
            left.append(CGPoint(x: center.x + CGFloat(uLeft), y: py))
            right.append(CGPoint(x: center.x + CGFloat(uRight), y: py))
        }
        guard let first = left.first else { return path }
        path.move(to: first)
        for pt in left.dropFirst() { path.addLine(to: pt) }
        for pt in right.reversed() { path.addLine(to: pt) }
        path.closeSubpath()
        return path
    }
}

/// What the moon canvas draws — either tonight's real phase or a forced full
/// disc for the `.fullMoon` condition.
struct MoonRenderPhase {
    var illuminated: Double
    var phaseFraction: Double
    var isWaxing: Bool

    static let fullOverride = MoonRenderPhase(illuminated: 1,
                                              phaseFraction: 0.5, isWaxing: true)
}

extension MoonPhase {
    /// Adapt tonight's real astronomy result to what the canvas draws.
    static func renderPhaseNow() -> MoonRenderPhase {
        let p = MoonPhase.current(at: .now)
        return MoonRenderPhase(illuminated: p.illuminatedFraction,
                               phaseFraction: p.phaseFraction,
                               isWaxing: p.isWaxing)
    }
}
