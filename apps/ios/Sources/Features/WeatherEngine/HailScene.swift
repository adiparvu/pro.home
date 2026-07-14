import SwiftUI
import SpriteKit
import UIKit

// MARK: - Weather Engine · HailScene (Composite · hail)
//
// Hard ice pellets over a cold steel storm sky, with flash accents. It replaces
// the generic path for `.hail` and layers, from BACK to FRONT:
//
//   1. STEEL STORM SKY — a cold, hard steel-grey depth gradient (WeatherSkyGradient)
//      over the stage's base sky, plus a dark low storm deck (a flat, bruised
//      CloudField). Hard and cold, not the soft blue-white of snow.
//   2. PELLETS — a dedicated SpriteKit emitter (HailPelletScene): small, hard,
//      bright ice pellets falling FAST and STRAIGHT (little wind), in two depths
//      for parallax, plus a short BOUNCE/SCATTER burst along the bottom edge so
//      the pellets read as striking a hard surface. This is its OWN emitter, not
//      the rain streaks or the snow flakes — pellets are round, hard, straight
//      and bouncing, so they cannot be either of those systems.
//   3. FLASH ILLUMINATION (Metal) — the same additive bloom the storm uses,
//      driven by the engine's live `flashLevel` (hail arms the stage's lightning
//      scheduler via `flashEnabled`). Sparse but violent.
//
// ENERGY: the pellet SpriteView mounts only when `context.motionEnabled` and
// PAUSES off-screen (isPaused with `isActive`); the still frame shows the steel
// sky + storm deck + a frozen flash bloom — no SpriteKit, no animating shader.
struct HailScene: WeatherScene {
    let context: WeatherSceneContext

    init(context: WeatherSceneContext) { self.context = context }

