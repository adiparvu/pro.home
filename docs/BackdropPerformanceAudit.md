# Backdrop Performance Audit — `AppBackdropEffects.swift`

Date: 2026-08-02
Scope: `apps/ios/Sources/Components/AppBackdropEffects.swift` (2,149 lines before edits, 2,184 after)
Context read: `AppMood.swift`, `AppBackdrop.swift`, `AppBackgroundStyle.swift`, `Services/AppLifecycle.swift`, `Components/WeatherStage/` (read-only)

---

## 0. The two findings that frame everything else

### 0.1 This layer is currently DORMANT — its runtime cost today is zero

`AppBackdropEffectsLayer`, `AppBackdropEffectsHint`, `NightSkyStaticLayer`, and
`AtmosphericEffectsPolicy` are referenced by **no other file in the app**. The
living mood backdrop was retired (user-decreed, 2026-07-19 — see the header of
`AppBackdrop.swift`); `appBackground` now renders `AppBackgroundView`, whose
modes are gradient / photo (a stored `liveSky` preference migrates to gradient
at init). Nothing mounts the SpriteKit atmosphere layer, so nothing in this
file executes in the shipped app except its static-let declarations if some
future code path touches them (they are all lazy).

Every optimization below is therefore insurance for the day the layer returns,
plus honest bookkeeping — not a fix for a live regression.

### 0.2 The effect set named in the task brief lives elsewhere

"Rain droplets with gyroscope, branched lightning, blizzard, volumetric fog,
rainbow, sand, fireflies, cloud shadows" describes
`Sources/Components/WeatherStage/` (`WeatherStageView.swift`, `MotionTilt.swift`,
`SkyShaders.metal`, `WeatherState.swift`) — the procedural Metal "live sky",
itself also dormant (the `liveSky` mode is migrated away at init). That
directory was out of scope for this task's hard constraints and was **not
modified**. It has its own `TimelineView(.animation)` driver
(`WeatherStageView.swift:268`, already coarsened to 10 Hz under Low Power Mode)
and deserves its own audit before it is ever re-enabled.

What `AppBackdropEffects.swift` actually contains: the seven SpriteKit
atmosphere scenes of the retired mood backdrop — rain (wind gusts + flash
lightning), snow, night stars (moon, wisps, shooting stars), morning motes,
day clouds, sunset glow (once-a-day bird flock), event sparkle — plus the
static night-sky fallback and the settings-carousel hint canvases.

---

## 1. Inventory — effect → drivers → cost class

All live scenes render inside **one** `SpriteView(preferredFramesPerSecond: 60,
options: [.allowsTransparency])` — SpriteKit's own CADisplayLink at 60 fps,
deliberately below ProMotion's 120 so SwiftUI keeps the UI thread free (the
rationale is documented in the file header). There are **no `TimelineView`s and
no `Timer`s anywhere in the file**; the only SwiftUI-side drivers are sleeping
`.task(id:)` schedulers that are cancelled while the scene is not `.active`.

