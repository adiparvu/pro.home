import SwiftUI
import SpriteKit
import UIKit

// MARK: - AppBackdropEffects — real atmosphere over the living backdrop
//
// Optional weather effects layered ABOVE the mood palette's gradients:
// rain (two streak depths + a sparse very-fast third, splashes, a drifting
// mist band, probabilistic lightning), snow (two parallax flake layers with
// rotation drift and an alpha twinkle), and a once-a-day event shimmer.
// The visual reference is Apple's Weather app; the budget reference is not —
// every particle count here is deliberately a fraction of it.
//
// THE ENERGY CONTRACT (AtmosphericEffectsPolicy is its type):
// Effects exist in the view tree ONLY while ALL of these hold —
//   1. the user's "Efecte atmosferice" toggle is ON ("app.mood.effects",
//      default true — the moods that use effects are opt-in choices already),
//   2. accessibilityReduceMotion == false (absolute; there is no reduced
//      variant — the backdrop simply stays the static palette),
//   3. Low Power Mode is OFF (observed live via
//      .NSProcessInfoPowerStateDidChange, so an active scene unmounts the
//      moment the battery panel flips),
// and the hosting SpriteView PAUSES (isPaused, which idles SKView's render
// loop — not a hide) the moment scenePhase leaves .active; leaving the
// screen removes the view entirely. When any of 1–3 fails the SpriteView is
// never mounted at all — the static backdrop's cost stays EXACTLY zero, no
// empty scene, no observers beyond three cheap @Observable reads.
//
// PARTICLE BUDGETS (steady-state live count = birthRate × lifetime; for the
// streak layers lifetime is derived from the actual scene height so the live
// count holds by construction on every device):
//   Rain  ≈ 45 far + 44 near + 14 fast + ~4 splashes + ~5 mist ≈ 112 < 150
//   Snow  = 54 far + 28 near = 82 < 100
//   Event = 30 total, one-shot, dead ≤ 2.6 s after appear — then nothing.
// The SpriteView renders at 60 fps on its own CADisplayLink (particle motion
// gains nothing perceptible from 120), leaving SwiftUI free to run the UI at
// 120 on ProMotion. Particle textures are tiny white @2x images rendered
// once with UIGraphicsImageRenderer and cached in static lets; color comes
// from per-emitter tinting, so light and dark grounds share every texture.

// MARK: - AtmosphericEffectsPolicy (the energy contract as a type)

/// The single authority on whether atmospheric effects may exist. Views ask
/// `allowsMounting(reduceMotion:)` (Reduce Motion is per-view environment —
/// the two process-wide gates live here); `scenePhase` stays a view concern
/// because pausing, unlike mounting, is per-scene.
///
/// STATE → WHAT RUNS:
///   toggle OFF / Reduce Motion / Low Power  → nothing mounted (zero cost)
///   mood without effects                    → nothing mounted (zero cost)
///   all gates pass, scenePhase == .active   → SpriteView @ 60 fps + (rain
///                                             only) one sleeping lightning task
///   all gates pass, scenePhase != .active   → SpriteView mounted but PAUSED
///                                             (SKView idle), lightning task
///                                             cancelled — no timers at all
///   backdrop leaves the screen              → view unmounted, scene released
@MainActor
@Observable
final class AtmosphericEffectsPolicy {
    static let shared = AtmosphericEffectsPolicy()

    private static let enabledKey = "app.mood.effects"
    private static let sparkleDayKey = "app.mood.effects.sparkleDay"

    /// The user's "Efecte atmosferice" toggle (Settings → Aspect → Fundal).
    /// Persisted; default ON — rain/winter/event are already opt-in moods.
    var userEnabled: Bool {
        didSet { UserDefaults.standard.set(userEnabled, forKey: Self.enabledKey) }
    }

    /// Mirrors `ProcessInfo.processInfo.isLowPowerModeEnabled`, kept live by
    /// the power-state notification so an active scene reacts immediately.
    private(set) var isLowPowerMode: Bool