    var body: some View {
        let p = context.parameters
        ZStack {
            // 1. Cold steel storm sky + a dark bruised deck.
            WeatherSkyGradient(
                zenith: WeatherRGB(0.22, 0.26, 0.33), zenithStrength: 0.34,
                horizon: WeatherRGB(0.52, 0.57, 0.64), horizonStrength: 0.30,
                zenithSpan: 0.6, horizonStart: 0.5)

            if p.cloudCover > 0.02 {
                CloudField(cover: p.cloudCover, darkness: max(p.cloudDarkness, 0.42),
                           warmth: 0, wind: p.windStrength,
                           time: context.time, band: 0.0...0.34)
            }

            // 2. Hard ice pellets (dedicated SpriteKit emitter). Motion-gated;
            //    the still frame never shows a paused pellet field.
            if context.motionEnabled {
                ComposedHailView(isActive: context.isActive).equatable()
            }

            // 3. Flash accents — the shared Metal illumination bloom.
            if p.flashEnabled {
                LightningIlluminationLayer(origin: context.flashOrigin,
                                           flash: context.flashLevel,
                                           tint: WeatherLight.flashTint,
                                           size: context.size)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Composed SpriteKit host (pause-aware, same contract as rain/snow)

/// Hosts the dedicated `HailPelletScene`. Pauses the SKView with the scene phase
/// (energy contract); the scene is created once and kept in `@State`, identity
/// stable so it is not rebuilt per frame.
struct ComposedHailView: View, Equatable {
    let isActive: Bool

    @State private var scene: SKScene?

    var body: some View {
        Group {
            if let scene {
                SpriteView(scene: scene, isPaused: !isActive,
                           preferredFramesPerSecond: 60,
                           options: [.allowsTransparency])
            }
        }
        .onAppear {
            if scene == nil { scene = HailPelletScene() }
        }
        .allowsHitTesting(false)
    }

    static func == (lhs: ComposedHailView, rhs: ComposedHailView) -> Bool {
        lhs.isActive == rhs.isActive
    }
}

// MARK: - Hail pellet scene (dedicated SpriteKit emitter + bottom bounce)
//
// PARTICLE BUDGET (steady-state live count = birthRate × lifetime; the falling
// layers derive lifetime from the real scene height so the live count holds by
// construction on every device, exactly like RainScene):
//   far pellets  = 16 live (small, dim, ~950 pt/s)
//   near pellets = 18 live (larger, bright, ~1150 pt/s)
//   bounce       = 16/s × 0.5 s = 8 live (short arced scatter along the bottom)
//   total ≈ 42 live < 60 — sparse but violent, well under the rain budget (112).
// The SpriteView renders at 60 fps on its own display link; particle textures
// are tiny white @2x images rendered once and cached statically; the cold steel
// tint comes from per-emitter colouring, like every other scene.
final class HailPelletScene: SKScene {
    private struct PelletSpec {
        let targetLive: CGFloat
        let speed: CGFloat
        let speedRange: CGFloat
    }

    /// (emitter, spec) pairs whose lifetime/birthRate follow the scene height.
    private var pellets: [(SKEmitterNode, PelletSpec)] = []
    private let bounce = SKEmitterNode()
    private var prewarmed = false

    /// Cold blue-white steel — hard and bright over the storm-grey sky.
    private static let pelletColor = UIColor(red: 0.82, green: 0.88, blue: 0.96, alpha: 1)

    override init() {
        super.init(size: CGSize(width: 390, height: 850))
        scaleMode = .resizeFill
        backgroundColor = .clear

        // Far depth — small, dim, fast.  16 live = birthRate × lifetime.
        let far = Self.pelletEmitter(texture: HailTextures.pellet,
                                     color: Self.pelletColor,
                                     scale: 0.34, scaleRange: 0.08,
                                     alpha: 0.55, alphaRange: 0.15)
        pellets.append((far, PelletSpec(targetLive: 16, speed: 950, speedRange: 120)))
        // Near depth — larger, bright, faster.  18 live.
        let near = Self.pelletEmitter(texture: HailTextures.pellet,
                                      color: Self.pelletColor,
                                      scale: 0.5, scaleRange: 0.12,
                                      alpha: 0.9, alphaRange: 0.1)
        pellets.append((near, PelletSpec(targetLive: 18, speed: 1150, speedRange: 150)))
        far.zPosition = 0
        near.zPosition = 1

        // Bottom bounce/scatter: tiny pellets flung UP and out with gravity, so
        // they arc back down — a short, hard bounce off the ground. 16/s × 0.5 s
        // ≈ 8 live. yAcceleration is the gravity that makes the arc.
        bounce.particleTexture = HailTextures.chip
        bounce.particleColor = Self.pelletColor
        bounce.particleColorBlendFactor = 1
        bounce.particleBirthRate = 16
        bounce.particleLifetime = 0.5
        bounce.particleLifetimeRange = 0.15
        bounce.emissionAngle = .pi / 2          // straight up…
        bounce.emissionAngleRange = 0.9         // …fanned into a scatter
        bounce.particleSpeed = 260
        bounce.particleSpeedRange = 120
        bounce.yAcceleration = -900             // gravity → the pellets fall back
        bounce.particleScale = 0.22
        bounce.particleScaleRange = 0.1
        bounce.particleAlpha = 0.85
        bounce.particleAlphaRange = 0.1
        bounce.particleAlphaSpeed = -1.4        // fade as they scatter
        bounce.zPosition = 2

        for (emitter, _) in pellets { addChild(emitter) }
        addChild(bounce)
        layoutEmitters()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("HailPelletScene is code-built only") }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutEmitters()
    }

    private static func pelletEmitter(texture: SKTexture, color: UIColor,
                                      scale: CGFloat, scaleRange: CGFloat,
                                      alpha: CGFloat, alphaRange: CGFloat) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = texture
        e.particleColor = color
        e.particleColorBlendFactor = 1
        e.emissionAngle = -.pi / 2       // straight down — hail falls straight
        e.emissionAngleRange = 0.03      // ~2° — barely any wind
        e.particleAlpha = alpha
        e.particleAlphaRange = alphaRange
        e.particleScale = scale
        e.particleScaleRange = scaleRange
        return e
    }

    /// Sizes the falling layers to the real scene: lifetime spans the full
    /// height (+ margin) at each layer's SLOWEST speed so no pellet dies
    /// mid-screen, and birth rate is re-derived to hold the live target.
    private func layoutEmitters() {
        guard size.width > 1, size.height > 1 else { return }
        let travel = size.height + 120
        for (emitter, spec) in pellets {
            let lifetime = travel / (spec.speed - spec.speedRange)
            emitter.particleLifetime = lifetime
            emitter.particleBirthRate = spec.targetLive / lifetime
            emitter.particleSpeed = spec.speed
            emitter.particleSpeedRange = spec.speedRange
            emitter.position = CGPoint(x: size.width / 2, y: size.height + 60)
            emitter.particlePositionRange = CGVector(dx: size.width + 40, dy: 30)
        }
        bounce.position = CGPoint(x: size.width / 2, y: 10)
        bounce.particlePositionRange = CGVector(dx: size.width, dy: 8)
    }

    /// One-time prewarm on the first simulated frame (see RainScene.update): the
    /// first RENDERED frame already shows a full pellet field, no fill-in.
    override func update(_ currentTime: TimeInterval) {
        guard !prewarmed else { return }
        prewarmed = true
        for (emitter, _) in pellets {
            emitter.advanceSimulationTime(TimeInterval(emitter.particleLifetime))
        }
        bounce.advanceSimulationTime(1)
    }
}

// MARK: - Hail textures (rendered once, cached statically)

/// Tiny white @2x textures for the pellets — rendered lazily on first use with
/// UIGraphicsImageRenderer and kept for the process lifetime, the same pattern
/// AppBackdropEffects uses. White + per-emitter tint means one set serves any
/// scheme. Self-contained here so the hail emitter adds nothing to the shared
/// mood-backdrop texture set.
private enum HailTextures {
    /// A hard ice pellet: an almost-flat opaque disc with a crisp edge (NOT the
    /// soft falloff of a snow flake) and a small bright specular highlight, so
    /// it reads as a hard, round, reflective ball of ice.
    static let pellet = pelletTexture(diameter: 9)
    /// A smaller hard chip for the bounce scatter.
    static let chip = pelletTexture(diameter: 5)

    private static func renderer(_ size: CGSize) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    private static func pelletTexture(diameter: CGFloat) -> SKTexture {
        let image = renderer(CGSize(width: diameter, height: diameter)).image { ctx in
            let cg = ctx.cgContext
            let c = CGPoint(x: diameter / 2, y: diameter / 2)
            // Hard body: opaque out to 60% of the radius, then a quick crisp
            // falloff — reads far harder than a flake's gentle fade.
            let body = [UIColor.white.withAlphaComponent(0.92).cgColor,
                        UIColor.white.withAlphaComponent(0.92).cgColor,
                        UIColor.white.withAlphaComponent(0.5).cgColor,
                        UIColor.white.withAlphaComponent(0).cgColor]
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: body as CFArray, locations: [0, 0.6, 0.82, 1]) {
                cg.drawRadialGradient(g, startCenter: c, startRadius: 0,
                                      endCenter: c, endRadius: diameter / 2, options: [])
            }
            // Specular highlight — a small denser (full-alpha) dot upper-left,
            // brighter than the 0.92 body after tinting, so ice catches light.
            let hl = CGPoint(x: diameter * 0.36, y: diameter * 0.34)
            let hlR = diameter * 0.18
            let spec = [UIColor.white.withAlphaComponent(1).cgColor,
                        UIColor.white.withAlphaComponent(0).cgColor]
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: spec as CFArray, locations: [0, 1]) {
                cg.drawRadialGradient(g, startCenter: hl, startRadius: 0,
                                      endCenter: hl, endRadius: hlR, options: [])
            }
        }
        return SKTexture(image: image)
    }
}