| Effect (mood) | Scene / view | Drivers | Steady-state budget | Cost class |
|---|---|---|---|---|
| Rain (also night+rain) | `RainScene` + `LightningLayer` | SpriteView 60 fps; `update()` = 4 property writes/frame (wind gusts); one task sleeping 25–70 s (lightning) | ≈ 45 + 44 + 14 streaks + ~4 splashes + ~5 mist ≈ 112 particles | Medium — largest particle count; 3 depth layers + splash + mist over a transparent SpriteView |
| Snow (winter) | `SnowScene` | SpriteView 60 fps; `update()` = 2 writes/frame (opposing gusts) | 54 + 28 = 82 flakes | Medium-low |
| Night stars | `NightStarsScene` | SpriteView 60 fps; 20 `repeatForever` alpha tweens (twinkles); moon-halo alpha tween; one task sleeping 60–180 s (shooting star) | 1 baked field sprite + 20 twinkles + moon disc + **additive** halo + 4 wisps + ≤1 streak | Medium-low CPU; ~5–6 MB @2x screen-sized baked texture while mounted (documented); one additive blend layer |
| Morning motes | `MorningMotesScene` | SpriteView 60 fps; 2 shaft alpha tweens; `update()` = prewarm-only guard | 25 motes + 2 static **additive** shaft sprites | Low |
| Day clouds | `DayCloudsScene` | SpriteView 60 fps; `update()` = prewarm-only guard | 3 near + 2 far sprites (minutes-long lifetimes) | Low count, but each cloud is a ~340–595 pt textured quad → overdraw, not particle count, is the cost |
| Sunset glow | `SunsetGlowScene` | SpriteView 60 fps; sun-glow alpha tween; one-shot flock (7–9 sprites, ~7 s, once/day) | 3 drift blobs + 1 **additive** screen-width sun-glow quad | Low-medium (large additive quad) |
| Event sparkle | `EventSparkleScene` | SpriteView 60 fps for ≤ 2.7 s, then the host removes the SpriteView entirely | 30 motes + 12 additive sparks, one-shot, once/day | Transient |
| Lightning (rain sub-layer) | `LightningLayer` (SwiftUI) | One task sleeping 25–70 s; two `RadialGradient`s animated via `.opacity` only | 2 gradient layers at opacity 0 between strikes | Negligible between strikes (CA skips fully transparent layers); brief full-screen blend during the ~1.5 s strike |
| Night fallback (gates closed) | `NightSkyStaticLayer` | None — one `Canvas` pass, no animation, no schedulers | 80 dots + spikes + baked moon image | One-shot draw per size/trait change |
| Settings hints | `AppBackdropEffectsHint` | None — one `Canvas` pass per card | ≤ 10 marks per card | One-shot draw |

### Compositor-expensive constructs (all deliberate, none live-blurred)

- **No live blur anywhere.** Every "soft" element (streak halo, mist, clouds,
  wisps, sun glow, moon halo, light shafts) is a pre-baked radial/linear-fade
  texture rendered once with `UIGraphicsImageRenderer` and cached in static
  lets — the file's own "blur is baked, never live" rule holds throughout.
- **Additive blending** (an extra blend pass, not an offscreen pass): event
  sparks, moon halo, morning shafts, sunset sun glow.
- **Transparency**: the whole SpriteView runs with `.allowsTransparency` —
  inherent to compositing atmosphere over the palette gradient.
- **No `ignoresSafeArea` layers, no shadows, no `.blur`, no opacity stacks**
  in this file; the two `LightningLayer` gradients sit at opacity 0 between
  strikes, which Core Animation skips.

### Work-while-invisible / backgrounded / Reduce Motion — the existing contract