    private init() {
        userEnabled = (UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool) ?? true
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        // The notification arrives on an arbitrary queue; hop to the main
        // actor before touching observable state. The closure runs long
        // after init returns, so referencing `shared` cannot re-enter it.
        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: nil
        ) { _ in
            Task { @MainActor in
                AtmosphericEffectsPolicy.shared.isLowPowerMode =
                    ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }

    /// Whether a scene may exist at all right now. Reduce Motion is passed
    /// in because it is environment state the view already observes.
    func allowsMounting(reduceMotion: Bool) -> Bool {
        userEnabled && !reduceMotion && !isLowPowerMode
    }

    /// The effect a mood wants, if any. The night mood joins in only while
    /// the engine's live weather tone says it is actually raining — the
    /// night-with-rain modulation keeps the night palette, but the drops
    /// still deserve to be real there.
    static func effect(for mood: AppMood, weatherTone: AppWeatherTone?) -> AtmosphericEffect? {
        switch mood {
        case .rain:   .rain(scheme: .light)
        case .night:  weatherTone == .rain ? .rain(scheme: .dark) : nil
        case .winter: .snow
        case .event:  .sparkle
        default:      nil
        }
    }

    /// Claims today's one event shimmer. Returns true exactly once per
    /// calendar day — the first event backdrop to appear that day plays the
    /// 2.5 s shimmer; every later one stays static, as designed.
    func takeDailySparkle(now: Date = .now) -> Bool {
        let day = Calendar.current.startOfDay(for: now).timeIntervalSinceReferenceDate
        let defaults = UserDefaults.standard
        guard defaults.double(forKey: Self.sparkleDayKey) != day else { return false }
        defaults.set(day, forKey: Self.sparkleDayKey)
        return true
    }
}

/// What a mood renders when the policy allows effects. The rain case carries
/// the ground's scheme because streaks must be slate-dark over the light
/// rain palette and pale over the night ground to read at all.
enum AtmosphericEffect: Hashable {
    case rain(scheme: ColorScheme)
    case snow
    case sparkle
}

// MARK: - AppBackdropEffectsLayer (what AppBackdrop composes)

/// The optional live layer above the palette gradients. Renders NOTHING —
/// not even an empty scene — unless the mood wants an effect and the policy
/// allows mounting; `AppBackdrop`'s static cost is untouched when this
/// resolves to the empty branch.
struct AppBackdropEffectsLayer: View {
    let mood: AppMood

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // Three cheap observable reads decide the branch; when it is empty,
        // that is the layer's ENTIRE cost.
        let effect = AtmosphericEffectsPolicy.effect(
            for: mood, weatherTone: AppMoodEngine.shared.weatherTone)
        if let effect,
           AtmosphericEffectsPolicy.shared.allowsMounting(reduceMotion: reduceMotion) {
            EffectsSceneHost(effect: effect, isRunning: scenePhase == .active)
                .id(effect)   // mood/scheme change = a fresh scene, old one released
                .allowsHitTesting(false)
                .accessibilityHidden(true)   // pure atmosphere
        }
    }
}

/// Owns the one SKScene of a backdrop instance (state resets with the
/// parent's `.id(effect)`, so a mood change swaps scenes cleanly), pauses it
/// with the scene phase, and runs the rain-only lightning scheduler.
private struct EffectsSceneHost: View {
    let effect: AtmosphericEffect
    let isRunning: Bool

    @State private var scene: SKScene?
    /// The event shimmer is strictly one-shot: spent means either played
    /// here or already claimed by an earlier backdrop today.
    @State private var sparkleSpent = false

    var body: some View {
        ZStack {
            if let scene {
                // isPaused (not a hide): SKView stops advancing/rendering
                // the instant the scene phase leaves .active.
                SpriteView(scene: scene,
                           isPaused: !isRunning,
                           preferredFramesPerSecond: 60,
                           options: [.allowsTransparency])
                    .transition(.opacity)
            }
            if case .rain(let scheme) = effect {
                LightningLayer(scheme: scheme, isRunning: isRunning)
            }
        }
        .onAppear(perform: mountIfNeeded)
        // A sparkle that arrived while inactive mounts on activation.
        .onChange(of: isRunning) { _, nowRunning in
            if nowRunning { mountIfNeeded() }
        }
        // The shimmer's whole life is ~2.57 s; afterwards the SpriteView
        // leaves the tree and the event backdrop is static again. Keyed to
        // the running state so nothing counts down while paused.
        .task(id: sparkleCleanupArmed) {
            guard sparkleCleanupArmed else { return }
            try? await Task.sleep(for: .seconds(2.7))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) { scene = nil }
        }
    }

    private var sparkleCleanupArmed: Bool {
        effect == .sparkle && scene != nil && isRunning
    }

    private func mountIfNeeded() {
        guard scene == nil, !sparkleSpent else { return }
        switch effect {
        case .rain(let scheme):
            scene = RainScene(scheme: scheme)
        case .snow:
            scene = SnowScene()
        case .sparkle:
            // Claim the day only when the shimmer can actually play NOW —
            // a paused mount must not silently spend it.
            guard isRunning else { return }
            sparkleSpent = true
            guard AtmosphericEffectsPolicy.shared.takeDailySparkle() else { return }
            scene = EventSparkleScene()
        }
    }
}

