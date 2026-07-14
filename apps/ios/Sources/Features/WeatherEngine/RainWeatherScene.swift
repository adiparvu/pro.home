import SwiftUI
import UIKit

// MARK: - Weather Engine · RainWeatherScene (Composite tier · rain / heavyRain)
//
// The dedicated Apple-Weather-depth rain scene, replacing the generic path for
// `.rain` and `.heavyRain`. It layers, from BACK to FRONT (the composition
// order is load-bearing — verified below):
//
//   1. REFRACTED SKY+CLOUD sublayer — the base sky (WeatherSkyLayer) + a low
//      cloud band, with `.weatherLensRain` applied to THIS SUBLAYER ONLY. The
//      lens droplets ("drops on the camera lens") therefore bend the SKY and
//      CLOUDS behind them and nothing else. Phase 1 flagged the risk of the old
//      stage-wide lens: it wrapped the whole stage INCLUDING the live SpriteView
//      rain — the priciest layerEffect input, and one SwiftUI may not rasterize
//      an SKView into at all. Scoping the lens to an opaque Canvas/gradient
//      sublayer is both correct AND cheaper, and the streaks sit ABOVE it.
//   2. FAR MIST VEIL (Canvas) — a very faint drifting veil low in the frame for
//      the far parallax the particle system alone can't give.
//   3. WATER SURFACE band — the lower ~22% reads as wet ground: a reflected-sky
//      gradient. The shared rain engine's splash emitter lands its rings here.
//   4. RAIN STREAKS — the shared SpriteKit RainScene (three depths + splashes +
//      mist), composed ABOVE the refracted sky.
//   5. NEAR MOTION-BLURRED STREAKS (Canvas) — a few fast foreground streaks with
//      baked motion blur, the nearest parallax plane, in front of everything.
//   6. CONDENSATION on the glass — a baked, static fogged-glass micro-droplet
//      texture at low alpha (drawn ONCE, ~zero per-frame cost).
//
// heavyRain is rain with the intensity dialled up: every intensity below reads
// `context.parameters.rainIntensity` (rain 0.6 → heavyRain 0.95), so streaks,
// lens beads, mist and near-streaks all densify together. See the multipliers
// in each subview.
//
// ENERGY: precipitation and the near/lens motion mount only when
// `context.motionEnabled`; the still frame (Reduce Motion / Low Power / effects
// off) shows sky + clouds + veil + water + condensation — a faithful, frozen
// representative with no SpriteKit and no animating shader.
struct RainWeatherScene: WeatherScene {
    let context: WeatherSceneContext

    init(context: WeatherSceneContext) { self.context = context }

    /// The single rain dial this scene scales everything from: 0.6 (rain) →
    /// 0.95 (heavyRain). Also fades in/out cleanly during a cross-dissolve
    /// because the parameter set is lerped upstream.
    private var rain: Double { context.parameters.rainIntensity }