Already implemented (the file's "energy contract", verified line by line):

| State | What runs |
|---|---|
| Effects toggle off / **Reduce Motion** / Low Power Mode | Nothing is mounted — not even an empty scene. Night gets the static `NightSkyStaticLayer` Canvas (zero drivers), so the accessibility variant is a designed static sky, not a missing feature. |
| Gates pass, `scenePhase != .active` | SpriteView mounted but `isPaused` (SKView render loop idle, SKActions frozen); every scheduler task is cancelled via `.task(id:)` re-keying — no timers exist while paused. |
| Backdrop leaves the screen | View unmounted, scene and its textures released. |
| Low Power flips while visible | `NSProcessInfoPowerStateDidChange` → observable policy → live unmount. |

The pause signal is `@Environment(\.scenePhase)`, not
`AppLifecycle.isBackgrounded`. That is the right choice, not an omission:
`AppLifecycle.isBackgrounded` (Services/AppLifecycle.swift) is a non-observable
UIKit poll built for realtime services, deliberately `false` during `.inactive`;
`scenePhase` is observable, per-scene, and pauses **earlier** (already on
`.inactive` — app switcher, system sheets). Rewiring to `AppLifecycle` would
pause *less* aggressively. No change made.

**Reduce Motion is fully respected** — it is one of the three mount gates
(`allowsMounting(reduceMotion:)`), and the two Canvas views are static by
construction. No violations found; nothing to fix under the accessibility law.

### Per-tick allocation audit

No per-frame allocations exist in the live path: particles are SpriteKit
emitters (native pooling), all textures are process-lifetime static lets,
scene `update()` bodies are 0–4 property writes plus two `sin` calls. The only
repeated re-derivation found was `NightSkyStaticLayer` rebuilding its 80 star
specs from the seeded RNG on every Canvas redraw — fixed below.

---

## 2. What was changed (and why it cannot change the look)

Two edits, both in `AppBackdropEffects.swift`, each carrying an in-code comment
stating the removed cost.

### 2.1 `AppBackdropEffectsLayer` — weather-tone observation narrowed to `.night`

Before: the body read `AppMoodEngine.shared.weatherTone` for **every** mood,
registering an Observation dependency — so any weather-cache update (a fresh
Apple Weather fetch, the reactive toggle) re-evaluated the body of every
mounted backdrop, including moods whose effect never looks at the tone.

After: `let tone = mood == .night ? AppMoodEngine.shared.weatherTone : nil`.

Cost removed: needless body re-evaluations (view invalidation, the
CLAUDE.md rule) on weather updates for six of the seven moods.
Why the look cannot change: `AtmosphericEffectsPolicy.effect(for:weatherTone:)`
reads the tone **only** in its `.night` case (rain-after-dark swaps stars for
rain); every other case ignores the parameter, so passing `nil` there is
identical by construction. For `.night` the read — and the live re-resolution —
is exactly as before.

### 2.2 `NightSkyStaticLayer` — star-field specs baked once per process

Before: the Canvas closure re-ran the seeded `SplitMix64` RNG (4 draws × 80
stars = 320 draws) and re-derived every position/size/alpha/tint on **every**
redraw — each size change and trait pass repeated work whose result is a
constant.

After: a `private static let stars: [StaticStar]` derives the 80 specs once;
the Canvas iterates the cached array.

Cost removed: 320 RNG draws + 80 spec constructions per redraw of the
accessibility/Low-Power night sky.
Why the look cannot change: the seed (`0x5EED_57A2_F1E1D`), the per-star draw
order (x, y, size, alpha), the value ranges, the index-based tint rule
(`i % 7` warm / `i % 5` cool), the y-flip, and the spike threshold (`r > 1.1`)
are all preserved verbatim — a deterministic RNG with the same seed and the
same call sequence produces the same numbers, so the rendered field is
bit-identical to the loop it replaces.

---

## 3. Considered and deliberately NOT changed

Per the task rule — when identical visuals could not be proven, no edit:

1. **Conditionally unmounting the `LightningLayer` gradients between strikes.**
   The two `RadialGradient`s sit at opacity 0 for 25–70 s at a time. But the
   fades are driven by `withAnimation { flash = 0 }` — the *state* hits 0
   instantly while the *presentation* animates, so an `if flash > 0` wrapper
   would remove the view the moment the fade begins, visibly clipping the
   flash decay. Core Animation already skips fully transparent layers, so the
   steady-state cost is effectively zero. Left as is.
2. **`.drawingGroup()` anywhere.** No qualifying subtree exists: nothing
   SwiftUI-side re-renders per tick (SpriteKit owns the per-frame work), and
   the two Canvas views are already single rasterized layers — adding
   `.drawingGroup()` would introduce an offscreen pass, the opposite of the
   goal.
3. **Deferring scene construction while mounted-but-paused.** `mountIfNeeded`
   builds the scene even when `scenePhase != .active` (except the sparkle,
   which must not spend its daily claim while invisible). This is the file's
   documented state table ("SpriteView mounted but PAUSED"); construction is
   one-time, prewarm correctly waits for the first *unpaused* frame, and
   deferral would only move the cost to activation. Left as designed.
4. **Coarsening `preferredFramesPerSecond` when inactive.** Redundant — the
   SpriteView is fully paused, which is stronger than any coarsening.
5. **Rewiring the pause to `AppLifecycle.isBackgrounded`.** Would pause later
   (only at `.background`), not earlier. `scenePhase` is the stronger signal;
   see §1.

---

## 4. Left for on-device Instruments verification

These cannot be proven from source and are worth 10 minutes on hardware
**before the layer is ever re-mounted**:

1. **`SpriteView(isPaused:)` truly idles the CADisplayLink** on the current
   SDK. The file asserts it; verify no `SKView`/`CADisplayLink` samples appear
   in Time Profiler while the app is inactive with a rain backdrop mounted.
2. **Rain steady-state GPU cost** (the heaviest scene: ~112 particles, three
   depth layers, splash + mist, full-screen transparent SpriteView) on a
   120 Hz device — confirm the SwiftUI UI still tracks 120 fps while the
   SpriteView runs at 60.
3. **Zero-opacity gradient skip** — with the Core Animation template, confirm
   the two `LightningLayer` gradients produce no render cost between strikes
   and no offscreen pass during one (color offscreen-rendered = nothing new).
4. **Night-scene memory** — the ~5–6 MB @2x baked star-field texture plus the
   moon sprites: watch the allocations delta on mount/unmount and on rotation
   (`bakeFieldIfNeeded` re-bakes on real size changes — a main-thread
   `UIGraphicsImageRenderer` pass; check rotation stays smooth).
5. **Additive-blend layers** (sun glow at screen width, moon halo, shafts,
   sparks) — GPU report while sunset/night/morning are mounted; additive
   quads at this size are the likeliest hidden cost on older devices.
6. **The WeatherStage** (`Components/WeatherStage/`) — out of scope here, has
   its own `TimelineView(.animation)`; audit separately before re-enabling
   `liveSky`.

---

## 5. 10-minute on-device profiling checklist

Device: a ProMotion iPhone on battery (not charging), Release build.
Precondition for §5.2–5.4: temporarily mount `AppBackdropEffectsLayer(mood:)`
over `appBackground` on one screen (it is dormant today), or profile whichever
backdrop system is actually live.

**Minutes 0–2 — baseline.**
Instruments → Time Profiler + Core Animation FPS + GPU (one document).
Record 30 s of the dashboard with the static gradient backdrop. Note: main
thread %, FPS (should pin at 120 on scroll), GPU utilization.

**Minutes 2–5 — heaviest scene (rain).**
Pin the rain mood; record 60 s idle + 30 s scrolling.
- Time Profiler: `SKRenderer`/`SKView` should sit in a worker context at
  ~60 Hz; SwiftUI's render loop must stay at 120 on scroll (no long main-actor
  frames from the backdrop).