// MARK: - Lightning (rain only, probabilistic — the flash IS the realism)

/// Every 25–70 s (uniform), a two-pulse flash biased toward a random point
/// on the top third — Apple's rain brightens the cloud field, never the
/// whole screen uniformly — followed by a 1.5 s cool afterglow where the
/// palette's accents live. No bolt is ever drawn. Between strikes exactly
/// one task sleeps in the scheduler; the two gradients sit at opacity 0
/// (compositor skips fully transparent layers). Ambient — no haptic.
private struct LightningLayer: View {
    let scheme: ColorScheme
    let isRunning: Bool

    @State private var flash: Double = 0
    @State private var afterglow: Double = 0
    @State private var origin = UnitPoint(x: 0.32, y: 0.04)

    var body: some View {
        ZStack {
            // Fixed gradient stops; only .opacity animates — the gradients
            // themselves are never rebuilt mid-flash.
            RadialGradient(colors: [.white, .white.opacity(0.35), .clear],
                           center: origin, startRadius: 0, endRadius: 640)
                .opacity(flash)
            RadialGradient(colors: [afterglowColor, .clear],
                           center: origin, startRadius: 0, endRadius: 560)
                .opacity(afterglow)
        }
        .task(id: isRunning) {
            guard isRunning else { return }   // paused → the task is cancelled: no timers
            while !Task.isCancelled {
                let wait = Double.random(in: 25...70)
                guard (try? await Task.sleep(for: .seconds(wait))) != nil else { return }
                await strike()
            }
        }
    }

    /// Cool storm-light tint over the backdrop accents while the flash decays.
    private var afterglowColor: Color {
        scheme == .dark
            ? Color(red: 0.741, green: 0.816, blue: 0.929)   // pale ice over night
            : Color(red: 0.545, green: 0.647, blue: 0.788)   // slate blue over rain ground
    }

    /// Two pulses — ~18% white for 120 ms, then ~8% for 280 ms, both
    /// .easeOut — with the 1.5 s afterglow riding the first. The tiny sleeps
    /// let each unanimated jump land on screen before its fade starts
    /// (SwiftUI coalesces same-turn state writes).
    @MainActor
    private func strike() async {
        origin = UnitPoint(x: .random(in: 0.15...0.85), y: .random(in: -0.05...0.12))
        flash = 0.18
        afterglow = 0.08
        try? await Task.sleep(for: .milliseconds(30))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.12)) { flash = 0 }
        withAnimation(.easeOut(duration: 1.5)) { afterglow = 0 }
        try? await Task.sleep(for: .milliseconds(160))
        guard !Task.isCancelled else { return }
        flash = 0.08
        try? await Task.sleep(for: .milliseconds(30))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.28)) { flash = 0 }
    }
}

// MARK: - Rain scene (three streak depths + splashes + mist)

/// Wind-angled rain. All layers share one 12° tilt (one wind), differ in
/// speed/size/alpha for depth, and carry per-particle alpha, length, and
/// angle jitter. Streak lifetime is derived from the live scene height so
/// every drop crosses the whole screen and the live count stays exactly the
/// target on any device: lifetime = (height + margin) / slowestSpeed,
/// birthRate = targetLive / lifetime.
private final class RainScene: SKScene {
    /// 12° from vertical — consistent across every layer, splash drift, and
    /// the mist's direction of travel.
    private static let windTilt: CGFloat = 12 * .pi / 180

    private struct StreakSpec {
        let targetLive: CGFloat   // steady-state live particles
        let speed: CGFloat
        let speedRange: CGFloat
    }

