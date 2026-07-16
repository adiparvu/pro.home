import SwiftUI
import SpriteKit
import UIKit

// MARK: - AppBackdropEffects — real atmosphere over the living backdrop
//
// Optional signature effects layered ABOVE the mood palette's gradients —
// every one of the seven atmospheres now carries one:
//   rain    — two streak depths (the near one with a bright leading bead) + a
//             sparse very-fast third, crown splashes, a drifting mist band,
//             probabilistic lightning, and slow WIND GUSTS that lean the whole
//             fall harder and let it relax (a sine pair, no extra particles)
//   winter  — two parallax layers of real six-armed crystal flakes with
//             rotation drift, a mid-fall twinkle, and the same slow gusts
//             carrying the layers in opposing waves
//   night   — a pre-baked star field (one static sprite) faintly colour-varied
//             with glints on the brightest, a barely-there milky-way band
//             baked into the same texture, THE MOON at its real astronomical
//             phase (terminator + maria + soft halo, one baked sprite pair),
//             ~20 four-point twinkling sparkles, and a rare shooting star
//             (60–180 s scheduler); when it actually rains at night, the rain
//             wins and the sky stays behind the clouds
//   morning — golden dust motes drifting lazily through two soft sun shafts
//             (baked light wedges, additive, breathing over ~8 s)
//   day     — three enormous ultra-soft clouds crossing over minutes, over a
//             farther, slower, dimmer pair — real depth parallax
//   sunset  — a continuous warm low sun-glow + faint golden drift, with a
//             once-a-day bird flock crossing above
//   event   — the once-a-day ~2.5 s shimmer: soft gold motes + bright
//             four-point sparkles rising together
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
// streak/cloud layers lifetime is derived from the actual scene size so the
// live count holds by construction on every device):
//   Rain    ≈ 45 far + 44 near + 14 fast + ~4 splashes + ~5 mist ≈ 112 < 150
//             (gusts modulate three xAcceleration values — zero particles)
//   Snow    = 54 far + 28 near = 82 < 100 (gusts: two property writes/frame)
//   Night   = 1 baked star-field sprite + 2 moon sprites + 20 twinkles
//             + ≤1 shooting streak ≤ 24
//   Morning = 2.5/s × 10 s = 25 motes + 2 static shaft sprites
//   Day     = 3 near + 2 far clouds (birthRate = live/lifetime — exact)
//   Sunset  = 0.15/s × 20 s = 3 drift blobs + ≤9 bird sprites for ~7 s, once a day
//   Event   = 30 total, one-shot, dead ≤ 2.6 s after appear — then nothing.
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
///   all gates pass, scenePhase == .active   → SpriteView @ 60 fps + at most
///                                             ONE sleeping scheduler task
///                                             (rain: lightning; night:
///                                             shooting stars; others: none)
///   all gates pass, scenePhase != .active   → SpriteView mounted but PAUSED
///                                             (SKView idle), scheduler task
///                                             cancelled — no timers at all
///   backdrop leaves the screen              → view unmounted, scene released
@MainActor
@Observable
final class AtmosphericEffectsPolicy {
    static let shared = AtmosphericEffectsPolicy()

    private static let enabledKey = "app.mood.effects"
    private static let sparkleDayKey = "app.mood.effects.sparkleDay"
    private static let flockDayKey = "app.mood.effects.flockDay"

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

    /// The signature effect each mood renders when the policy allows
    /// mounting — every atmosphere carries one. The night mood joins the
    /// rain only while the engine's live weather tone says it is actually
    /// raining: the night-with-rain modulation keeps the night palette, but
    /// the drops still deserve to be real there — and the stars honestly
    /// stay behind the clouds.
    static func effect(for mood: AppMood, weatherTone: AppWeatherTone?) -> AtmosphericEffect {
        switch mood {
        case .morning: .morningMotes
        case .day:     .dayClouds
        case .sunset:  .sunsetGlow
        case .night:   weatherTone == .rain ? .rain(scheme: .dark) : .stars
        case .rain:    .rain(scheme: .light)
        case .winter:  .snow
        case .event:   .sparkle
        }
    }

    /// Claims today's one event shimmer. Returns true exactly once per
    /// calendar day — the first event backdrop to appear that day plays the
    /// 2.5 s shimmer; every later one stays static, as designed.
    func takeDailySparkle(now: Date = .now) -> Bool {
        Self.takeDaily(key: Self.sparkleDayKey, now: now)
    }

    /// Claims today's one sunset bird flock — the same once-per-calendar-day
    /// mechanism as the shimmer, on its own key: the first sunset backdrop
    /// to appear that day plays the crossing; the golden drift underneath is
    /// continuous regardless.
    func takeDailyFlock(now: Date = .now) -> Bool {
        Self.takeDaily(key: Self.flockDayKey, now: now)
    }

    private static func takeDaily(key: String, now: Date) -> Bool {
        let day = Calendar.current.startOfDay(for: now).timeIntervalSinceReferenceDate
        let defaults = UserDefaults.standard
        guard defaults.double(forKey: key) != day else { return false }
        defaults.set(day, forKey: key)
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
    case stars          // night: baked field + twinkles + rare shooting star
    case morningMotes   // morning: golden dust in the light
    case dayClouds      // day: three enormous barely-there passing clouds
    case sunsetGlow     // sunset: faint golden drift + once-a-day bird flock
}

// MARK: - AppBackdropEffectsLayer (what AppBackdrop composes)

/// The optional live layer above the palette gradients. Renders NOTHING —
/// not even an empty scene — unless the policy allows mounting;
/// `AppBackdrop`'s static cost is untouched when this resolves to the empty
/// branch. Every mood now carries a signature effect, so the mount decision
/// is purely the energy policy's.
struct AppBackdropEffectsLayer: View {
    let mood: AppMood

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // Three cheap observable reads decide the branch; when it is empty,
        // that is the layer's ENTIRE cost.
        if AtmosphericEffectsPolicy.shared.allowsMounting(reduceMotion: reduceMotion) {
            let effect = AtmosphericEffectsPolicy.effect(
                for: mood, weatherTone: AppMoodEngine.shared.weatherTone)
            EffectsSceneHost(effect: effect, isRunning: scenePhase == .active)
                .id(effect)   // mood/scheme change = a fresh scene, old one released
                .allowsHitTesting(false)
                .accessibilityHidden(true)   // pure atmosphere
        }
    }
}

/// Owns the one SKScene of a backdrop instance (state resets with the
/// parent's `.id(effect)`, so a mood change swaps scenes cleanly), pauses it
/// with the scene phase, and runs the per-effect scheduler (rain: lightning;
/// night: shooting stars; sunset: the one-shot flock claim).
private struct EffectsSceneHost: View {
    let effect: AtmosphericEffect
    let isRunning: Bool