- Core Animation FPS: no drops below 110 while scrolling over the rain.
- GPU: note utilization delta vs baseline; the transparent SpriteView +
  three streak layers is the number to write down for the budget.
- Trigger a lightning strike wait (or temporarily shorten the 25–70 s range
  locally) and confirm no frame spike over the two-pulse flash.

**Minutes 5–7 — pause matrix.**
With rain mounted: swipe to the app switcher (scene `.inactive`), then home
(`.background`). In Time Profiler both should show the SpriteKit track going
silent within a frame; zero timer wakes (the scheduler tasks are cancelled).
Return to foreground: rain resumes prewarmed, no fill-in from an empty sky.

**Minutes 7–9 — night + gates.**
Pin night: check memory delta on mount (~5–6 MB texture), rotate twice (re-bake
stays jank-free), leave it 3 min in the background and confirm zero CPU.
Then flip Low Power Mode ON while watching: the SpriteView must unmount live
and `NightSkyStaticLayer` take its place with no further samples. Repeat with
Settings → Accessibility → Reduce Motion.

**Minutes 9–10 — write the numbers down.**
Update this doc's §4 items with measured values (GPU % per scene, mount memory,
resume latency). Anything above ~10% GPU over baseline for a backdrop is a
budget conversation, not a silent ship.