    var body: some View {
        let p = context.parameters
        let size = context.size
        ZStack {
            // 1. Refracted sky + clouds — lens droplets bend ONLY this sublayer.
            //    An opaque sky gradient gives the droplets real content to
            //    magnify; the streaks (step 4) are composited above it.
            ZStack {
                WeatherSkyLayer(parameters: p)
                if p.cloudCover > 0.02 {
                    CloudField(cover: p.cloudCover, darkness: max(p.cloudDarkness, 0.3),
                               warmth: 0, wind: p.windStrength, time: context.time,
                               band: 0.0...0.42)
                }
            }
            // Frozen time in the still frame → beads hold instead of drifting;
            // intensity 0 there makes `.weatherLensRain` a no-op (returns self).
            .weatherLensRain(time: context.motionEnabled ? context.time : 0,
                             intensity: context.motionEnabled ? rain : 0,
                             size: size)

            // 2. Far mist veil — soft, low, behind the rain (far parallax).
            FarRainMistVeil(intensity: rain, wind: p.windStrength, time: context.time)

            // 3. Wet ground / water surface — a reflected-sky band, lower ~22%.
            WetGroundBand(parameters: p, size: size)

            // 4. Rain streaks (shared SpriteKit engine) ABOVE the refracted sky.
            //    Same intensity formula the generic path used, so the ≈112-live
            //    baseline budget is unchanged (rain ×1.36, heavyRain ×1.57).
            if context.motionEnabled {
                ComposedRainView(scheme: .dark,
                                 intensity: 1 + rain * 0.6,
                                 isActive: context.isActive)
                    .equatable()

                // 5. Near motion-blurred streaks — nearest parallax, in front.
                NearRainStreaks(intensity: rain, time: context.time)
            }

            // 6. Condensation on the glass — baked once, ~zero per-frame cost.
            RainCondensation(intensity: rain)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Far mist veil (Canvas · far parallax)

/// A very faint drifting veil that sits behind the rain to add far depth the
/// particle field doesn't. Deterministic (fixed seed) and a pure function of
/// `time`, so it never jumps and the still frame is valid.
///
/// COST: N ≤ 5 radial-gradient fills per frame; no Canvas blur (softness is the
/// gradient falloff). Alpha is intentionally tiny — presence, not fog.
private struct FarRainMistVeil: View {
    var intensity: Double
    var wind: Double
    var time: TimeInterval

    private static let seeds: [(x: Double, y: Double, scale: Double,
                                alpha: Double, speed: Double)] = {
        var rng = SystemRandomNumberGeneratorSeeded(seed: 0x2A17_FEED_9C31)
        return (0..<5).map { _ in
            (x: Double.random(in: 0...1, using: &rng),
             y: Double.random(in: 0.42...0.80, using: &rng),
             scale: Double.random(in: 0.8...1.4, using: &rng),
             alpha: Double.random(in: 0.5...1.0, using: &rng),
             speed: Double.random(in: 0.3...0.8, using: &rng))
        }
    }()

    var body: some View {
        Canvas { context, size in
            guard intensity > 0.02 else { return }
            let drift = time * (8 + wind * 24)   // pt/s, wind-scaled
            for seed in Self.seeds {
                let w = size.width * (0.7 + seed.scale * 0.5)
                let h = w * 0.5
                let track = size.width + w
                var x = (seed.x * track + drift * seed.speed)
                    .truncatingRemainder(dividingBy: track)
                if x < 0 { x += track }
                x -= w / 2
                let y = size.height * seed.y
                let a = seed.alpha * 0.10 * intensity   // ≤ ~0.095 — very faint
                let rect = CGRect(x: x, y: y - h / 2, width: w, height: h)
                context.fill(Path(ellipseIn: rect),
                             with: .radialGradient(
                                Gradient(colors: [Color.white.opacity(a),
                                                  Color.white.opacity(0)]),
                                center: CGPoint(x: rect.midX, y: rect.midY),
                                startRadius: 0, endRadius: w / 2))
            }
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}

// MARK: - Wet ground / water surface (reflected sky)

/// The lower ~22% of the frame, read as wet ground/water reflecting the sky: a
/// vertical gradient seeded from the sky colours (bright near the horizon line,
/// darkening down), with a thin sheen highlight along the top. A pure gradient —
/// zero per-frame work beyond one composite; the shared rain engine's splash
/// emitter provides the landing rings over it.
private struct WetGroundBand: View {
    var parameters: WeatherParameters
    var size: CGSize

    var body: some View {
        let bandH = max(1, size.height * 0.22)
        // Reflected sky: horizon colour up top, darker sky-top colour below.
        let horizon = parameters.skyBottom.color
        let deep = parameters.skyTop.color
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [horizon.opacity(0.0),
                         horizon.opacity(0.5),
                         deep.opacity(0.82)],
                startPoint: .top, endPoint: .bottom)
            // A thin bright sheen where the water meets the rain haze.
            LinearGradient(colors: [.white.opacity(0.10), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: bandH * 0.28)
        }
        .frame(height: bandH)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
    }
}

// MARK: - Near motion-blurred streaks (Canvas · nearest parallax)

/// A few fast foreground streaks with baked motion blur — the nearest parallax
/// plane, in front of the SpriteKit rain. Deterministic layout, a pure function
/// of `time` (each streak falls and wraps), so the still frame is valid.
///
/// COST: N ≤ 10 streaks × 2 strokes = ≤ 20 line strokes per frame. Motion blur
/// is BAKED as a wide faint underlay stroke beneath a thin brighter core — never
/// a Canvas `.blur`. Count and alpha scale with intensity.
private struct NearRainStreaks: View {
    var intensity: Double
    var time: TimeInterval

    private struct Streak {
        let x, length, width, speed, alpha, phase: Double
    }
    private static let tilt = 12.0 * .pi / 180   // shares the rain engine's 12°

    private static let streaks: [Streak] = {
        var rng = SystemRandomNumberGeneratorSeeded(seed: 0x9D1E_5772_BEEF_01)
        return (0..<10).map { _ in
            Streak(x: .random(in: -0.05...1.05, using: &rng),
                   length: .random(in: 0.10...0.22, using: &rng),
                   width: .random(in: 2.0...4.5, using: &rng),
                   speed: .random(in: 1.6...2.6, using: &rng),
                   alpha: .random(in: 0.12...0.24, using: &rng),
                   phase: .random(in: 0...1, using: &rng))
        }
    }()

    var body: some View {
        Canvas { context, size in
            guard intensity > 0.02 else { return }
            let count = max(4, Int((Double(Self.streaks.count)
                                    * (0.5 + intensity * 0.5)).rounded()))
            let dxPerUnit = tan(Self.tilt)
            for streak in Self.streaks.prefix(count) {
                // Fall progress wraps 0…1; the streak enters above and exits below.
                let prog = (streak.phase + time * streak.speed)
                    .truncatingRemainder(dividingBy: 1)
                let yTop = prog * (1 + streak.length) - streak.length
                let x = streak.x * size.width
                let p0 = CGPoint(x: x, y: yTop * size.height)
                let p1 = CGPoint(x: x + dxPerUnit * streak.length * size.height,
                                 y: (yTop + streak.length) * size.height)
                var path = Path()
                path.move(to: p0)
                path.addLine(to: p1)
                // Baked motion blur: wide faint pass, then a thin bright core.
                context.stroke(path,
                    with: .color(.white.opacity(streak.alpha * 0.5 * intensity)),
                    style: StrokeStyle(lineWidth: streak.width * 1.8, lineCap: .round))
                context.stroke(path,
                    with: .color(.white.opacity(streak.alpha * intensity)),
                    style: StrokeStyle(lineWidth: streak.width * 0.6, lineCap: .round))
            }
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}

// MARK: - Condensation on the glass (baked once)

/// A subtle fogged-glass wetness: a static texture of micro-droplets + a few
/// short runnels, BAKED ONCE into a cached `UIImage` (the same render-once
/// pattern the particle textures use) and displayed as a resizable image at low
/// alpha. There is NO per-frame drawing — it is one composited quad, so it
/// costs the same whether the stage runs at 120fps or is a still frame.
private struct RainCondensation: View {
    var intensity: Double

    var body: some View {
        Image(uiImage: Self.texture)
            .resizable()
            .opacity(0.35 + 0.25 * intensity)   // heavier rain → wetter glass
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }

    /// ~140 micro-droplets + a handful of runnels, white on clear, low alpha,
    /// rendered once at a fixed reference size and stretched to fill. Stretching
    /// micro-droplets is imperceptible and buys true zero per-frame cost.
    private static let texture: UIImage = {
        let canvas = CGSize(width: 320, height: 680)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 2
        var rng = SystemRandomNumberGeneratorSeeded(seed: 0xC0FF_EE12_3455)
        return UIGraphicsImageRenderer(size: canvas, format: format).image { ctx in
            let cg = ctx.cgContext
            // Micro-droplets.
            for _ in 0..<140 {
                let x = CGFloat.random(in: 0...canvas.width, using: &rng)
                let y = CGFloat.random(in: 0...canvas.height, using: &rng)
                let r = CGFloat.random(in: 0.6...2.2, using: &rng)
                let a = CGFloat.random(in: 0.02...0.07, using: &rng)
                let colors = [UIColor.white.withAlphaComponent(a).cgColor,
                              UIColor.white.withAlphaComponent(0).cgColor]
                if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: colors as CFArray, locations: [0, 1]) {
                    cg.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y),
                                          startRadius: 0,
                                          endCenter: CGPoint(x: x, y: y),
                                          endRadius: r, options: [])
                }
            }
            // A few faint runnels trickling down.
            cg.setLineCap(.round)
            for _ in 0..<8 {
                let x = CGFloat.random(in: 0...canvas.width, using: &rng)
                let y = CGFloat.random(in: 0...(canvas.height * 0.6), using: &rng)
                let len = CGFloat.random(in: 20...90, using: &rng)
                let a = CGFloat.random(in: 0.02...0.05, using: &rng)
                cg.setStrokeColor(UIColor.white.withAlphaComponent(a).cgColor)
                cg.setLineWidth(CGFloat.random(in: 0.8...1.6, using: &rng))
                cg.move(to: CGPoint(x: x, y: y))
                cg.addLine(to: CGPoint(x: x + CGFloat.random(in: -4...4, using: &rng),
                                       y: y + len))
                cg.strokePath()
            }
        }
    }()
}