    @State private var scene: SKScene?
    /// The event shimmer is strictly one-shot: spent means either played
    /// here or already claimed by an earlier backdrop today.
    @State private var sparkleSpent = false
    /// Same contract for the sunset flock — but unlike the shimmer it rides
    /// a continuous scene, so only the crossing is once a day, not the mount.
    @State private var flockSpent = false

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
        // Shooting stars ride the exact lightning pause matrix: between
        // streaks exactly one task sleeps, and pausing cancels it (task(id:)
        // re-arms on resume) — no timers exist while the scene is paused.
        .task(id: shootingStarArmed) {
            guard shootingStarArmed else { return }
            while !Task.isCancelled {
                let wait = Double.random(in: 60...180)
                guard (try? await Task.sleep(for: .seconds(wait))) != nil else { return }
                (scene as? NightStarsScene)?.spawnShootingStar()
            }
        }
    }

    private var sparkleCleanupArmed: Bool {
        effect == .sparkle && scene != nil && isRunning
    }

    private var shootingStarArmed: Bool {
        effect == .stars && scene != nil && isRunning
    }

    private func mountIfNeeded() {
        if scene == nil, !sparkleSpent {
            switch effect {
            case .rain(let scheme):
                scene = RainScene(scheme: scheme)
            case .snow:
                scene = SnowScene()
            case .stars:
                scene = NightStarsScene()
            case .morningMotes:
                scene = MorningMotesScene()
            case .dayClouds:
                scene = DayCloudsScene()
            case .sunsetGlow:
                scene = SunsetGlowScene()
            case .sparkle:
                // Claim the day only when the shimmer can actually play
                // NOW — a paused mount must not silently spend it.
                guard isRunning else { break }
                sparkleSpent = true
                if AtmosphericEffectsPolicy.shared.takeDailySparkle() {
                    scene = EventSparkleScene()
                }
            }
        }
        armFlockIfReady()
    }

    /// Mirrors the sparkle's "claim only when it can play NOW" rule for the
    /// sunset flock: a paused mount leaves the claim untouched, and the
    /// activation path re-enters through `mountIfNeeded`.
    private func armFlockIfReady() {
        guard effect == .sunsetGlow, !flockSpent, isRunning,
              let glow = scene as? SunsetGlowScene else { return }
        flockSpent = true
        guard AtmosphericEffectsPolicy.shared.takeDailyFlock() else { return }
        glow.runFlock()
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
final class RainScene: SKScene {
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
    /// full rain field with no visible fill-in — then drive the WIND GUSTS:
    /// a slow two-sine breathing (periods ~33 s and ~2 min, never in phase)
    /// bends every live streak via xAcceleration, so the whole fall leans
    /// harder and relaxes the way real rain does. Three property writes per
    /// frame — no particles, no nodes, no timers.
    override func update(_ currentTime: TimeInterval) {
        if !prewarmed {
            prewarmed = true
            for (emitter, _) in streaks {
                emitter.advanceSimulationTime(TimeInterval(emitter.particleLifetime))
            }
            mist.advanceSimulationTime(20)
            splash.advanceSimulationTime(1)
        }
        let gust = sin(currentTime * 0.19) * 0.6 + sin(currentTime * 0.053) * 0.4
        for (emitter, spec) in streaks {
            // Faster (nearer) layers feel the wind more — depth stays honest.
            emitter.xAcceleration = CGFloat(gust) * spec.speed * 0.10
        }
        // The mist band rides the same wind, drifting faster on the gust.
        mist.particleSpeed = 14 + CGFloat(gust) * 6
    }
}

// MARK: - Snow scene (two parallax flake layers)

/// Slow flakes with per-flake rotation drift (the six-armed crystal texture
/// turns visibly) and a gentle brightness twinkle.
/// Flakes spawn across the whole height and fade in/out mid-air — Apple's
/// flakes do the same — which keeps lifetimes, and therefore the live
/// count, small: 54 + 28 = 82 < 100. Horizontal sway comes from opposing
/// per-layer xAcceleration, so the two depths visibly cross-drift.
// Each particle now carries a real six-armed CRYSTAL texture (not a blob), so
// the per-flake rotation reads as an actual snowflake turning as it falls.
final class SnowScene: SKScene {
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

        // Far: 6.75/s × 8 s = 54 live. The 22 pt crystal at 0.14 → ~3 pt.
        Self.configure(farFlakes, color: flakeColor,
                       birthRate: 6.75, lifetime: 8,
                       speed: 55, speedRange: 20,
                       scale: 0.14, scaleRange: 0.05,
                       peakAlpha: 0.52,
                       xAcceleration: 6, rotationSpeed: 0.30)
        // Near: 4/s × 7 s = 28 live, larger crystals swaying the other way.
        Self.configure(nearFlakes, color: flakeColor,
                       birthRate: 4, lifetime: 7,
                       speed: 90, speedRange: 25,
                       scale: 0.24, scaleRange: 0.07,   // → ~5.3 pt crystals
                       peakAlpha: 0.78,
                       xAcceleration: -7, rotationSpeed: -0.45)
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
                                  xAcceleration: CGFloat, rotationSpeed: CGFloat,
                                  emissionAngle: CGFloat = -.pi / 2) {
        e.particleTexture = AtmosphericParticleTextures.flake
        e.particleColor = color
        e.particleColorBlendFactor = 1
        e.particleBirthRate = birthRate
        e.particleLifetime = lifetime
        e.particleLifetimeRange = lifetime * 0.2
        e.emissionAngle = emissionAngle
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

    /// One-time prewarm (see RainScene.update), then the winter wind: the
    /// same slow two-sine gusting as the rain, phase-shifted per layer so the
    /// two depths are carried in opposing waves — flakes visibly swept
    /// sideways in gusts instead of falling uniformly. Two writes per frame.
    override func update(_ currentTime: TimeInterval) {
        if !prewarmed {
            prewarmed = true
            farFlakes.advanceSimulationTime(9)
            nearFlakes.advanceSimulationTime(8)
        }
        let gust = sin(currentTime * 0.16) * 0.6 + sin(currentTime * 0.047) * 0.4
        // Around each layer's base sway (+6 / −7), so the cross-drift
        // survives calm moments and both layers surge together in a gust.
        farFlakes.xAcceleration = 6 + CGFloat(gust) * 11
        nearFlakes.xAcceleration = -7 + CGFloat(gust) * 15
    }
}

// MARK: - Event sparkle scene (one-shot 2.5 s gold shimmer)

/// Exactly 30 soft gold motes rising gently from the lower half — emitted
/// over ~0.67 s, each living ≤ 1.9 s, everything gone by ~2.57 s. The host
/// then removes the SpriteView entirely; the event backdrop is static for
/// the rest of the day. Elegance over spectacle.
private final class EventSparkleScene: SKScene {
    private let motes = SKEmitterNode()
    /// A dozen brighter four-point sparkles mixed through the soft motes — the
    /// glints that make a celebration read as a celebration, not just dust.
    private let sparks = SKEmitterNode()

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
        motes.zPosition = 0
        addChild(motes)

        // Bright sparkles: warmer, larger four-point glints rising with the
        // motes, spinning slowly so the diffraction cross flashes. 12 total,
        // one-shot, gone within the same ~2.6 s window.
        sparks.particleTexture = AtmosphericParticleTextures.sparkleStar
        sparks.particleColor = UIColor(red: 1.0, green: 0.90, blue: 0.62, alpha: 1)
        sparks.particleColorBlendFactor = 1
        sparks.particleBlendMode = .add
        sparks.numParticlesToEmit = 12
        sparks.particleBirthRate = 18
        sparks.particleLifetime = 1.6
        sparks.particleLifetimeRange = 0.4
        sparks.emissionAngle = .pi / 2
        sparks.emissionAngleRange = 0.7
        sparks.particleSpeed = 36
        sparks.particleSpeedRange = 20
        sparks.particleScale = 0.22
        sparks.particleScaleRange = 0.12
        sparks.particleRotationRange = 2 * .pi
        sparks.particleRotationSpeed = 1.2       // the cross flashes as it turns
        sparks.particleAlphaSequence = SKKeyframeSequence(
            keyframeValues: [0.0, 0.9, 0.0], times: [0, 0.4, 1])
        sparks.zPosition = 1
        addChild(sparks)
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
        for emitter in [motes, sparks] {
            emitter.position = CGPoint(x: size.width / 2, y: size.height * 0.30)
            emitter.particlePositionRange = CGVector(dx: size.width * 0.75,
                                                     dy: size.height * 0.35)
        }
    }
}

// MARK: - Night stars scene (baked field + twinkles + rare shooting star)

/// The night sky in three costs:
///  1. A star FIELD — 80 dots of varying size/alpha baked into ONE texture
///     on one static sprite. Zero per-frame cost beyond compositing a single
///     quad; the texture lives with the scene and is released on unmount.
///  2. 20 live twinkle sprites running slow alpha tweens only — no movement,
///     one shared tiny texture, so SpriteKit batches them in one draw.
///  3. A rare shooting star: every 60–180 s the host's scheduler task (the
///     lightning pattern — cancelled while paused) asks for ONE streak, a
///     pre-baked bright-head/fading-tail texture moved across a top-area
///     diagonal over 0.7 s with an .easeIn alpha out.
/// Budget: 1 static field sprite + 20 twinkles + ≤1 streak ≤ 22 live nodes.
private final class NightStarsScene: SKScene {
    /// A star in unit space. For the baked field `size` is the dot radius in
    /// points; for twinkles it is the sprite scale on the 22 pt sparkle texture
    /// and `alpha` is the twinkle's PEAK.
    private struct StarSpec {
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let alpha: CGFloat
    }