---

## 6. Balance results

Post-edit structural check over the whole file (comments/strings stripped):
`{ }` 236/236 · `( )` 983/983 · `[ ]` 99/99 — all balanced. No Swift
toolchain exists in this environment, so the compile gate runs with the next
device/CI build; both edits are local, additive, and type-simple (one
let-binding split, one static-let extraction of an existing loop).

---

# WeatherStage (the live layer) — `Sources/Components/WeatherStage/`

Date: 2026-08-02 (same day, follow-up to §0.2)
Scope: `WeatherStageView.swift` (333 → 356 lines), `WeatherState.swift` (316),
`MotionTilt.swift` (71), `SkyShaders.metal` (637)
Mount path read (not modified): `AppBackdrop.swift`, `AppBackgroundStyle.swift`

## 7. Status — the living implementation, currently unmounted

This directory IS the implementation of the effect set the briefs describe —
gyroscope lens droplets, wind shear, branching lightning, blizzard,
volumetric-feel fog, the partial after-rain rainbow, sandstorm, fireflies,
cloud shadows. Architecturally it is **one full-screen Metal fragment pass**
(`weatherSky`, a SwiftUI `colorEffect`): there are no per-effect views, no
CPU particles, no textures — every effect is hash-derived per pixel and
branch-gated on its own intensity uniform.

Mount status verified end to end: the only construction site is
`AppBackgroundView` (`AppBackgroundStyle.swift:241`), reachable only in
`.liveSky` mode; `BackgroundStyle.init` migrates a stored `liveSky` to
`.gradient` (user-decreed, IMG_8767) and no UI sets `.liveSky` back
(`BackgroundSettingsView` renders `.liveSky` with the gradient section). Both
singletons (`WeatherStageEngine`, `MotionTiltEngine`) are lazy and are touched
only by those unreachable `.liveSky` branches, so **today the whole directory
costs zero at runtime** — no timer, no observer, no shader pass. Everything
below is the audit it "deserves before it is ever re-enabled" (§4.6), plus two
safe fixes so re-enabling inherits no landmines.

## 8. Inventory — drivers, cadences, allocations, compositor

| Driver | Where | Cadence | Work per tick | Gating |
|---|---|---|---|---|
| `TimelineView(.animation)` | `WeatherStageView.swift:280` (was :268 pre-edit) | **Display rate — 120 Hz on ProMotion**; 10 Hz under Low Power (`minimumInterval: 0.1`) | 1 full-screen fragment pass + 16-arg `Shader` packing | `paused: scenePhase != .active` (the b1179 freeze-in-background fix); whole branch absent under Reduce Motion |
| `weatherSky` fragment pass | `SkyShaders.metal:204` | per frame · per pixel | ALU only — zero texture samples, zero buffers | every effect behind its own intensity uniform (coherent branches) |
| Engine refresh `Timer` | `stageAppeared()` | 300 s, tolerance 30 s, ref-counted per mounted stage | one `recompute` (pure param math) | invalidated when the last stage unmounts; NOT scenePhase-gated (see §10.3) |
| Weather-cache observer | engine `init` | event-driven | one `recompute` | lives for process lifetime (singleton) |
| Rainbow fade `Task` | `scheduleRainbowFadeTicks()` | two one-shot sleeps (~210 s, ~212 s) | one `recompute` each | armed only when rain ends under a risen sun |
| `MotionTiltEngine` (CoreMotion) | `MotionTilt.swift` | 30 Hz on the main queue | ~10 flops of low-pass math | acquired only while rain > 0.03 **and now only while `.active`** (§9.2); refuses to start in Low Power; deliberately not `@Observable` — zero invalidation churn |
| Widget sky publish | `publishSkySnapshot()` | on material color change or >15 min staleness | App Group write + `reloadAllTimelines()` | throttled by design |

