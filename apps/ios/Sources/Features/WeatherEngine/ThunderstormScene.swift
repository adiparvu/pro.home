import SwiftUI

// MARK: - Weather Engine · ThunderstormScene (flagship · Composite tier)
//
// The most demanding scene — it proves all three render tiers at once:
//   - CANVAS   a dark, turbulent storm-cloud field (denser + more bruised than
//              the generic CloudField, with a low churning underbelly).
//   - SPRITEKIT the SHARED rain engine (RainScene from AppBackdropEffects),
//              composed at storm intensity — the one rain implementation, not a
//              copy.
//   - METAL    the lightning sky illumination + bloom shader, driven by the
//              engine's live flashLevel (the stage's 25–70 s scheduler pulses
//              a two-flash with a documented thunder-delay hook; no audio this
//              phase).
// Plus a Canvas BOLT stroke: a bright multi-segment jagged stroke that appears
// with the flash. Per the existing lightning design, the REALISM is the
// illumination (the sky bloom), not the bolt geometry — a photoreal branching
// bolt is a device-tuning item (see the report), so the bolt here is a clean,
// bright stroke synced to the flash and the shader does the atmospheric work.
struct ThunderstormScene: WeatherScene {
    let context: WeatherSceneContext

    init(context: WeatherSceneContext) { self.context = context }

    var body: some View {
        let p = context.parameters
        ZStack {
            // Turbulent storm clouds — heavy, dark, low.
            StormCloudField(darkness: p.cloudDarkness, wind: p.windStrength,
                            time: context.time)

            // Composed SpriteKit rain at storm intensity (dark drops over the
            // dark sky). Motion-gated: the still frame shows clouds + a frozen
            // bolt, never a paused particle field.
            if context.motionEnabled {
                ComposedRainView(scheme: .dark, intensity: 1.6,
                                 isActive: context.isActive)
                    .equatable()
            }

            // Canvas bolt — a jagged bright stroke keyed to the flash origin,
            // visible only at the peak of a strike.
            LightningBolt(origin: context.flashOrigin,
                          flash: context.flashLevel,
                          size: context.size)

            // Metal sky illumination + bloom (the realism), fed by flashLevel.
            LightningIlluminationLayer(origin: context.flashOrigin,
                                       flash: context.flashLevel,
                                       tint: WeatherLight.flashTint,
                                       size: context.size)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Storm cloud field (Canvas)

/// A darker, denser, lower cloud field than the generic one — two bands (a high
/// veil and a churning underbelly) drifting at storm speed. Deterministic and a
/// pure function of `time`. Reuses the CloudField look but tuned for menace.
private struct StormCloudField: View {
    var darkness: Double
    var wind: Double
    var time: TimeInterval

    var body: some View {
        ZStack {
            CloudField(cover: 1.0, darkness: max(darkness, 0.5), warmth: 0,
                       wind: wind, time: time, band: 0.0...0.30)
            CloudField(cover: 0.9, darkness: max(darkness, 0.62), warmth: 0,
                       wind: wind * 1.25, time: time + 40, band: 0.14...0.5)
                .opacity(0.9)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Lightning bolt (Canvas stroke)

/// A jagged multi-segment bolt from the strike origin toward the ground,
/// drawn only while `flash` is above a threshold (the peak of a strike). The
/// path is derived DETERMINISTICALLY from the origin so it doesn't jitter
/// within a single flash, and it re-seeds per strike because the origin moves.
/// Its opacity tracks the flash so it appears and vanishes with the bloom.
///
/// DEVICE-TUNING ITEM (flagged): the bolt is a single clean fork, not a
/// physically branched channel — realism here is intentionally the shader's
/// illumination. A richer branching bolt with additive glow passes is a device
/// tuning task once the shader pipeline is validated on hardware.
private struct LightningBolt: View {
    var origin: UnitPoint
    var flash: Double
    var size: CGSize

    var body: some View {
        Canvas { context, canvasSize in
            guard flash > 0.35 else { return }
            let start = CGPoint(x: origin.x * canvasSize.width,
                                y: origin.y * canvasSize.height)
            let path = boltPath(from: start, size: canvasSize)
            let alpha = min(1, (flash - 0.35) / 0.65)

            // Blurred outer glow on a COPY (so the blur doesn't bleed into the
            // core), then a sharp bright core on the clean context on top.
            var glow = context
            glow.addFilter(.blur(radius: 3))
            glow.stroke(path, with: .color(WeatherLight.flashTint.opacity(alpha * 0.7)),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(.white.opacity(alpha)),
                           style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    /// A jagged descending path with one small fork. Deterministic per origin
    /// (a hash of the origin seeds the zigzag), so it is stable within a strike.
    private func boltPath(from start: CGPoint, size: CGSize) -> Path {
        var rng = SystemRandomNumberGeneratorSeeded(
            seed: UInt64(abs(origin.x * 100_000).rounded()) &* 2_654_435_761
                &+ UInt64(abs(origin.y * 100_000).rounded()))
        var path = Path()
        path.move(to: start)
        let segments = 7
        let endY = size.height * CGFloat.random(in: 0.72...0.95, using: &rng)
        var point = start
        var forkAt = Int.random(in: 2...4, using: &rng)
        for i in 1...segments {
            let progress = CGFloat(i) / CGFloat(segments)
            let y = start.y + (endY - start.y) * progress
            let jitter = CGFloat.random(in: -0.05...0.05, using: &rng) * size.width
            let x = point.x + jitter
            let next = CGPoint(x: x, y: y)
            path.addLine(to: next)
            // One fork: a short connected branch off the main channel, then
            // the pen returns to the main path to carry on descending.
            if i == forkAt {
                var branch = next
                path.move(to: next)
                for _ in 0..<3 {
                    branch = CGPoint(
                        x: branch.x - CGFloat.random(in: 0.01...0.06, using: &rng) * size.width,
                        y: branch.y + size.height * 0.055)
                    path.addLine(to: branch)
                }
                path.move(to: next)
                forkAt = -1
            }
            point = next
        }
        return path
    }
}