    private let fieldNode = SKSpriteNode()
    private var fieldSpecs: [StarSpec] = []
    private var twinkles: [(sprite: SKSpriteNode, spec: StarSpec)] = []
    /// The scene size the field texture was last baked for — re-baked only
    /// on a real size change (rotation), never per frame.
    private var bakedFieldSize: CGSize = .zero
    /// The moon at tonight's REAL phase: one baked disc sprite (terminator +
    /// maria) over one soft halo sprite. Nil within ~a day of new moon — an
    /// honest sky has no moon to show then.
    private var moonDisc: SKSpriteNode?
    private var moonHalo: SKSpriteNode?

    override init() {
        super.init(size: CGSize(width: 390, height: 850))
        scaleMode = .resizeFill
        backgroundColor = .clear

        // The sky is a designed constellation, not a dice roll: a fixed seed
        // bakes the same field on every mount and every re-bake, so stars
        // never jump on rotation or between screens.
        var rng = SplitMix64(seed: 0x5EED_57A2_F1E1D)
        fieldSpecs = (0..<80).map { _ in
            StarSpec(x: .random(in: 0.01...0.99, using: &rng),
                     y: .random(in: 0.01...0.99, using: &rng),
                     size: .random(in: 0.5...1.3, using: &rng),
                     alpha: .random(in: 0.12...0.55, using: &rng))
        }

        // Twinkles: four-point sparkles (not plain dots) with a real sky's
        // faint colour spread — most cool ice, a few warm. Alpha keyframe
        // tweens only. Random initial alpha + per-star durations desync phases.
        let coolStar = UIColor(red: 0.855, green: 0.894, blue: 0.965, alpha: 1)
        let warmStar = UIColor(red: 0.980, green: 0.930, blue: 0.830, alpha: 1)
        for _ in 0..<20 {
            let spec = StarSpec(x: .random(in: 0.03...0.97, using: &rng),
                                y: .random(in: 0.05...0.97, using: &rng),
                                size: .random(in: 0.10...0.20, using: &rng),  // ~2.2–4.4 pt
                                alpha: .random(in: 0.45...0.75, using: &rng))
            let sprite = SKSpriteNode(texture: AtmosphericParticleTextures.sparkleStar)
            // One star in four leans warm — a real sky is not one colour.
            sprite.color = Double.random(in: 0...1, using: &rng) < 0.25 ? warmStar : coolStar
            sprite.colorBlendFactor = 1
            sprite.setScale(spec.size)
            sprite.zPosition = 1
            let dim = spec.alpha * 0.3
            sprite.alpha = .random(in: dim...spec.alpha, using: &rng)
            let down = SKAction.fadeAlpha(to: dim,
                                          duration: .random(in: 1.6...3.2, using: &rng))
            down.timingMode = .easeInEaseOut
            let up = SKAction.fadeAlpha(to: spec.alpha,
                                        duration: .random(in: 1.6...3.2, using: &rng))
            up.timingMode = .easeInEaseOut
            sprite.run(.repeatForever(.sequence([down, up])))
            twinkles.append((sprite, spec))
            addChild(sprite)
        }

        fieldNode.zPosition = 0
        addChild(fieldNode)

        // The moon, at its real astronomical phase tonight. Within ~a day of
        // new moon there is honestly nothing to draw. The halo breathes very
        // slowly (±25% of its 8% alpha); the disc itself is static.
        let phase = Self.moonPhase()
        let illuminated = (1 - cos(2 * .pi * phase)) / 2
        if illuminated > 0.03 {
            let halo = SKSpriteNode(texture: AtmosphericParticleTextures.moonHalo)
            halo.color = UIColor(red: 0.88, green: 0.91, blue: 0.97, alpha: 1)
            halo.colorBlendFactor = 1
            halo.blendMode = .add
            halo.alpha = 0.08
            halo.zPosition = 0.4
            let dim = SKAction.fadeAlpha(to: 0.06, duration: 5.5)
            dim.timingMode = .easeInEaseOut
            let lift = SKAction.fadeAlpha(to: 0.10, duration: 5.5)
            lift.timingMode = .easeInEaseOut
            halo.run(.repeatForever(.sequence([dim, lift])))
            addChild(halo)
            moonHalo = halo

            let disc = SKSpriteNode(texture: Self.moonTexture(phase: phase, diameter: 44))
            disc.alpha = 0.85
            disc.zPosition = 0.5
            addChild(disc)
            moonDisc = disc
        }
        layoutNodes()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("NightStarsScene is code-built only") }

    /// The lunar phase now, in [0, 1): 0 = new, 0.5 = full. Derived from the
    /// mean synodic month (29.530589 d) against a known new-moon epoch
    /// (2000-01-06 18:14 UTC) — within ±½ day over decades, which is exactly
    /// the fidelity a backdrop needs.
    private static func moonPhase(on date: Date = .now) -> Double {
        let epoch = Date(timeIntervalSince1970: 947_182_440)   // 2000-01-06 18:14 UTC
        let synodic = 29.530589 * 86_400.0
        let raw = date.timeIntervalSince(epoch).truncatingRemainder(dividingBy: synodic)
        return (raw < 0 ? raw + synodic : raw) / synodic
    }

    /// Bakes the moon disc for a given phase: the dark side as faint
    /// earthshine, the lit region bounded by the circle's limb on the lit
    /// side and the terminator half-ellipse (semi-axis = R·cos 2πp — signed,
    /// so crescent and gibbous fall out of the same path), a few soft maria
    /// blotches clipped to the lit shape, and a touch of limb darkening.
    /// Waxing lights the right side, waning the left (northern-sky reading).
    private static func moonTexture(phase: Double, diameter: CGFloat) -> SKTexture {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 3   // the terminator's curve deserves the extra crispness
        let canvas = CGSize(width: diameter + 4, height: diameter + 4)
        let r = diameter / 2
        let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let waxing = phase < 0.5
        // Signed terminator semi-axis: +R at new → 0 at quarter → −R at full.
        let terminator = r * CGFloat(cos(2 * .pi * phase))
        let lit = UIColor(red: 0.93, green: 0.94, blue: 0.96, alpha: 1)

        let image = UIGraphicsImageRenderer(size: canvas, format: format).image { ctx in
            let cg = ctx.cgContext
            // Earthshine: the whole disc, barely there.
            cg.setFillColor(lit.withAlphaComponent(0.10).cgColor)
            cg.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))