**Particle counts / per-tick allocations:** none on the CPU. Rain sheets (4),
snow layers (3), blizzard streaks, droplets (2 layers), fireflies (2 layers),
stars, motes are all per-pixel hash fields — no arrays, no `Path`, no
`Gradient`, nothing rebuilt per frame. The only per-frame Swift allocation is
the `Shader` argument packing inherent to the `colorEffect` API.

**Compositor:** one opaque full-screen layer (`Rectangle().fill(.black)` +
`colorEffect`). No blur, no shadows, no opacity stacks, no offscreen pass, no
`drawingGroup`. Overdraw contribution: exactly one backdrop layer.

**Shader cost classes (audit only — the .metal file was not touched):** the
dominant always-on cost is the cloud block — it runs whenever
`cloudiness > 0.02`, and the CLEAR-sky default is 0.18, so even a clear day
pays ~6 fBM evaluations (~120 hashes) per pixel; night adds stars/Milky
Way/moon (cheap); rain adds the 4-sheet field + lens droplets; every other
effect idles at one uniform compare. This is look-bound and belongs to the
device measurements (§11), not to source edits.

**Reduce Motion:** respected by construction — the RM branch mounts no
TimelineView and no gyro, and renders one still frame. Verified that
`time: 0` cannot freeze a lightning strike into the still: the storm flash
gate `hash12(float2(0, 17.3))` evaluates to 0.6302 in float32 (< the 0.93
threshold), so the bolt path is provably closed at t = 0.

## 9. Changes (2 — both `WeatherStageView.swift`)

### 9.1 Reduce Motion still frame renders `engine.toParams` (stale-frame fix)

Before: the RM branch rendered `engine.current(at: .now)`. With no frame
clock, that expression is evaluated only when the `@Observable` engine
mutates — i.e. at the START of each transition, where eased t ≈ 0 returns
≈ `fromParams`, the OLD sky. Every 5-minute recompute re-froze it there, so a
Reduce Motion user sat permanently one transition behind and could miss a
weather change (clear → storm) entirely.

After: the still renders `toParams`, the settled target. Cost removed: none
at render time (same single frame) — this is the accessibility fix the task
class sanctions: a state change lands as an immediate CUT, which is exactly
what Reduce Motion prescribes instead of the 3 s cross-anim, and the still now
always shows the TRUE sky. Why nothing else can change: the non-RM branch is
untouched, and `toParams` is observable, so invalidation still fires on every
recompute.

### 9.2 Gyroscope acquisition gated on `scenePhase == .active`

Before: `syncMotion()` acquired whenever `wantsMotion` flipped true. Rain
arriving via a weather-cache notification while the scene was inactive (app
switcher) started the 30 Hz CoreMotion tap while the TimelineView was paused —
no frame ever read the tilt. That is the same background-motion class as the
b1173 0x8BADF00D watchdog kill the file's own comments document.

After: acquisition requires `.active`; release triggers when either the rain
or the phase goes. Cost removed: a live CoreMotion thread (30 Hz) spinning for
an unrendered, frozen backdrop. Why the look cannot change: while `.active`
the logic is bit-identical, and outside `.active` zero frames render — a
running gyro changed zero pixels. Return to foreground re-syncs through the
existing `onChange(of: scenePhase)` path.

## 10. Considered and deliberately NOT changed (with reasoning)

1. **`.animation` → `.periodic`: NO.** The rule allows it only when the look
   cannot differ. Here the shader visibly animates at display cadence in
   essentially every state — rain/snow streak motion, cloud domain-warp
   morphing, star twinkle, dust motes, fog drift — so a coarser clock is a
   visible frame-rate reduction, precisely the excluded case. The honest
   open question is `minimumInterval: 1/60` on ProMotion (half the fragment
   passes for motion most eyes may not distinguish at this speed); that is a
   look-affecting trade only device numbers can justify — left for §11.