    /// (emitter, spec) pairs whose lifetime/birthRate follow the scene size.
    private var streaks: [(SKEmitterNode, StreakSpec)] = []
    private let mist = SKEmitterNode()
    private let splash = SKEmitterNode()
    private var prewarmed = false

    init(scheme: ColorScheme) {
        super.init(size: CGSize(width: 390, height: 850))
        scaleMode = .resizeFill
        backgroundColor = .clear

        let dark = scheme == .dark
        // Slate ink over the light rain palette; pale blue over night.
        let far  = dark ? UIColor(red: 0.741, green: 0.808, blue: 0.871, alpha: 1)
                        : UIColor(red: 0.310, green: 0.416, blue: 0.518, alpha: 1)
        let near = dark ? UIColor(red: 0.796, green: 0.855, blue: 0.906, alpha: 1)
                        : UIColor(red: 0.235, green: 0.357, blue: 0.455, alpha: 1)
        let mistColor = dark ? UIColor(red: 0.686, green: 0.765, blue: 0.827, alpha: 1)
                             : UIColor(red: 0.549, green: 0.635, blue: 0.710, alpha: 1)

        // Depth 1 — far: thin, dim, slower.   45 live = birthRate × lifetime.
        let farEmitter = Self.streakEmitter(
            texture: AtmosphericParticleTextures.farStreak, color: far,
            alpha: 0.32, alphaRange: 0.12)
        streaks.append((farEmitter, StreakSpec(targetLive: 45, speed: 700, speedRange: 120)))
        // Depth 2 — near: larger, softly bright (halo baked in the texture),
        // fastest of the visible bodies. 44 live.
        let nearEmitter = Self.streakEmitter(
            texture: AtmosphericParticleTextures.nearStreak, color: near,
            alpha: 0.45, alphaRange: 0.15)
        streaks.append((nearEmitter, StreakSpec(targetLive: 44, speed: 1000, speedRange: 150)))
        // Depth 3 — sparse, very fast, very faint (Apple's third depth). 14 live.
        let fastEmitter = Self.streakEmitter(
            texture: AtmosphericParticleTextures.fastStreak, color: far,
            alpha: 0.22, alphaRange: 0.08)
        streaks.append((fastEmitter, StreakSpec(targetLive: 14, speed: 1350, speedRange: 150)))

        farEmitter.zPosition = 1
        fastEmitter.zPosition = 2
        nearEmitter.zPosition = 3

        // Barely-there mist band drifting with the wind: ~5 huge soft blobs
        // (0.28/s × 18 s) at ≤ 5% alpha — presence, not fog.
        mist.particleTexture = AtmosphericParticleTextures.mist
        mist.particleColor = mistColor
        mist.particleColorBlendFactor = 1
        mist.particleBirthRate = 0.28
        mist.particleLifetime = 18
        mist.particleLifetimeRange = 4
        mist.emissionAngle = 0            // rightward — the wind's direction
        mist.particleSpeed = 14
        mist.particleSpeedRange = 6
        mist.particleAlphaSequence = SKKeyframeSequence(
            keyframeValues: [0.0, 0.05, 0.05, 0.0], times: [0, 0.25, 0.75, 1])
        mist.particleScale = 3.2
        mist.particleScaleRange = 0.8
        mist.zPosition = 0

        // Ground splashes: a handful of short-lived expanding ellipse rings
        // along the bottom edge (12/s × 0.35 s ≈ 4 live) — what makes the
        // rain read grounded.
        splash.particleTexture = AtmosphericParticleTextures.splashRing
        splash.particleColor = near
        splash.particleColorBlendFactor = 1
        splash.particleBirthRate = 12
        splash.particleLifetime = 0.35
        splash.particleLifetimeRange = 0.1
        splash.particleSpeed = 0
        splash.particleAlpha = 0.30
        splash.particleAlphaRange = 0.10
        splash.particleAlphaSpeed = -0.85
        splash.particleScale = 0.35
        splash.particleScaleRange = 0.15
        splash.particleScaleSpeed = 1.5
        splash.zPosition = 4

        for (emitter, _) in streaks { addChild(emitter) }
        addChild(mist)
        addChild(splash)
        layoutEmitters()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("RainScene is code-built only") }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutEmitters()
    }

    private static func streakEmitter(texture: SKTexture, color: UIColor,
                                      alpha: CGFloat, alphaRange: CGFloat) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = texture
        e.particleColor = color
        e.particleColorBlendFactor = 1
        e.emissionAngle = -.pi / 2 + windTilt   // down, leaning with the wind
        e.emissionAngleRange = 0.05             // ~3° per-drop angle jitter
        e.particleRotation = windTilt           // streak axis follows velocity
        e.particleAlpha = alpha
        e.particleAlphaRange = alphaRange       // per-particle alpha variation
        e.particleScale = 1
        e.particleScaleRange = 0.28             // per-particle length variation
        return e
    }

    /// Sizes everything to the real scene: streak lifetimes span the full
    /// height (+ margin) at each layer's SLOWEST speed so no drop dies
    /// mid-screen, and birth rates are re-derived to hold the live targets.
    private func layoutEmitters() {
        guard size.width > 1, size.height > 1 else { return }
        let travel = size.height + 120
        let drift = travel * tan(Self.windTilt)   // horizontal wind carry
        for (emitter, spec) in streaks {
            let lifetime = travel / (spec.speed - spec.speedRange)
            emitter.particleLifetime = lifetime
            emitter.particleBirthRate = spec.targetLive / lifetime
            emitter.particleSpeed = spec.speed
            emitter.particleSpeedRange = spec.speedRange
            // Spawn line above the top edge, widened and shifted against the
            // wind so the tilted fall still covers both screen edges.
            emitter.position = CGPoint(x: size.width / 2 - drift / 2,
                                       y: size.height + 60)
            emitter.particlePositionRange = CGVector(dx: size.width + drift + 80, dy: 30)
        }
        mist.position = CGPoint(x: size.width / 2, y: size.height * 0.30)
        mist.particlePositionRange = CGVector(dx: size.width, dy: size.height * 0.14)
        splash.position = CGPoint(x: size.width / 2, y: 26)
        splash.particlePositionRange = CGVector(dx: size.width, dy: 18)
    }

    /// Prewarm on the first simulated frame — by then the SpriteView has
    /// already sized the scene, so the very first RENDERED frame shows a
    /// full rain field with no visible fill-in. Runs exactly once.
    override func update(_ currentTime: TimeInterval) {
        guard !prewarmed else { return }
        prewarmed = true
        for (emitter, _) in streaks {
            emitter.advanceSimulationTime(TimeInterval(emitter.particleLifetime))
        }
        mist.advanceSimulationTime(20)
        splash.advanceSimulationTime(1)
    }
}