            // The lit region: limb semicircle on the lit side + terminator
            // half-ellipse back. Built in a unit-friendly transform so the
            // signed semi-axis draws crescents and gibbous phases alike;
            // mirrored horizontally for waning.
            cg.saveGState()
            cg.translateBy(x: c.x, y: c.y)
            if !waxing { cg.scaleBy(x: -1, y: 1) }
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: -r))
            path.addArc(center: .zero, radius: r,
                        startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
            if abs(terminator) > 0.5 {
                let t = CGAffineTransform(scaleX: terminator / r, y: 1)
                path.addPath(Self.halfEllipseBackUp(radius: r), transform: t)
            } else {
                path.addLine(to: CGPoint(x: 0, y: -r))
            }
            path.closeSubpath()
            cg.addPath(path)
            cg.clip()
            cg.setFillColor(lit.cgColor)
            cg.fill(CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
            // Maria: a few soft grey blotches, fixed positions (the same face
            // always shows), visible only where the clip lets them through.
            cg.setFillColor(UIColor(red: 0.72, green: 0.75, blue: 0.80, alpha: 0.55).cgColor)
            for (mx, my, mr) in [(-0.22, -0.18, 0.30), (0.18, 0.05, 0.24),
                                 (-0.05, 0.32, 0.18), (0.30, -0.30, 0.13)] {
                let br = r * CGFloat(mr)
                cg.fillEllipse(in: CGRect(x: r * CGFloat(mx) - br, y: r * CGFloat(my) - br,
                                          width: br * 2, height: br * 2))
            }
            cg.restoreGState()

            // Limb darkening: a soft inward shadow ring so the disc reads as
            // a sphere, not a sticker.
            cg.saveGState()
            cg.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            cg.clip()
            let edge = [UIColor.clear.cgColor,
                        UIColor(white: 0.1, alpha: 0.18).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: edge, locations: [0.78, 1]) {
                cg.drawRadialGradient(g, startCenter: c, startRadius: 0,
                                      endCenter: c, endRadius: r, options: [])
            }
            cg.restoreGState()
        }
        return SKTexture(image: image)
    }

    /// The right half-ellipse of radius `radius`, traversed bottom → top —
    /// the terminator's return path (scaled by the caller's signed transform).
    private static func halfEllipseBackUp(radius: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: radius))
        p.addArc(center: .zero, radius: radius,
                 startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: false)
        return p
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutNodes()
    }

    /// One shooting star, on demand from the host's scheduler. A single
    /// transient sprite: the stretched streak texture (head at local +x)
    /// rotated onto a random top-area diagonal, one moveBy + the .easeIn
    /// fade-out over 0.7 s total, then removed.
    func spawnShootingStar() {
        guard !isPaused, size.width > 1 else { return }
        let sprite = SKSpriteNode(texture: AtmosphericParticleTextures.shootingStreak)
        sprite.color = UIColor(red: 0.92, green: 0.95, blue: 1.0, alpha: 1)
        sprite.colorBlendFactor = 1
        let fromLeft = Bool.random()
        let startX = size.width * .random(in: 0.15...0.60)
        sprite.position = CGPoint(x: fromLeft ? startX : size.width - startX,
                                  y: size.height * .random(in: 0.78...0.94))
        let dx: CGFloat = .random(in: 190...260) * (fromLeft ? 1 : -1)
        let dy: CGFloat = -.random(in: 70...120)
        sprite.zRotation = atan2(dy, dx)   // head leads along the velocity
        sprite.alpha = 0
        sprite.zPosition = 2
        addChild(sprite)
        let fade = SKAction.fadeOut(withDuration: 0.55)
        fade.timingMode = .easeIn
        let alphaTrack = SKAction.sequence([.fadeAlpha(to: 0.9, duration: 0.08),
                                            .wait(forDuration: 0.07),
                                            fade])
        sprite.run(.sequence([.group([.moveBy(x: dx, y: dy, duration: 0.7), alphaTrack]),
                              .removeFromParent()]))
    }

    private func layoutNodes() {
        guard size.width > 1, size.height > 1 else { return }
        bakeFieldIfNeeded()
        fieldNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        for (sprite, spec) in twinkles {
            sprite.position = CGPoint(x: spec.x * size.width, y: spec.y * size.height)
        }
        // The moon rides high in the upper-right sky, clear of the title area.
        let moonCenter = CGPoint(x: size.width * 0.78, y: size.height * 0.84)
        moonDisc?.position = moonCenter
        if let halo = moonHalo {
            halo.position = moonCenter
            halo.size = CGSize(width: 150, height: 150)
        }
    }

    /// Renders the 80-dot field into one screen-sized texture (@2x for
    /// pinpoint crispness — ~5–6 MB RGBA while the night scene is mounted,
    /// released with it). Runs at init and on real size changes only.
    private func bakeFieldIfNeeded() {
        guard size != bakedFieldSize else { return }
        bakedFieldSize = size
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 2
        // A real sky is faintly coloured — most stars near-white, a few warm
        // (older) or cool-blue (hotter). Deterministic per index so the tint
        // is stable across re-bakes. The brightest stars also get a small
        // four-point glint so a handful read as prominent stars, not just dots.
        let warm = UIColor(red: 1.0, green: 0.94, blue: 0.85, alpha: 1)
        let cool = UIColor(red: 0.86, green: 0.91, blue: 1.0, alpha: 1)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            // A barely-there milky-way band: a wide soft luminance ribbon on a
            // fixed diagonal, dusted with ~70 pinpoint micro-stars along it
            // (deterministic — same seed family as the field). ≤ 3% alpha:
            // presence you sense before you see it.
            cg.saveGState()
            cg.translateBy(x: size.width * 0.5, y: size.height * 0.5)
            cg.rotate(by: -.pi / 5.2)
            let bandLen = max(size.width, size.height) * 1.6
            let bandColors = [UIColor.white.withAlphaComponent(0.030).cgColor,
                              UIColor.white.withAlphaComponent(0.012).cgColor,
                              UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: bandColors, locations: [0, 0.55, 1]) {
                // Two mirrored half-fades from the band's spine outward.
                for sign in [CGFloat(1), -1] {
                    cg.saveGState()
                    cg.clip(to: CGRect(x: -bandLen / 2, y: sign > 0 ? 0 : -110,
                                       width: bandLen, height: 110))
                    cg.drawLinearGradient(g,
                                          start: CGPoint(x: 0, y: 0),
                                          end: CGPoint(x: 0, y: sign * 110),
                                          options: [])
                    cg.restoreGState()
                }
            }
            var bandRng = SplitMix64(seed: 0x1AC7EA_11)
            cg.setFillColor(UIColor.white.withAlphaComponent(0.16).cgColor)
            for _ in 0..<70 {
                let x = CGFloat.random(in: -bandLen / 2...bandLen / 2, using: &bandRng)
                // Denser near the spine: average two uniforms toward 0.
                let y = (CGFloat.random(in: -80...80, using: &bandRng)
                       + CGFloat.random(in: -80...80, using: &bandRng)) / 2
                let d = CGFloat.random(in: 0.4...0.9, using: &bandRng)
                cg.fillEllipse(in: CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d))
            }
            cg.restoreGState()

            for (i, star) in fieldSpecs.enumerated() {
                let base: UIColor = i % 7 == 0 ? warm : (i % 5 == 0 ? cool : .white)
                let c = CGPoint(x: star.x * size.width, y: star.y * size.height)
                cg.setFillColor(base.withAlphaComponent(star.alpha).cgColor)
                cg.fillEllipse(in: CGRect(x: c.x - star.size, y: c.y - star.size,
                                          width: star.size * 2, height: star.size * 2))
                // The brightest few get thin diffraction spikes.
                if star.size > 1.1 {
                    cg.setStrokeColor(base.withAlphaComponent(star.alpha * 0.6).cgColor)
                    cg.setLineWidth(0.5)
                    cg.setLineCap(.round)
                    let spike = star.size * 3.2
                    for a in stride(from: 0, to: CGFloat.pi * 2, by: .pi / 2) {
                        cg.move(to: c)
                        cg.addLine(to: CGPoint(x: c.x + cos(a) * spike,
                                               y: c.y + sin(a) * spike))
                    }
                    cg.strokePath()
                }
            }
        }
        fieldNode.texture = SKTexture(image: image)
        fieldNode.size = size
    }
}

/// Tiny deterministic RNG (SplitMix64) for designed-once layouts — the
/// night scene's constellation must be identical across mounts and re-bakes.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Morning motes scene (golden dust in the light)

/// Sunlight through a window: ultra-soft gold discs (~3–6 pt) drifting
/// lazily in every direction at 10–20 pt/s, each arcing under a barely-there
/// downward pull. Spawned across the whole screen and faded in/out mid-air —
/// the snow spawn pattern — so lifetimes stay short and the live count small:
/// 2.5/s × 10 s = 25 motes (mission band 22–28), alpha peaking at 0.20.
private final class MorningMotesScene: SKScene {
    private let motes = SKEmitterNode()
    /// Two soft sun shafts falling from the upper-left — the light the motes
    /// are drifting THROUGH. Baked wedges, additive, breathing out of phase
    /// over ~8–11 s; two static sprites, zero per-frame work.
    private let shafts: [SKSpriteNode] = (0..<2).map { _ in
        SKSpriteNode(texture: AtmosphericParticleTextures.lightShaft)
    }
    private var prewarmed = false

