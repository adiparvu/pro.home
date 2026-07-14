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
// Plus a Canvas BRANCHING BOLT (Phase 2): a recursively midpoint-displaced main
// channel with 1–4 forks, regenerated per strike, with a bright white core over
// a baked wide glow (no live blur). Its reach, width, and fork count scale with
// the per-strike magnitude, so some strikes are full-screen and close while
// others are short and distant. The Metal illumination shader does the
// atmospheric work (sky bloom biased to the bolt origin); together they read as
// a real strike.
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
                                 isActive: context.isActive,
                                 airborneDust: true)
                    .equatable()
            }

            // Canvas branching bolt — a recursively displaced channel with
            // forks, keyed to the flash origin/magnitude, visible only at the
            // bright peak of a strike.
            LightningBolt(origin: context.flashOrigin,
                          flash: context.flashLevel,
                          magnitude: context.flashMagnitude,
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

// MARK: - Lightning bolt (Canvas · recursive branching)

/// A recursively-branched bolt from the strike origin toward the ground, drawn
/// only while `flash` is above the bright-peak threshold. The channel is built
/// by MIDPOINT DISPLACEMENT (a segment is repeatedly split and its midpoint
/// pushed perpendicular by a decreasing amount — a cheap 1-D fractal that reads
/// as a natural jagged bolt), plus 1–4 FORKS that branch off the main channel
/// with the same generator at reduced length/brightness.
///
/// PER-STRIKE VARIETY: geometry is seeded deterministically from the origin +
/// magnitude, so it is stable within one strike and fresh on the next. A high
/// `magnitude` reaches the ground with a wide, forked channel (a close strike);
/// a low magnitude is a short, thin, few-forked bolt high in the sky (distant).
///
/// GLOW is BAKED as three stacked strokes (wide-faint → mid → white core) — no
/// Canvas `.blur` (a live blur is a real GPU cost; softness is layered instead).
private struct LightningBolt: View {
    var origin: UnitPoint
    /// 0...1 live brightness (already magnitude-scaled) — drives opacity.
    var flash: Double
    /// 0...1 per-strike magnitude — drives reach, width and fork count.
    var magnitude: Double
    var size: CGSize

    /// Below this the bolt is not drawn (the long dim afterglow shows only the
    /// sky bloom, no channel). Kept low so a distant, dim strike still flashes
    /// its short bolt.
    private static let threshold = 0.14

    var body: some View {
        Canvas { context, canvasSize in
            guard flash > Self.threshold, canvasSize.width > 1 else { return }
            let alpha = min(1, (flash - Self.threshold) / (1 - Self.threshold))
            let channels = boltChannels(size: canvasSize)

            // Core width and glow scale with the strike magnitude.
            let coreW = 1.2 + 1.6 * magnitude
            for channel in channels {
                let w = coreW * channel.weight
                // Wide faint glow → mid tint → bright white core.
                context.stroke(channel.path,
                    with: .color(WeatherLight.flashTint.opacity(alpha * 0.16 * channel.weight)),
                    style: StrokeStyle(lineWidth: w * 4.5, lineCap: .round, lineJoin: .round))
                context.stroke(channel.path,
                    with: .color(WeatherLight.flashTint.opacity(alpha * 0.45 * channel.weight)),
                    style: StrokeStyle(lineWidth: w * 2.0, lineCap: .round, lineJoin: .round))
                context.stroke(channel.path,
                    with: .color(.white.opacity(alpha * channel.weight)),
                    style: StrokeStyle(lineWidth: max(0.8, w * 0.7), lineCap: .round, lineJoin: .round))
            }
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    private struct Channel { let path: Path; let weight: Double }

    /// The main channel plus its forks, as (path, brightness-weight) pairs.
    private func boltChannels(size: CGSize) -> [Channel] {
        var rng = SystemRandomNumberGeneratorSeeded(
            seed: UInt64(abs(origin.x * 100_000).rounded()) &* 2_654_435_761
                &+ UInt64(abs(origin.y * 100_000).rounded())
                &+ UInt64(abs(magnitude * 9_973).rounded()) &* 40_503)

        let start = CGPoint(x: origin.x * size.width, y: origin.y * size.height)
        // Reach: distant strike ends high (~0.45h), close strike hits ~0.95h.
        let endY = size.height * (0.45 + 0.5 * magnitude)
        let endX = start.x + CGFloat.random(in: -0.18...0.18, using: &rng) * size.width
        let end = CGPoint(x: endX, y: endY)
        let disp = size.width * (0.06 + 0.06 * magnitude)   // jaggedness

        var mainPts: [CGPoint] = [start]
        subdivide(start, end, displacement: disp, depth: 5, rng: &rng, into: &mainPts)
        var channels = [Channel(path: polyline(mainPts), weight: 1.0)]

        // Forks: 1 (distant) → 4 (close). Each springs from a node on the lower
        // ⅔ of the main channel and runs shorter, dimmer, thinner.
        let forkCount = max(1, Int((1 + 3 * magnitude).rounded()))
        for _ in 0..<forkCount {
            guard mainPts.count > 4 else { break }
            let idx = Int.random(in: (mainPts.count / 3)...(mainPts.count - 2), using: &rng)
            let a = mainPts[idx]
            let branchLen = CGFloat.random(in: 0.14...0.30, using: &rng)
            let b = CGPoint(
                x: a.x + CGFloat.random(in: -0.22...0.22, using: &rng) * size.width,
                y: a.y + branchLen * size.height)
            var pts: [CGPoint] = [a]
            subdivide(a, b, displacement: disp * 0.6, depth: 3, rng: &rng, into: &pts)
            channels.append(Channel(path: polyline(pts),
                                    weight: Double.random(in: 0.35...0.6)))
        }
        return channels
    }

    /// Midpoint displacement: split a→b, push the midpoint perpendicular by a
    /// random amount, recurse on each half with the displacement halved.
    private func subdivide(_ a: CGPoint, _ b: CGPoint, displacement: CGFloat,
                           depth: Int, rng: inout SystemRandomNumberGeneratorSeeded,
                           into pts: inout [CGPoint]) {
        if depth == 0 { pts.append(b); return }
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(0.0001, (dx * dx + dy * dy).squareRoot())
        // Unit perpendicular to the segment.
        let px = -dy / len, py = dx / len
        let off = CGFloat.random(in: -displacement...displacement, using: &rng)
        let m = CGPoint(x: mid.x + px * off, y: mid.y + py * off)
        subdivide(a, m, displacement: displacement * 0.55, depth: depth - 1, rng: &rng, into: &pts)
        subdivide(m, b, displacement: displacement * 0.55, depth: depth - 1, rng: &rng, into: &pts)
    }

    private func polyline(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        for p in pts.dropFirst() { path.addLine(to: p) }
        return path
    }
}