// MARK: - Snow scene (two parallax flake layers)

/// Slow flakes with per-flake rotation drift (the flake texture is slightly
/// asymmetric, so rotation actually reads) and a gentle brightness twinkle.
/// Flakes spawn across the whole height and fade in/out mid-air — Apple's
/// flakes do the same — which keeps lifetimes, and therefore the live
/// count, small: 54 + 28 = 82 < 100. Horizontal sway comes from opposing
/// per-layer xAcceleration, so the two depths visibly cross-drift.
private final class SnowScene: SKScene {
    private let farFlakes = SKEmitterNode()
    private let nearFlakes = SKEmitterNode()
    private var prewarmed = false

    override init() {
        super.init(size: CGSize(width: 390, height: 850))
        scaleMode = .resizeFill
        backgroundColor = .clear

        // Cool gray-blue — honest visibility over the near-white winter
        // ground (white-on-white flakes would simply not exist).
        let flakeColor = UIColor(red: 0.470, green: 0.580, blue: 0.680, alpha: 1)

        // Far: 6.75/s × 8 s = 54 live, ~2–3 pt.
        Self.configure(farFlakes, color: flakeColor,
                       birthRate: 6.75, lifetime: 8,
                       speed: 55, speedRange: 20,
                       scale: 0.16, scaleRange: 0.05,   // 16 pt texture → ~2.6 pt
                       peakAlpha: 0.55,
                       xAcceleration: 6, rotationSpeed: 0.45)
        // Near: 4/s × 7 s = 28 live, ~4–5 pt, swaying the other way.
        Self.configure(nearFlakes, color: flakeColor,
                       birthRate: 4, lifetime: 7,
                       speed: 90, speedRange: 25,
                       scale: 0.28, scaleRange: 0.06,   // → ~4.5 pt
                       peakAlpha: 0.80,
                       xAcceleration: -7, rotationSpeed: -0.7)
        farFlakes.zPosition = 0
        nearFlakes.zPosition = 1
        addChild(farFlakes)
        addChild(nearFlakes)
        layoutEmitters()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SnowScene is code-built only") }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutEmitters()
    }