    override init() {
        super.init(size: CGSize(width: 390, height: 850))
        scaleMode = .resizeFill
        backgroundColor = .clear

        for (i, shaft) in shafts.enumerated() {
            shaft.color = UIColor(red: 1.0, green: 0.88, blue: 0.66, alpha: 1)
            shaft.colorBlendFactor = 1
            shaft.blendMode = .add
            shaft.zRotation = i == 0 ? -0.34 : -0.46   // leaning from upper-left
            shaft.alpha = i == 0 ? 0.075 : 0.055
            shaft.zPosition = -1                        // behind the motes
            let low = SKAction.fadeAlpha(to: shaft.alpha * 0.55,
                                         duration: i == 0 ? 8.0 : 11.0)
            low.timingMode = .easeInEaseOut
            let high = SKAction.fadeAlpha(to: shaft.alpha,
                                          duration: i == 0 ? 8.0 : 11.0)
            high.timingMode = .easeInEaseOut
            shaft.run(.repeatForever(.sequence([low, high])))
            addChild(shaft)
        }

        motes.particleTexture = AtmosphericParticleTextures.dot
        // Warm sun-gold over the morning palette.
        motes.particleColor = UIColor(red: 0.973, green: 0.831, blue: 0.576, alpha: 1)
        motes.particleColorBlendFactor = 1
        motes.particleBirthRate = 2.5
        motes.particleLifetime = 10
        motes.particleLifetimeRange = 3
        motes.emissionAngle = 0
        motes.emissionAngleRange = 2 * .pi    // each mote picks its own lazy drift
        motes.particleSpeed = 15
        motes.particleSpeedRange = 5          // 10–20 pt/s
        motes.yAcceleration = -1.5            // gentle settle → slow individual arcs
        motes.particleScale = 0.36
        motes.particleScaleRange = 0.12       // 12 pt texture → ~2.9–5.8 pt discs
        // Fade in, dim mid-life, glint, fade out — the 0.08–0.22 alpha band.
        motes.particleAlphaSequence = SKKeyframeSequence(
            keyframeValues: [0.0, 0.20, 0.10, 0.16, 0.0],
            times: [0, 0.2, 0.5, 0.8, 1])
        addChild(motes)
        layoutEmitter()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("MorningMotesScene is code-built only") }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutEmitter()
    }

    private func layoutEmitter() {
        guard size.width > 1, size.height > 1 else { return }
        motes.position = CGPoint(x: size.width / 2, y: size.height / 2)
        motes.particlePositionRange = CGVector(dx: size.width + 60,
                                               dy: size.height + 60)
        // Shafts span most of the height, anchored toward the upper-left
        // where the morning light enters; the second sits deeper and wider.
        let span = size.height * 1.1
        for (i, shaft) in shafts.enumerated() {
            shaft.size = CGSize(width: i == 0 ? 110 : 170, height: span)
            shaft.position = CGPoint(x: size.width * (i == 0 ? 0.30 : 0.58),
                                     y: size.height * 0.62)
        }
    }

    /// One-time prewarm on the first simulated frame (see RainScene.update).
    override func update(_ currentTime: TimeInterval) {
        guard !prewarmed else { return }
        prewarmed = true
        motes.advanceSimulationTime(13)
    }
}

// MARK: - Day clouds scene (passing cloud softness)

/// The Apple clear-day feel: three enormous ultra-soft white blobs (the
/// pre-baked huge-blur disc, ~340–595 pt at scale) crossing at 4.5–7.5 pt/s
/// with lifetimes of minutes — spawn fully offscreen left, die fully
/// offscreen right — and a barely perceptible ≤ 4% alpha breathing over the
/// crossing. Live count is exact by construction: lifetime = travel /
/// slowestSpeed, birthRate = 3 / lifetime (≈ one birth every ~70 s).
private final class DayCloudsScene: SKScene {
    private static let targetLive: CGFloat = 3
    private static let speed: CGFloat = 6
    private static let speedRange: CGFloat = 1.5   // 4.5–7.5 pt/s
    private static let farTargetLive: CGFloat = 2
    private static let farSpeed: CGFloat = 3.2
    private static let farSpeedRange: CGFloat = 0.8   // 2.4–4.0 pt/s — half tempo
    /// Half the largest cloud's visual footprint (180 pt texture × max scale
    /// 3.3 ÷ 2) — both birth and death happen fully offscreen.
    private static let margin: CGFloat = 300

    private let clouds = SKEmitterNode()
    /// A farther, slower, dimmer pair behind the near layer — the depth
    /// parallax that makes the sky read as a volume, not a flat drift.
    private let farClouds = SKEmitterNode()
    private var prewarmed = false

    override init() {
        super.init(size: CGSize(width: 390, height: 850))
        scaleMode = .resizeFill
        backgroundColor = .clear

        clouds.particleTexture = AtmosphericParticleTextures.cloud
        clouds.particleColor = .white
        clouds.particleColorBlendFactor = 1
        clouds.emissionAngle = 0               // left → right
        clouds.particleSpeed = Self.speed
        clouds.particleSpeedRange = Self.speedRange
        clouds.particleScale = 2.6
        clouds.particleScaleRange = 0.7        // ~340–595 pt — screen-width scale
        // The breathing: a slow ≤ 4% swell over the minutes-long crossing.
        // Never zero — birth and death are already offscreen, so no pop.
        clouds.particleAlphaSequence = SKKeyframeSequence(
            keyframeValues: [0.028, 0.04, 0.03, 0.04, 0.028],
            times: [0, 0.3, 0.55, 0.8, 1])
        clouds.zPosition = 1
        addChild(clouds)

        farClouds.particleTexture = AtmosphericParticleTextures.cloud
        farClouds.particleColor = .white
        farClouds.particleColorBlendFactor = 1
        farClouds.emissionAngle = 0
        farClouds.particleSpeed = Self.farSpeed
        farClouds.particleSpeedRange = Self.farSpeedRange
        farClouds.particleScale = 1.5
        farClouds.particleScaleRange = 0.4     // ~200–340 pt — visibly farther
        farClouds.particleAlphaSequence = SKKeyframeSequence(
            keyframeValues: [0.018, 0.026, 0.02, 0.026, 0.018],
            times: [0, 0.3, 0.55, 0.8, 1])
        farClouds.zPosition = 0
        addChild(farClouds)
        layoutEmitter()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("DayCloudsScene is code-built only") }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutEmitter()
    }

    /// Lifetime and birth rate follow the real width so exactly ~3 clouds
    /// live on any device (the rain scene's construction, horizontal).
    private func layoutEmitter() {
        guard size.width > 1, size.height > 1 else { return }
        let travel = size.width + Self.margin * 2
        let lifetime = travel / (Self.speed - Self.speedRange)   // ≈ 220 s on iPhone
        clouds.particleLifetime = lifetime
        clouds.particleBirthRate = Self.targetLive / lifetime    // ≈ 0.0136/s
        clouds.position = CGPoint(x: -Self.margin, y: size.height * 0.60)
        clouds.particlePositionRange = CGVector(dx: 0, dy: size.height * 0.55)

        let farLifetime = travel / (Self.farSpeed - Self.farSpeedRange)
        farClouds.particleLifetime = farLifetime
        farClouds.particleBirthRate = Self.farTargetLive / farLifetime
        // The far band rides higher — distance in a sky reads as altitude.
        farClouds.position = CGPoint(x: -Self.margin, y: size.height * 0.74)
        farClouds.particlePositionRange = CGVector(dx: 0, dy: size.height * 0.40)
    }

    /// One-time prewarm: without it the sky would stay empty for minutes.
    override func update(_ currentTime: TimeInterval) {
        guard !prewarmed else { return }
        prewarmed = true
        clouds.advanceSimulationTime(TimeInterval(clouds.particleLifetime))
        farClouds.advanceSimulationTime(TimeInterval(farClouds.particleLifetime))
    }
}

// MARK: - Sunset glow scene (golden drift + once-a-day bird flock)

/// Two costs, honestly separated:
///  - CONTINUOUS golden drift — the rain scene's mist-band pattern in warm
///    gold: 0.15/s × 20 s = 3 huge soft blobs at ≤ 5% alpha, drifting slowly.
///  - ONE-SHOT bird flock — on the first sunset backdrop of the day (the
///    event shimmer's per-day claim, own key), 7–9 silhouettes cross the
///    upper third once over ~6.5–7.5 s in a loose V with per-bird offset,
///    speed, and start jitter, flapping via a two-frame texture swap, then
///    remove themselves. The claim is made by the host only while running;
///    the crossing itself launches from the first simulated frame so the
///    path always uses the real scene width.
private final class SunsetGlowScene: SKScene {
    private let drift = SKEmitterNode()
    /// The setting sun's warm bloom, low on the horizon — a continuous soft
    /// glow that breathes gently. This is the thing that makes the mood read as
    /// an actual sunset rather than "gold specks over a gradient".
    private let sunGlow = SKSpriteNode(texture: AtmosphericParticleTextures.sunGlow)
    private var prewarmed = false
    private var flockPending = false