2. **Making the Low Power `minimumInterval` reactive.** It is captured at
   body evaluation, but flipping LPM forces a Control-Center/Settings
   round-trip → `scenePhase` leaves and re-enters `.active` → body
   re-evaluates and picks it up. Observing `NSProcessInfoPowerStateDidChange`
   would add a permanent driver to fix a window that closes itself.
3. **scenePhase-gating the 5-minute engine timer.** It fires at most once per
   300 s while merely inactive; process suspension already silences it in
   background, and a recompute while inactive is pure param math with a
   throttled publish. Gating would add resume choreography to save
   microseconds.
4. **De-duplicating `snapshotColors` inside `publishSkySnapshot`**
   (`snapshotWantsDarkScheme` recomputes it). ≤ 1 evaluation per 15 minutes
   of ~100 flops; inlining the luma threshold would duplicate policy across
   files — divergence risk exceeds the gain.
5. **Caching `wantsDarkGround` for `.liveSky`** (recomputes the CPU gradient
   mirror on every `backdropPrimaryText` read). Only reachable if liveSky
   returns, and the property lives in `AppBackgroundStyle.swift` — out of
   this task's file scope. Flagged for the re-enable train.
6. **Any edit to `SkyShaders.metal`.** Every candidate (octave counts, branch
   floors, the 0.18 clear-sky cloudiness) changes pixels. Audit-only.

## 11. On-device checklist — WeatherStage extension of §5

Precondition: locally allow `.liveSky` again (comment the migration line in
`BackgroundStyle.init` and set the mode) on a ProMotion device, Release build.

**+2 min — per-state GPU ladder.** Pin each preset in turn (clear day,
cloudy, fog, rain, storm, snow, blizzard, sandstorm, night) and write down
GPU % for 30 s each. Expect the cloud block to dominate; rain adds the
4-sheet field + droplets. Anything above the §5 budget line (~10% over the
gradient baseline) is a conversation before re-enable.
**+2 min — the 120 Hz question.** With rain pinned, compare GPU/energy
between stock `.animation` and a local `minimumInterval: 1/60` build, eyes on
the streaks. This is the only place §10.1 can be settled.
**+1 min — pause matrix.** Rain pinned: app switcher, then home. Time
Profiler must show the fragment pass AND `com.apple.CoreMotion.MotionThread`
both silent within a frame (the b1173/b1179 regression pair). Foreground:
rain resumes, droplets react to tilt again.
**+1 min — gyro lifecycle.** Pin rain → unpin to clear while foregrounded:
MotionThread must exit within a frame of the 3 s transition dropping rain
below 0.03. Then pin rain while in the app switcher (via a paired device or
scheduled change): MotionThread must NOT appear until re-activation (§9.2).
**+1 min — Reduce Motion.** RM on, storm pinned: a single still, no frozen
bolt (§8), then change the pin to clear — the still must CUT to the new sky
on the next engine mutation (§9.1), not stay on the storm.
**+1 min — Low Power.** Flip LPM with the stage mounted; after returning to
the app confirm the cadence sits at 10 Hz (Core Animation FPS instrument)
and the gyro refuses to start under rain.
**+1 min — widget publish throttle.** Cross one material sky change (pin
night from day) and confirm exactly one `reloadAllTimelines`, then repeated
small transitions cause none for 15 min.

## 12. Balance results (WeatherStage)

Post-edit structural check, comments/strings stripped:

| File | `{ }` | `( )` | `[ ]` |
|---|---|---|---|
| `WeatherStageView.swift` (edited) | 55/55 | 152/152 | 3/3 |
| `WeatherState.swift` (untouched) | 43/43 | 116/116 | 5/5 |
| `MotionTilt.swift` (untouched) | 10/10 | 15/15 | 1/1 |
| `SkyShaders.metal` (untouched) | 46/46 | 534/534 | 2/2 |

All balanced. No Swift/Metal toolchain exists in this environment; both edits
are local and type-simple (one expression swap inside an existing branch, two
boolean conditions in an existing if/else), so the compile gate runs with the
next device/CI build.