    private static func configure(_ e: SKEmitterNode, color: UIColor,
                                  birthRate: CGFloat, lifetime: CGFloat,
                                  speed: CGFloat, speedRange: CGFloat,
                                  scale: CGFloat, scaleRange: CGFloat,
                                  peakAlpha: Double,
                                  xAcceleration: CGFloat, rotationSpeed: CGFloat) {
        e.particleTexture = AtmosphericParticleTextures.flake
        e.particleColor = color
        e.particleColorBlendFactor = 1
        e.particleBirthRate = birthRate
        e.particleLifetime = lifetime
        e.particleLifetimeRange = lifetime * 0.2
        e.emissionAngle = -.pi / 2
        e.emissionAngleRange = 0.35
        e.particleSpeed = speed
        e.particleSpeedRange = speedRange
        e.xAcceleration = xAcceleration          // the layer's sway direction
        e.particleScale = scale
        e.particleScaleRange = scaleRange
        e.particleRotationRange = 2 * .pi        // every flake lands differently
        e.particleRotationSpeed = rotationSpeed  // per-layer rotation drift
        // Fade in, twinkle once mid-fall, fade out — mid-air death never pops.
        e.particleAlphaSequence = SKKeyframeSequence(
            keyframeValues: [0.0, peakAlpha, peakAlpha * 0.55, peakAlpha, 0.0],
            times: [0, 0.15, 0.45, 0.75, 1])
    }

    private func layoutEmitters() {
        guard size.width > 1, size.height > 1 else { return }
        for e in [farFlakes, nearFlakes] {
            e.position = CGPoint(x: size.width / 2, y: size.height / 2)
            // Spawn across the whole field (not just the top edge): steady
            // state covers every region even though flakes die mid-fall.
            e.particlePositionRange = CGVector(dx: size.width + 80,
                                               dy: size.height + 120)
        }
    }

    /// One-time prewarm on the first simulated frame (see RainScene.update).
    override func update(_ currentTime: TimeInterval) {
        guard !prewarmed else { return }
        prewarmed = true
        farFlakes.advanceSimulationTime(9)
        nearFlakes.advanceSimulationTime(8)
    }
}

// MARK: - Event sparkle scene (one-shot 2.5 s gold shimmer)

/// Exactly 30 soft gold motes rising gently from the lower half — emitted
/// over ~0.67 s, each living ≤ 1.9 s, everything gone by ~2.57 s. The host
/// then removes the SpriteView entirely; the event backdrop is static for
/// the rest of the day. Elegance over spectacle.
private final class EventSparkleScene: SKScene {
    private let motes = SKEmitterNode()

    override init() {
        super.init(size: CGSize(width: 390, height: 850))
        scaleMode = .resizeFill
        backgroundColor = .clear

        motes.particleTexture = AtmosphericParticleTextures.dot
        // The event palette's festive gold (#E9C15E).
        motes.particleColor = UIColor(red: 0.914, green: 0.757, blue: 0.369, alpha: 1)
        motes.particleColorBlendFactor = 1
        motes.numParticlesToEmit = 30            // the whole budget, one-shot
        motes.particleBirthRate = 45
        motes.particleLifetime = 1.7
        motes.particleLifetimeRange = 0.4        // all dead by 30/45 + 1.9 ≈ 2.57 s
        motes.emissionAngle = .pi / 2            // rising
        motes.emissionAngleRange = 0.5
        motes.particleSpeed = 42
        motes.particleSpeedRange = 18
        motes.particleScale = 0.30
        motes.particleScaleRange = 0.18
        motes.particleRotationRange = 2 * .pi
        motes.particleAlphaSequence = SKKeyframeSequence(
            keyframeValues: [0.0, 0.55, 0.0], times: [0, 0.35, 1])
        addChild(motes)
        layoutEmitter()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("EventSparkleScene is code-built only") }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutEmitter()
    }

    private func layoutEmitter() {
        guard size.width > 1, size.height > 1 else { return }
        motes.position = CGPoint(x: size.width / 2, y: size.height * 0.30)
        motes.particlePositionRange = CGVector(dx: size.width * 0.75,
                                               dy: size.height * 0.35)
    }
}