    override init() {
        super.init(size: CGSize(width: 390, height: 850))
        scaleMode = .resizeFill
        backgroundColor = .clear

        // Warm low sun bloom — deep amber-gold, seated below the horizon so
        // only its upper glow shows. Additive so it lifts the palette warmly,
        // with a slow ±8% breathe and a barely-there scale swell.
        sunGlow.color = UIColor(red: 1.0, green: 0.66, blue: 0.34, alpha: 1)
        sunGlow.colorBlendFactor = 1
        sunGlow.blendMode = .add
        sunGlow.alpha = 0.20
        sunGlow.zPosition = -1
        let breatheDown = SKAction.fadeAlpha(to: 0.13, duration: 4.5)
        breatheDown.timingMode = .easeInEaseOut
        let breatheUp = SKAction.fadeAlpha(to: 0.22, duration: 4.5)
        breatheUp.timingMode = .easeInEaseOut
        sunGlow.run(.repeatForever(.sequence([breatheDown, breatheUp])))
        addChild(sunGlow)

        drift.particleTexture = AtmosphericParticleTextures.mist
        // Deep warm gold — reads as late light, not fog.
        drift.particleColor = UIColor(red: 1.0, green: 0.78, blue: 0.50, alpha: 1)
        drift.particleColorBlendFactor = 1
        drift.particleBirthRate = 0.15
        drift.particleLifetime = 20            // 0.15 × 20 = 3 live blobs
        drift.particleLifetimeRange = 5
        drift.emissionAngle = 0
        drift.particleSpeed = 12
        drift.particleSpeedRange = 5
        drift.particleAlphaSequence = SKKeyframeSequence(
            keyframeValues: [0.0, 0.05, 0.05, 0.0], times: [0, 0.25, 0.75, 1])
        drift.particleScale = 3.2
        drift.particleScaleRange = 0.8
        drift.zPosition = 0
        addChild(drift)
        layoutEmitter()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SunsetGlowScene is code-built only") }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutEmitter()
    }

    /// Queues the day's one crossing; it launches on the next simulated
    /// frame, when the SpriteView has already sized the scene.
    func runFlock() {
        flockPending = true
    }

    private func layoutEmitter() {
        guard size.width > 1, size.height > 1 else { return }
        drift.position = CGPoint(x: size.width / 2, y: size.height * 0.38)
        drift.particlePositionRange = CGVector(dx: size.width, dy: size.height * 0.28)
        // The sun sits low and slightly off-centre, its bloom sized to spill
        // across the width; the lower half is below the frame so only the glow
        // rises into the sky.
        let bloom = size.width * 1.7
        sunGlow.size = CGSize(width: bloom, height: bloom)
        sunGlow.position = CGPoint(x: size.width * 0.62, y: size.height * 0.14)
    }

    override func update(_ currentTime: TimeInterval) {
        if !prewarmed {
            prewarmed = true
            drift.advanceSimulationTime(24)
        }
        if flockPending, size.width > 1 {
            flockPending = false
            launchFlock()
        }
    }