// MARK: - Particle textures (rendered once, cached statically)

/// Tiny white @2x textures shared by every scene — rendered lazily on first
/// use with UIGraphicsImageRenderer and kept for the process lifetime.
/// White + per-emitter tint means one texture set serves both schemes.
private enum AtmosphericParticleTextures {
    /// Depth 1 rain streak: 2×26 pt, hard-edged, dim.
    static let farStreak = streak(width: 2, height: 26, halo: 0)
    /// Depth 2 rain streak: 3.5×34 pt with a soft halo (the "slightly
    /// blurred-bright" near layer — blur is baked, never live).
    static let nearStreak = streak(width: 3.5, height: 34, halo: 2)
    /// Depth 3 rain streak: 1.5×42 pt needle for the very-fast faint layer.
    static let fastStreak = streak(width: 1.5, height: 42, halo: 0)
    /// Soft round dot (event motes).
    static let dot = radialDot(diameter: 12, asymmetric: false)
    /// Slightly asymmetric soft blob — snow. The lobe off center is what
    /// makes per-flake rotation drift visible on something this small.
    static let flake = radialDot(diameter: 16, asymmetric: true)
    /// Large soft blob scaled up ~3× for the drifting mist band.
    static let mist = mistBlob(diameter: 96)
    /// Thin ellipse ring that expands and fades — a rain splash.
    static let splashRing = splashEllipse(size: CGSize(width: 14, height: 5))

    private static func renderer(_ size: CGSize) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 2   // tinted motes this small gain nothing from @3x
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    /// Vertical capsule with alpha fading at both tips; `halo` adds a wider
    /// soft capsule behind it for the near layer's baked glow.
    private static func streak(width: CGFloat, height: CGFloat, halo: CGFloat) -> SKTexture {
        let pad = halo + 1
        let canvas = CGSize(width: width + pad * 2, height: height + pad * 2)
        let image = renderer(canvas).image { ctx in
            let cg = ctx.cgContext
            if halo > 0 {
                let haloRect = CGRect(x: 1, y: 1,
                                      width: width + halo * 2, height: height + halo * 2)
                fillCapsule(cg, rect: haloRect, alphas: [0, 0.35, 0.35, 0])
            }
            let body = CGRect(x: pad, y: pad, width: width, height: height)
            fillCapsule(cg, rect: body, alphas: [0, 1, 1, 0])
        }
        return SKTexture(image: image)
    }

    private static func fillCapsule(_ cg: CGContext, rect: CGRect, alphas: [CGFloat]) {
        cg.saveGState()
        cg.addPath(UIBezierPath(roundedRect: rect, cornerRadius: rect.width / 2).cgPath)
        cg.clip()
        let colors = alphas.map { UIColor.white.withAlphaComponent($0).cgColor }
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors as CFArray,
                                     locations: [0, 0.3, 0.7, 1]) {
            cg.drawLinearGradient(gradient,
                                  start: CGPoint(x: rect.midX, y: rect.minY),
                                  end: CGPoint(x: rect.midX, y: rect.maxY),
                                  options: [])
        }
        cg.restoreGState()
    }

    private static func radialDot(diameter: CGFloat, asymmetric: Bool) -> SKTexture {
        let canvas = CGSize(width: diameter, height: diameter)
        let image = renderer(canvas).image { ctx in
            let cg = ctx.cgContext
            drawRadialFade(cg, center: CGPoint(x: diameter / 2, y: diameter / 2),
                           radius: diameter / 2, peak: 1)
            if asymmetric {
                // A dimmer lobe off center: rotation becomes visible.
                drawRadialFade(cg, center: CGPoint(x: diameter * 0.68, y: diameter * 0.40),
                               radius: diameter * 0.22, peak: 0.7)
            }
        }
        return SKTexture(image: image)
    }

    private static func mistBlob(diameter: CGFloat) -> SKTexture {
        let image = renderer(CGSize(width: diameter, height: diameter)).image { ctx in
            drawRadialFade(ctx.cgContext,
                           center: CGPoint(x: diameter / 2, y: diameter / 2),
                           radius: diameter / 2, peak: 0.9)
        }
        return SKTexture(image: image)
    }

    private static func drawRadialFade(_ cg: CGContext, center: CGPoint,
                                       radius: CGFloat, peak: CGFloat) {
        let colors = [UIColor.white.withAlphaComponent(peak).cgColor,
                      UIColor.white.withAlphaComponent(peak * 0.35).cgColor,
                      UIColor.white.withAlphaComponent(0).cgColor]
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors as CFArray,
                                        locations: [0, 0.45, 1]) else { return }
        cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                              endCenter: center, endRadius: radius, options: [])
    }

    private static func splashEllipse(size: CGSize) -> SKTexture {
        let canvas = CGSize(width: size.width + 2, height: size.height + 2)
        let image = renderer(canvas).image { ctx in
            let cg = ctx.cgContext
            cg.setStrokeColor(UIColor.white.cgColor)
            cg.setLineWidth(1)
            cg.strokeEllipse(in: CGRect(x: 1, y: 1, width: size.width, height: size.height))
        }
        return SKTexture(image: image)
    }
}

// MARK: - Static hint for fixed previews (no live scenes per card)

/// What the settings carousel cards show instead of a scene: a handful of
/// pre-baked marks drawn once in a Canvas — the mood's weather signature at
/// zero ongoing cost. Positions are deterministic (no RNG at render), in
/// unit coordinates so the hint scales with any preview. Moods without
/// effects render nothing at all.
struct AppBackdropEffectsHint: View {
    let mood: AppMood

    /// (x, y, alpha) in unit space; rain marks add the shared 12° wind tilt.
    private static let rainMarks: [(CGFloat, CGFloat, CGFloat)] = [
        (0.14, 0.18, 0.38), (0.30, 0.55, 0.26), (0.44, 0.12, 0.44),
        (0.58, 0.68, 0.30), (0.70, 0.30, 0.40), (0.84, 0.58, 0.26),
        (0.92, 0.15, 0.34),
    ]
    private static let snowMarks: [(CGFloat, CGFloat, CGFloat)] = [
        (0.12, 0.22, 0.55), (0.26, 0.62, 0.40), (0.38, 0.14, 0.60),
        (0.52, 0.44, 0.45), (0.64, 0.74, 0.55), (0.76, 0.26, 0.40),
        (0.88, 0.56, 0.60), (0.94, 0.12, 0.35),
    ]
    private static let sparkMarks: [(CGFloat, CGFloat, CGFloat)] = [
        (0.18, 0.66, 0.50), (0.32, 0.38, 0.35), (0.50, 0.72, 0.55),
        (0.66, 0.30, 0.40), (0.80, 0.58, 0.50), (0.90, 0.80, 0.30),
    ]

    var body: some View {
        switch mood {
        case .rain:   marks(kind: .rain)
        case .winter: marks(kind: .snow)
        case .event:  marks(kind: .spark)
        default:      EmptyView()
        }
    }

    private enum Kind { case rain, snow, spark }

    private func marks(kind: Kind) -> some View {
        Canvas { context, size in
            switch kind {
            case .rain:
                // Short streaks leaning the scene's 12° — the same wind.
                let tilt = 12 * CGFloat.pi / 180
                let len = max(10, size.height * 0.14)
                let color = Color(red: 0.235, green: 0.357, blue: 0.455)
                for (x, y, alpha) in Self.rainMarks {
                    var path = Path()
                    let start = CGPoint(x: x * size.width, y: y * size.height)
                    path.move(to: start)
                    path.addLine(to: CGPoint(x: start.x + len * sin(tilt),
                                             y: start.y + len * cos(tilt)))
                    context.stroke(path, with: .color(color.opacity(alpha)),
                                   style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                }
            case .snow:
                let color = Color(red: 0.470, green: 0.580, blue: 0.680)
                for (x, y, alpha) in Self.snowMarks {
                    let r: CGFloat = alpha > 0.5 ? 2.4 : 1.7
                    let rect = CGRect(x: x * size.width - r, y: y * size.height - r,
                                      width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(color.opacity(alpha)))
                }
            case .spark:
                let gold = Color(red: 0.914, green: 0.757, blue: 0.369)
                for (x, y, alpha) in Self.sparkMarks {
                    let r: CGFloat = alpha > 0.45 ? 1.9 : 1.3
                    let rect = CGRect(x: x * size.width - r, y: y * size.height - r,
                                      width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(gold.opacity(alpha)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