    /// The loose V: a leader plus alternating-side followers, each set back
    /// and out a row with small positional jitter, individual flap tempo,
    /// start delay, and crossing duration. Every bird removes itself after
    /// exiting; the scene then holds only the drift again.
    private func launchFlock() {
        let count = Int.random(in: 7...9)
        let fromLeft = Bool.random()
        let dir: CGFloat = fromLeft ? 1 : -1
        let baseY = size.height * .random(in: 0.72...0.82)
        let baseDuration = Double.random(in: 6.5...7.5)
        let startX = fromLeft ? -80 : size.width + 80
        let travel = size.width + 160
        let silhouette = UIColor(red: 0.28, green: 0.17, blue: 0.14, alpha: 1)
        for i in 0..<count {
            let row = CGFloat((i + 1) / 2)
            let side: CGFloat = i == 0 ? 0 : (i % 2 == 1 ? 1 : -1)
            let bird = SKSpriteNode(texture: AtmosphericParticleTextures.birdFrames[i % 2])
            bird.color = silhouette
            bird.colorBlendFactor = 1
            bird.alpha = 0.62
            bird.setScale(.random(in: 0.85...1.1))
            let setBack = row * 16 + .random(in: -4...4)
            bird.position = CGPoint(x: startX - dir * setBack,
                                    y: baseY + side * (row * 9 + .random(in: -3...3)))
            bird.zPosition = 2
            bird.run(.repeatForever(.animate(with: AtmosphericParticleTextures.birdFrames,
                                             timePerFrame: .random(in: 0.14...0.19))))
            let move = SKAction.moveBy(x: dir * (travel + setBack),
                                       y: .random(in: 12...36),
                                       duration: baseDuration + .random(in: -0.35...0.35))
            bird.run(.sequence([.wait(forDuration: .random(in: 0...0.4)),
                                move,
                                .removeFromParent()]))
            addChild(bird)
        }
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
    /// blurred-bright" near layer — blur is baked, never live) and a bright
    /// leading bead so the closest drops read as heavy falling water.
    static let nearStreak = streak(width: 3.5, height: 34, halo: 2, head: true)
    /// Depth 3 rain streak: 1.5×42 pt needle for the very-fast faint layer.
    static let fastStreak = streak(width: 1.5, height: 42, halo: 0)
    /// Soft round dot (morning motes, soft event motes).
    static let dot = radialDot(diameter: 12)
    /// A real six-armed dendritic snow crystal — a soft glow core with six
    /// branched arms — instead of a plain blob. On something this small the
    /// crystalline arms read as an actual snowflake when it rotates, not a
    /// speck. Rendered once; the per-flake rotation makes each land differently.
    static let flake = crystalFlake(diameter: 22)
    /// A four-point star sparkle: a bright soft core with thin tapering
    /// diffraction spikes (the way a real star reads through a lens). Used by
    /// the night twinkles and the brighter event sparkles.
    static let sparkleStar = starSparkle(diameter: 22)
    /// Large soft blob scaled up ~3× for the drifting mist band.
    static let mist = mistBlob(diameter: 96)
    /// A wide, warm, extra-soft bloom — the low sun's glow at sunset. No hard
    /// core; tinted warm gold by the node.
    static let sunGlow = cloudBlob(diameter: 220)
    /// A rain splash: the thin expanding ring PLUS a small three-tick crown of
    /// rebounding droplets, so an impact reads as water hitting a surface, not
    /// just a widening circle.
    static let splashRing = splashCrown(size: CGSize(width: 16, height: 6))
    /// Shooting-star streak: 90×3 pt horizontal capsule, tail (−x) fading to
    /// nothing, bright head at +x. The stretch is baked; flight is one moveBy.
    static let shootingStreak = horizontalStreak(length: 90, thickness: 3)
    /// The sunset bird's two wing frames (up / down): flapping is a plain
    /// two-frame SKAction texture swap, never live drawing.
    static let birdFrames = [bird(wingsUp: true), bird(wingsUp: false)]
    /// Very large extra-soft disc for the day clouds — the mist blob's
    /// falloff is too tight once scaled to screen width.
    static let cloud = cloudBlob(diameter: 180)
    /// The moon's soft atmospheric halo (additive, tinted pale ice).
    static let moonHalo = cloudBlob(diameter: 150)
    /// A tall soft light wedge for the morning sun shafts: bright spine
    /// fading to nothing sideways, and fading out toward both ends.
    static let lightShaft = shaft(width: 90, height: 300)

    private static func renderer(_ size: CGSize) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 2   // tinted motes this small gain nothing from @3x
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    /// Vertical capsule with alpha fading at both tips; `halo` adds a wider
    /// soft capsule behind it for the near layer's baked glow. `head` adds a
    /// small bright bead at the LEADING (bottom) tip — a real drop is heaviest
    /// and brightest at its front, so the near layer reads as falling water,
    /// not a uniform line.
    private static func streak(width: CGFloat, height: CGFloat,
                               halo: CGFloat, head: Bool = false) -> SKTexture {
        let pad = halo + 2
        let canvas = CGSize(width: width + pad * 2, height: height + pad * 2)
        let image = renderer(canvas).image { ctx in
            let cg = ctx.cgContext
            if halo > 0 {
                let haloRect = CGRect(x: 1, y: 1,
                                      width: width + halo * 2, height: height + halo * 2)
                fillCapsule(cg, rect: haloRect, alphas: [0, 0.35, 0.35, 0])
            }
            let body = CGRect(x: pad, y: pad, width: width, height: height)
            // Bottom-weighted body: fades in slowly at the top, stays bright at
            // the leading tip so the head reads as heavier than the tail.
            fillCapsule(cg, rect: body, alphas: head ? [0, 0.5, 1, 0.9] : [0, 1, 1, 0])
            if head {
                // A bright rounded bead at the leading (bottom) tip.
                let r = width * 1.15
                drawRadialFade(cg, center: CGPoint(x: body.midX, y: body.maxY - width * 0.4),
                               radius: r, peak: 1)
            }
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

    private static func radialDot(diameter: CGFloat) -> SKTexture {
        let canvas = CGSize(width: diameter, height: diameter)
        let image = renderer(canvas).image { ctx in
            drawRadialFade(ctx.cgContext,
                           center: CGPoint(x: diameter / 2, y: diameter / 2),
                           radius: diameter / 2, peak: 1)
        }
        return SKTexture(image: image)
    }

    /// A six-armed dendritic snow crystal: a faint round glow so the shape
    /// never looks like a hard icon at small size, then six arms at 60° each
    /// with a symmetric pair of side-branches — the classic stellar-dendrite
    /// silhouette. White, thin, round-capped; tinted by the emitter.
    private static func crystalFlake(diameter: CGFloat) -> SKTexture {
        let image = renderer(CGSize(width: diameter, height: diameter)).image { ctx in
            let cg = ctx.cgContext
            let c = CGPoint(x: diameter / 2, y: diameter / 2)
            // Soft core glow — keeps the crystal from reading as a hard glyph.
            drawRadialFade(cg, center: c, radius: diameter * 0.30, peak: 0.65)

            cg.setStrokeColor(UIColor.white.cgColor)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            let arm = diameter * 0.44          // arm length from centre
            let branch = diameter * 0.15       // side-branch length
            for i in 0..<6 {
                let a = CGFloat(i) * .pi / 3    // 60° spacing
                let dir = CGVector(dx: cos(a), dy: sin(a))
                let tip = CGPoint(x: c.x + dir.dx * arm, y: c.y + dir.dy * arm)
                cg.setLineWidth(1.1)
                cg.move(to: c)
                cg.addLine(to: tip)
                cg.strokePath()
                // Two symmetric side-branches part-way along the arm.
                let mid = CGPoint(x: c.x + dir.dx * arm * 0.55,
                                  y: c.y + dir.dy * arm * 0.55)
                for sign in [CGFloat(1), -1] {
                    let b = a + sign * (.pi / 3)
                    cg.setLineWidth(0.9)
                    cg.move(to: mid)
                    cg.addLine(to: CGPoint(x: mid.x + cos(b) * branch,
                                           y: mid.y + sin(b) * branch))
                    cg.strokePath()
                }
            }
        }
        return SKTexture(image: image)
    }

    /// A four-point star: a bright soft core plus four thin diffraction spikes
    /// that taper to nothing — how a real point of light reads through optics.
    /// White; the emitter/sprite tints it (cool ice for stars, gold for events).
    private static func starSparkle(diameter: CGFloat) -> SKTexture {
        let image = renderer(CGSize(width: diameter, height: diameter)).image { ctx in
            let cg = ctx.cgContext
            let c = CGPoint(x: diameter / 2, y: diameter / 2)
            // Bright soft core.
            drawRadialFade(cg, center: c, radius: diameter * 0.22, peak: 1)
            // Four spikes (up/down/left/right), each a thin triangle tapering
            // from the core to a fine point — the diffraction cross.
            let reach = diameter * 0.48
            let halfW = diameter * 0.06
            for i in 0..<4 {
                let a = CGFloat(i) * .pi / 2
                let dir = CGVector(dx: cos(a), dy: sin(a))
                let perp = CGVector(dx: -dir.dy, dy: dir.dx)
                let tip = CGPoint(x: c.x + dir.dx * reach, y: c.y + dir.dy * reach)
                let baseL = CGPoint(x: c.x + perp.dx * halfW, y: c.y + perp.dy * halfW)
                let baseR = CGPoint(x: c.x - perp.dx * halfW, y: c.y - perp.dy * halfW)
                cg.setFillColor(UIColor.white.withAlphaComponent(0.9).cgColor)
                cg.move(to: baseL)
                cg.addLine(to: tip)
                cg.addLine(to: baseR)
                cg.closePath()
                cg.fillPath()
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

    /// Horizontal capsule whose alpha ramps from nothing at the tail to full
    /// at the head — the pre-stretched shooting-star body.
    private static func horizontalStreak(length: CGFloat, thickness: CGFloat) -> SKTexture {
        let canvas = CGSize(width: length + 2, height: thickness + 2)
        let image = renderer(canvas).image { ctx in
            let cg = ctx.cgContext
            let rect = CGRect(x: 1, y: 1, width: length, height: thickness)
            cg.addPath(UIBezierPath(roundedRect: rect,
                                    cornerRadius: thickness / 2).cgPath)
            cg.clip()
            let alphas: [CGFloat] = [0, 0.2, 0.75, 1]
            let colors = alphas.map { UIColor.white.withAlphaComponent($0).cgColor }
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors as CFArray,
                                         locations: [0, 0.55, 0.9, 1]) {
                cg.drawLinearGradient(gradient,
                                      start: CGPoint(x: rect.minX, y: rect.midY),
                                      end: CGPoint(x: rect.maxX, y: rect.midY),
                                      options: [])
            }
        }
        return SKTexture(image: image)
    }

    /// One wing frame of the bird silhouette: a 16×10 pt stroked chevron —
    /// wings raised (deep V, tips high) or on the downstroke (shallow,
    /// tips low). White, tinted dark by the node like every other texture.
    private static func bird(wingsUp: Bool) -> SKTexture {
        let canvas = CGSize(width: 16, height: 10)
        let image = renderer(canvas).image { ctx in
            let cg = ctx.cgContext
            cg.setStrokeColor(UIColor.white.cgColor)
            cg.setLineWidth(1.8)
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            let bodyY: CGFloat = wingsUp ? 7.5 : 4.5
            let tipY: CGFloat = wingsUp ? 2.5 : 6.5
            cg.move(to: CGPoint(x: 2, y: tipY))
            cg.addLine(to: CGPoint(x: 8, y: bodyY))
            cg.addLine(to: CGPoint(x: 14, y: tipY))
            cg.strokePath()
        }
        return SKTexture(image: image)
    }

    /// A soft light shaft: horizontal falloff from a bright spine to nothing
    /// at the sides, multiplied by a vertical fade at both ends — a beam of
    /// light with no edges anywhere. White; tinted warm gold by the sprite.
    private static func shaft(width: CGFloat, height: CGFloat) -> SKTexture {
        let image = renderer(CGSize(width: width, height: height)).image { ctx in
            let cg = ctx.cgContext
            let cs = CGColorSpaceCreateDeviceRGB()
            // Horizontal profile: bright spine → transparent sides.
            let across = [UIColor.white.withAlphaComponent(0).cgColor,
                          UIColor.white.withAlphaComponent(0.9).cgColor,
                          UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: cs, colors: across,
                                  locations: [0, 0.5, 1]) {
                cg.drawLinearGradient(g, start: CGPoint(x: 0, y: height / 2),
                                      end: CGPoint(x: width, y: height / 2), options: [])
            }
            // Vertical envelope: destination-in fade at both ends.
            cg.setBlendMode(.destinationIn)
            let along = [UIColor.white.withAlphaComponent(0).cgColor,
                         UIColor.white.withAlphaComponent(1).cgColor,
                         UIColor.white.withAlphaComponent(1).cgColor,
                         UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: cs, colors: along,
                                  locations: [0, 0.25, 0.75, 1]) {
                cg.drawLinearGradient(g, start: CGPoint(x: width / 2, y: 0),
                                      end: CGPoint(x: width / 2, y: height), options: [])
            }
        }
        return SKTexture(image: image)
    }

    /// Softer-shouldered radial fade than `mistBlob` — at screen-width scale
    /// the cloud must have no visible core at all.
    private static func cloudBlob(diameter: CGFloat) -> SKTexture {
        let image = renderer(CGSize(width: diameter, height: diameter)).image { ctx in
            let cg = ctx.cgContext
            let center = CGPoint(x: diameter / 2, y: diameter / 2)
            let colors = [UIColor.white.withAlphaComponent(0.85).cgColor,
                          UIColor.white.withAlphaComponent(0.40).cgColor,
                          UIColor.white.withAlphaComponent(0).cgColor]
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: colors as CFArray,
                                            locations: [0, 0.5, 1]) else { return }
            cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                  endCenter: center, endRadius: diameter / 2,
                                  options: [])
        }
        return SKTexture(image: image)
    }

    /// A splash: the thin expanding ellipse ring plus a small three-tick crown
    /// of rebounding droplets above it, so an impact reads as water striking a
    /// surface (a crown), not merely a widening circle. All white; the emitter
    /// tints and expands it.
    private static func splashCrown(size: CGSize) -> SKTexture {
        let tick: CGFloat = 4                     // droplet rebound height
        let canvas = CGSize(width: size.width + 4, height: size.height + tick + 4)
        let image = renderer(canvas).image { ctx in
            let cg = ctx.cgContext
            let ringRect = CGRect(x: 2, y: tick + 2, width: size.width, height: size.height)
            cg.setStrokeColor(UIColor.white.cgColor)
            cg.setLineCap(.round)
            // The ring.
            cg.setLineWidth(1)
            cg.strokeEllipse(in: ringRect)
            // Three rebound ticks rising from the ring's crown.
            cg.setLineWidth(1.1)
            for fx in [CGFloat(0.28), 0.5, 0.72] {
                let x = ringRect.minX + ringRect.width * fx
                let jitter = fx == 0.5 ? tick : tick * 0.7
                cg.move(to: CGPoint(x: x, y: ringRect.minY))
                cg.addLine(to: CGPoint(x: x, y: ringRect.minY - jitter))
                cg.strokePath()
            }
        }
        return SKTexture(image: image)
    }
}

// MARK: - Static hint for fixed previews (no live scenes per card)

/// What the settings carousel cards show instead of a scene: a handful of
/// pre-baked marks drawn once in a Canvas — the mood's signature at zero
/// ongoing cost. Positions are deterministic (no RNG at render), in unit
/// coordinates so the hint scales with any preview. The day mood
/// deliberately renders nothing: its live effect is designed to be barely
/// perceptible, and any visible thumbnail mark would overstate it.
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
    private static let starMarks: [(CGFloat, CGFloat, CGFloat)] = [
        (0.10, 0.15, 0.70), (0.22, 0.55, 0.35), (0.30, 0.30, 0.50),
        (0.42, 0.12, 0.40), (0.50, 0.68, 0.30), (0.58, 0.38, 0.65),
        (0.70, 0.20, 0.45), (0.78, 0.60, 0.35), (0.88, 0.35, 0.55),
        (0.94, 0.10, 0.40),
    ]
    private static let moteMarks: [(CGFloat, CGFloat, CGFloat)] = [
        (0.15, 0.70, 0.30), (0.28, 0.40, 0.22), (0.45, 0.62, 0.35),
        (0.60, 0.28, 0.25), (0.75, 0.55, 0.32), (0.88, 0.36, 0.22),
    ]
    /// (x, y) chevron centers — the flock, mid-crossing, in the upper third.
    private static let birdMarks: [(CGFloat, CGFloat)] = [
        (0.32, 0.24), (0.44, 0.16), (0.56, 0.26),
    ]

    var body: some View {
        switch mood {
        case .rain:    marks(kind: .rain)
        case .winter:  marks(kind: .snow)
        case .event:   marks(kind: .spark)
        case .night:   marks(kind: .stars)
        case .morning: marks(kind: .motes)
        case .sunset:  marks(kind: .birds)
        case .day:     EmptyView()   // honest — see the type comment
        }
    }

    private enum Kind { case rain, snow, spark, stars, motes, birds }

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
                // Tiny six-armed crystals — the same silhouette the live flakes
                // now carry, so the thumbnail matches what actually falls.
                let color = Color(red: 0.470, green: 0.580, blue: 0.680)
                for (x, y, alpha) in Self.snowMarks {
                    let c = CGPoint(x: x * size.width, y: y * size.height)
                    let r: CGFloat = alpha > 0.5 ? 3.0 : 2.2
                    var path = Path()
                    for i in 0..<6 {
                        let a = CGFloat(i) * .pi / 3
                        path.move(to: c)
                        path.addLine(to: CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r))
                    }
                    context.stroke(path, with: .color(color.opacity(alpha)),
                                   style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
                }
            case .spark:
                let gold = Color(red: 0.914, green: 0.757, blue: 0.369)
                for (x, y, alpha) in Self.sparkMarks {
                    let r: CGFloat = alpha > 0.45 ? 1.9 : 1.3
                    let rect = CGRect(x: x * size.width - r, y: y * size.height - r,
                                      width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(gold.opacity(alpha)))
                }
            case .stars:
                // The moon first — matching the live scene's upper-right seat.
                let moon = CGPoint(x: size.width * 0.80, y: size.height * 0.22)
                let mr: CGFloat = max(3.5, size.width * 0.035)
                context.fill(Path(ellipseIn: CGRect(x: moon.x - mr, y: moon.y - mr,
                                                    width: mr * 2, height: mr * 2)),
                             with: .color(Color(red: 0.93, green: 0.94, blue: 0.96).opacity(0.75)))
                // Pinpoint stars; the brighter ones get a tiny four-point
                // glint, matching the live field's diffraction spikes.
                for (x, y, alpha) in Self.starMarks {
                    let c = CGPoint(x: x * size.width, y: y * size.height)
                    let r: CGFloat = alpha > 0.5 ? 1.1 : 0.8
                    context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r,
                                                        width: r * 2, height: r * 2)),
                                 with: .color(.white.opacity(alpha)))
                    if alpha > 0.5 {
                        let s = r * 2.6
                        var cross = Path()
                        for a in stride(from: 0, to: CGFloat.pi * 2, by: .pi / 2) {
                            cross.move(to: c)
                            cross.addLine(to: CGPoint(x: c.x + cos(a) * s, y: c.y + sin(a) * s))
                        }
                        context.stroke(cross, with: .color(.white.opacity(alpha * 0.6)),
                                       style: StrokeStyle(lineWidth: 0.5, lineCap: .round))
                    }
                }
            case .motes:
                let gold = Color(red: 0.973, green: 0.831, blue: 0.576)
                for (x, y, alpha) in Self.moteMarks {
                    let r: CGFloat = alpha > 0.28 ? 2.1 : 1.6
                    let rect = CGRect(x: x * size.width - r, y: y * size.height - r,
                                      width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(gold.opacity(alpha)))
                }
            case .birds:
                // A warm low sun glow — the sunset's continuous signature —
                // with the flock's three chevrons crossing above it.
                let sun = CGPoint(x: size.width * 0.62, y: size.height * 1.02)
                context.fill(
                    Path(ellipseIn: CGRect(x: sun.x - size.width * 0.5,
                                           y: sun.y - size.width * 0.5,
                                           width: size.width, height: size.width)),
                    with: .radialGradient(
                        Gradient(colors: [Color(red: 1.0, green: 0.66, blue: 0.34).opacity(0.5),
                                          .clear]),
                        center: sun, startRadius: 0, endRadius: size.width * 0.5))
                let ink = Color(red: 0.28, green: 0.17, blue: 0.14)
                let span = max(7, size.width * 0.06)
                let rise = span * 0.35
                for (x, y) in Self.birdMarks {
                    let c = CGPoint(x: x * size.width, y: y * size.height)
                    var path = Path()
                    path.move(to: CGPoint(x: c.x - span / 2, y: c.y - rise))
                    path.addLine(to: c)
                    path.addLine(to: CGPoint(x: c.x + span / 2, y: c.y - rise))
                    context.stroke(path, with: .color(ink.opacity(0.5)),
                                   style: StrokeStyle(lineWidth: 1.2, lineCap: .round,
                                                      lineJoin: .round))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
