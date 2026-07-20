# PRVIO Dynamic Island & Live Activities — System Specification

Status: proposed (awaiting phase approval) · Owner: iOS · Targets: iOS 17.1+,
watchOS 10.0+ (Smart Stack mirroring on watchOS 11+), iPadOS 17.1+

---

## 0. Scope & honesty principle

PRVIO already ships a working Live Activities system: five activity types
(Shopping, Delivery, Maintenance, Plant Care, Work Session), a `@MainActor`
orchestrator (`LiveActivityService`), Dynamic Island + Lock Screen views
(`Widgets/LiveActivityViews.swift`), per-kind appearance preferences
(`LiveActivityPrefs`, app-group backed) and a full settings screen. This
specification **redesigns and extends that system to first-party Apple
quality** — it is not a greenfield build.

**Smart home is IN scope — on real rails.** PRVIO ships a working IoT layer
(`IoTService` + `IoTModels`): ESP32 / Raspberry Pi / RS485-Modbus devices,
16 sensor types (temperature, humidity, motion, door/window, CO₂, pressure,
light, noise, current, voltage, power, energy, water, smoke, gas, custom),
alert thresholds and automations. Smart-home Live Activities are therefore
built **on top of the user's actually-configured devices**: a Water-Leak
island exists because the user's leak sensor reported water, a Solar island
because their inverter's power/energy registers are being read. The honesty
law is enforced structurally — an activity kind can only start from a real
sensor event or a real device command; nothing is ever simulated. Two real
gaps are closed as implementation phases: **actuator commands** (garage /
gate / relays — today the IoT layer is read-only) and a **server push path**
so islands update while the phone is locked (today sensor polling runs only
while the app is alive).

**What it WILL cover** (every one backed by a real, live data flow):

| Activity | Driver | Lifecycle |
|---|---|---|
| Delivery (flagship) | Ship24 → `track-webhook` edge fn → `packages` table | hours–days, push-updated |
| Shopping session | `SupplyService.toggleComplete` | minutes–hours |
| Work session timer | task row / watch, system-counted elapsed time | minutes–hours |
| Maintenance task | `TaskService` progress | minutes–hours |
| Plant-watering session | `PlantService.markWatered` | minutes |
| Emergency Mode (new) | existing Emergency Mode feature | until deactivated |
| ARIA long jobs (new, gated) | monthly recap / report generation | seconds–minutes; only if the job outlives foreground |
| IoT alert (new) | `IoTSensor.isAlerting` / event webhooks: water, smoke, gas, motion, door/window, threshold breach | until cleared/acknowledged |
| Energy (new) | power/energy/current/voltage sensors (consumption + solar production) | user-started session or peak alert |
| Cover control (new) | garage / gate actuator commands (Phase E adds actuators to `IoTService`) | seconds–minutes per operation |

Receipt scanning stays **in-app**: OCR completes in seconds while the sheet
is open, so an island state would be dishonest theater. If a future batch
import runs long enough to background, it adopts the `progress` archetype.

---

## 1. Current-state audit (gaps this spec closes)

1. **No shared components.** Each of the five activities hand-builds its
   icon disc, progress row, header and metric text → five slightly different
   layouts, duplicated code, drift.
2. **Token violations.** Views hardcode `.blue`, `.orange`, `.teal`,
   `Color(red:…)` and `.font(.system(size: 10…24))` instead of brand tokens
   and `AppFont` (which is Dynamic-Type-relative). Fixed-size fonts do not
   scale with the user's text size.
3. **Fragmented kind model.** Region gating keys are raw strings
   (`"shopping"`, `"workSession"`); `LiveActivityKind` lives in a Settings
   file and **omits `workSession`**, so the work session can never be
   customized per-kind and its string key silently falls back to globals.
4. **No motion design.** Counters and status flips swap with no
   `contentTransition`; completion has no celebratory state beyond a text
   change; nothing distinguishes success/warning/critical.
5. **No haptics.** `CompleteWorkSessionIntent`/`EndWorkSessionIntent` run in
   the app's process (LiveActivityIntent) and could fire
   `HapticFeedback.success()` — they don't.
6. **Delivery is not "live".** All `Activity.request` calls use
   `pushType: nil`; the Ship24 webhook updates the database, but the island
   only refreshes when the app happens to be foregrounded. ETA is a baked
   string; checkpoints/milestones are never shown.
7. **No staleness contract.** Every update passes `staleDate: nil`, so the
   system can keep showing hours-old state as fresh.
8. **No alerting.** `exception` / `failed_attempt` delivery states render in
   the same calm blue as `in_transit`; ActivityKit `AlertConfiguration` is
   unused.
9. **Accessibility untreated.** No `accessibilityLabel` on island regions,
   color is sometimes the only status signal, fixed font sizes.

---

## 2. UX specification

### 2.1 Content hierarchy (every activity, every state)

One activity answers exactly one question per state:

- **Minimal** (island shared with another app): *which app/what domain* —
  a single SF Symbol in the kind's tint. Nothing else. Never text.
- **Compact** (default island): *what + where it stands* — leading: kind
  symbol (tinted); trailing: ONE datum (count `3/8`, timer, status word,
  milestone glyph). Max ~4 characters trailing on the timer archetypes.
- **Expanded** (long-press): *full picture + act* —
  - Leading: icon + title (kind or subject).
  - Trailing: the key metric (%, timer, ETA).
  - Bottom: progress visualization + one line of context + **at most two
    actions**, both honest (they perform exactly what they say via
    `LiveActivityIntent` or deep link).
- **Lock Screen / banner**: the expanded story in a card; respects the
  user's per-kind "details on Lock Screen" preference (existing
  `MinimalLockRow` fallback stays).
- **StandBy / iPad Lock Screen**: same lock-screen view; verify legibility
  at night-mode red tint (no color-only signals — §11).

### 2.2 Per-activity state walk

**Delivery** (archetype: *milestone journey*)
- States (from Ship24 milestones): `pending → info_received → in_transit →
  out_for_delivery → (delivered | exception | failed_attempt |
  available_for_pickup | expired)`.
- Compact trailing: milestone word when short ("Azi", "3 opriri") else
  milestone glyph; out-for-delivery upgrades tint to `brandWarning` orange.
- Expanded bottom: **4-segment milestone bar** (ordered, filled segments;
  current segment pulses once on update), latest checkpoint line
  ("Sortat în depozit · Cluj"), ETA chip when known. Actions: **Vezi**
  (deep link `prvio://deliveries`) — single action; no fake "Call courier".
- Terminal: `delivered` flips the whole activity to success treatment
  (§9) for 6 s, then dismisses. `exception`/`failed_attempt` use the
  warning treatment + ActivityKit alert so Lock Screen lights up.

**Shopping** (archetype: *progress session*)
- Compact trailing: `5/8` (numericText transition). Expanded: progress bar
  + "5 din 8 produse" + list name; completion state "Gata! 🎉" green.
  Action: **Deschide lista**.

**Work session** (archetype: *timer*)
- Compact trailing: system-counted `Text(startedAt, style: .timer)` (zero
  updates while running — already correct, keep). Expanded actions:
  **Finalizează** (borderedProminent) / **Încheie** — existing intents,
  now with success/light haptics.

**Maintenance** (archetype: *progress session*) — as shopping, wrench
domain, step description line.

**Plant care** (archetype: *progress session*) — drop domain, "Ultima:
Monstera" context line.

**Emergency Mode** (new; archetype: *persistent status*)
- While Emergency Mode is active: compact = SOS glyph in `brandDanger`;
  expanded = mode name, active-since, action **Dezactivează** (intent,
  confirmation in-app) + **Deschide**. Critical treatment, never auto-
  dismisses. This is the only activity allowed to use red.

**ARIA jobs** (new; archetype: *indeterminate → done*; only for jobs that
genuinely continue after backgrounding)
- Compact trailing: three-dot thinking glyph (animated between updates via
  state ticks, ≤1/30 s, or static when Reduce Motion).
- Expanded: job name ("Recap lunar"), stage line, **Anulează**. Done state:
  checkmark + **Vezi raportul** deep link, auto-dismiss 8 s.

**IoT alert** (new; archetype: *attention*; one activity per alerting sensor,
capped at the 2 most severe)
- Severity ladder from sensor type: *critical* (smoke, gas, water) →
  `brandDanger`, ActivityKit alert, never auto-dismisses until the sensor
  clears or the user acknowledges; *warning* (threshold breach on
  temperature/power/CO₂/…, door/window open past a configured window,
  motion while Emergency Mode armed) → `brandWarning`.
- Compact: sensor-type symbol (from `IoTSensor.SensorType.icon`) + terse
  state ("Apă!", "23,5°", "Deschis"). Expanded: sensor name + linked zone
  ("Bucătărie"), live value, since-when, actions **Vezi** (deep link
  `prvio://iot`) and **Am înțeles** (acknowledge intent — silences this
  alert instance, never the sensor).
- Ends automatically when `isAlerting` clears (value back in range,
  door closed, smoke clear) — success flip (§8), dismiss 5 s.

**Energy** (new; archetype: *live gauge*; user-started from the IoT hub or
auto on a peak alert)
- Compact trailing: current draw "2,8 kW" (numericText). If both power
  (consumption) and a solar-tagged energy sensor exist: net value with
  directional arrow (▼ importing / ▲ exporting).
- Expanded: consumption vs production twin bars, today's kWh, peak chip
  when above threshold. Action: **Deschide** (IoT hub deep link).
- Updates only from real polls/webhooks; staleDate +15 min so the system
  dims stale readings instead of showing false "live" data.

**Cover control — garage / gate** (new; archetype: *operation*; requires
Phase E actuators)
- Started by the user's own command (in-app, Control Center control, or
  App Intent — never spontaneously). States: `sent → moving →
  (open/closed | obstructed | timeout)`; `moving` runs a determinate bar
  only if the device reports position, otherwise an indeterminate shimmer —
  no fake percentages.
- Compact: garage symbol + state word. Expanded: device name, state,
  actions **Oprește** / **Inversează** (only if the actuator protocol
  supports them — capability-gated buttons, §5.5).
- `obstructed`/`timeout` use warning treatment + alert. Terminal states
  auto-dismiss after 4 s.

### 2.3 Multiple simultaneous activities

The system shows the two most-recent activities in the island (one compact,
one minimal). We do not fight it: every activity must carry meaning in its
bare minimal glyph. PRVIO caps itself at **one activity per kind** plus at
most 3 concurrent delivery activities (most-recently-updated wins;
`LiveActivityService` already keys deliveries by id — add the cap).

---

## 3. UI specification

### 3.1 Tokens (single source: DesignSystem + new IslandKit)

- Typography: `AppFont` only — `captionStrong` (compact trailing),
  `footnoteEmphasis` (titles), `title3` (lock icon), rounded-design metric
  via a new `AppFont.metric(_:)` (SF Rounded, text-style-relative). **No
  `.font(.system(size:))` literals.**
- Color per kind (from `LiveActivityKind.tint`): shopping `brandSkyBlue`,
  delivery `brandPrimaryBlue` (→ `brandWarning` out-for-delivery), 
  maintenance `brandWarning`, plantCare `brandSuccess`, workSession `.teal`
  (promote to a `brandTeal` token), emergency `brandDanger`, aria
  `brandPurple`. Status colors always paired with a symbol change.
- Spacing: `AppSpacing` scale; expanded bottom uses `AppSpacing.sm` rows,
  lock card `AppSpacing.lg` padding, 44 pt icon disc (existing) formalized
  as `IslandMetrics.iconDisc`.
- Shape: icon disc = Circle with `tint.opacity(AppOpacity.fill)`;
  progress bars 4 pt, `AppRadius.full`.
- Materials: island is system-black — content only (no glass hacks). Lock
  card keeps `activityBackgroundTint(.clear)` so the system material shows
  through (Liquid-Glass-correct); dark/light handled by system.

### 3.2 Region layout grid (expanded)

```
┌ leading ──────────────┬────────────── trailing ┐
│ ◉ icon  Title (1 ln)  │            METRIC 17pt │
├ bottom ────────────────────────────────────────┤
│ ▰▰▰▱ progress / milestone bar (4 pt)           │
│ context line (footnote, secondary, 1 ln)       │
│ [ Primary action ]  [ Secondary ]              │
└────────────────────────────────────────────────┘
```
Compact: icon 12 pt leading · metric ≤5 ch trailing. Minimal: icon only.

---

## 4. State diagrams

```
Delivery:  ○ pending ─▶ info_received ─▶ in_transit ─▶ out_for_delivery ─▶ ● delivered ✓(6s)
                 │             │              │                │
                 └──────── exception / failed_attempt (⚠ alert) ┘─▶ resumed or ended
Session (shopping/plant/maintenance):
           ○ first item ─▶ updating (n/total) ─▶ ● complete ✓(4–5s) | ✕ abandoned (stale → end)
Work session:  ○ start ─▶ running (system timer) ─▶ ● complete ✓(2s) | ✕ ended (immediate)
Emergency:     ○ armed ─▶ active (persistent, critical) ─▶ ✕ deactivated (immediate)
ARIA job:      ○ queued ─▶ working (stages) ─▶ ● done ✓(8s) | ✕ cancelled/failed (⚠)
```
Rules: every path reaches a terminal state; every terminal state sets a
dismissal policy; every non-terminal update sets a `staleDate` (§8.3).

---

## 5–7. Architecture

### 5.1 Component architecture — `Widgets/IslandKit.swift` (new)

Reusable, preference-aware building blocks (all take `LiveActivityKind`):

- `IslandIconDisc(kind:state:)` — 44 pt disc, symbol crossfade on state.
- `IslandCompactMetric(text:tint:)` — rounded, monospacedDigit, numericText
  transition, ≤5 ch.
- `IslandProgressBar(value:tint:)` / `IslandMilestoneBar(stage:of:tint:)`.
- `IslandHeader(kind:title:)` — leading region.
- `IslandActionBar(primary:secondary:)` — intent buttons, 44 pt targets.
- `IslandLockCard(kind:title:context:metric:actions:)` — the lock-screen
  card every activity composes.
- `LA` preference gates stay, but keyed by `LiveActivityKind` not strings.

All five existing activities are re-skinned onto these components —
`LiveActivityViews.swift` shrinks to thin per-kind compositions.

### 5.2 SwiftUI / model architecture

- `LiveActivityKind` moves to `Sources/LiveActivities/LiveActivityKind.swift`
  (compiled into app + widgets), gains `workSession`, `emergency`, `aria`,
  `iotAlert`, `energy`, `cover` cases and carries: `symbol`, `tint` (token),
  `deepLink`, `titleKey`, auto-start capability flag (work session,
  emergency, aria and cover are user/system-initiated — never auto-start,
  excluded from those toggles but present in per-kind appearance).
- `LiveActivityService` stays the single orchestrator; gains
  `syncEmergency(active:)`, `startARIAJob/updateARIAJob/endARIAJob`,
  `syncIoTAlerts(_:)` (fed by `IoTService.checkAutomations`/`isAlerting`
  transitions), `startEnergySession/updateEnergy/endEnergySession`,
  `startCoverOperation/updateCover/endCoverOperation`, the 3-delivery cap,
  the 2-alert severity cap, staleDate policy, and alert-configured updates.

### 5.5 Smart-home rails (extends the existing IoT layer)

- **Actuators (Phase E).** `IoTDevice` gains an `actuators: [IoTActuator]`
  counterpart to sensors: `kind` (relay, cover, dimmer), `commands`
  (capability set: open/close/stop/toggle/set-level), transport = the
  device's existing protocol (HTTP POST `/command` for ESP32/RPi, Modbus
  write FC 05/06 for RS485). `IoTService.send(_ command:to:)` executes,
  confirms via read-back where the protocol allows, and reports
  `CoverState`. Capability-gated UI: a button renders only if the actuator
  declares that command — no dead controls.
- **Event ingestion & locked-phone updates (Phase F).** New edge function
  `iot-event`: devices (or the existing automation "Call Webhook" action)
  POST sensor events with a per-property secret; the function persists the
  event, evaluates severity, then (a) sends an APNs alert push through the
  existing p8 machinery and (b) sends `apns-push-type: liveactivity`
  updates to any registered IoT activity token (same
  `live_activity_tokens` table as deliveries). Local polling remains the
  in-app path; the webhook path is what makes alerts real when the phone
  is in a pocket.
- **Energy semantics.** Solar production = energy/power sensors the user
  tags as *production* (new `role` field: consumption | production |
  storage) — the Energy island's net arithmetic uses tags the user set,
  not guesses.

### 5.3 ActivityKit architecture

- Attributes structs unchanged where shipped (decode compatibility);
  `DeliveryActivityAttributes.ContentState` gains optional
  `milestoneIndex: Int?`, `checkpoint: String?` (optionals → old payloads
  still decode, same pattern as `propertyName`).
- **Push updates (Phase B):** delivery activities request
  `pushType: .token`; a `pushTokenUpdates` task uploads tokens to a new
  `live_activity_tokens` table (activity_id, tracker_id, token, user_id,
  environment). `track-webhook` (already the single Ship24 authority)
  additionally POSTs APNs `apns-push-type: liveactivity` with the new
  content state, reusing the p8 JWT machinery from `send-chat-push`.
  `NSSupportsLiveActivitiesFrequentUpdates` is already declared.
- Stale dates: delivery = min(ETA end-of-day, +6 h); sessions = +2 h;
  work session = +12 h; emergency = none (never stale).
- Alerts: `AlertConfiguration(title:body:sound:)` on delivery
  exception/out-for-delivery and ARIA failure — Lock Screen lights up,
  island expands briefly (system behavior).

### 5.4 WidgetKit architecture

Bundle unchanged (`PRVIOWidgetBundle`) + `EmergencyLiveActivity`,
`ARIAJobLiveActivity`. Watch mirroring: each ActivityConfiguration adds
`.supplementalActivityFamilies([.small])` so watchOS 11+ Smart Stack
renders a proper small card (compact leading/trailing reused); watchOS 10
(Series 4) shows nothing — the existing watch app + RelevanceKit already
covers that device honestly.

---

## 8. Motion specification

Live Activity transitions between presentations are system-driven (springs
included); we design the **content** transitions:

| Event | Treatment | Timing |
|---|---|---|
| Counter change | `.contentTransition(.numericText())` | system |
| Status word/symbol change | `.contentTransition(.symbolEffect(.replace))` / opacity | system |
| Progress bar | animated by system on update | — |
| Milestone advance | newly-filled segment scales 1.0→1.15→1.0 | `.snappy` |
| Success terminal | icon → `checkmark.circle.fill` bounce (`.symbolEffect(.bounce)`), tint → success | one shot |
| Warning/critical | icon `.symbolEffect(.pulse)` while in that state | system-throttled |
| ARIA thinking | `variableColor.iterative` on ellipsis symbol | system |

Reduce Motion: symbol effects and the milestone pulse are dropped
(crossfade only) — gate via `@Environment(\.accessibilityReduceMotion)`
inside IslandKit, one place.

---

## 9. Haptic specification (in-process actions only — honest haptics)

Haptics fire only where code runs on the phone with the user present:
LiveActivityIntents (app process) and in-app events. Push-driven updates
cannot and must not fake haptics.

| Interaction | Haptic (existing `HapticFeedback`) |
|---|---|
| Complete work session (island button) | `.success()` |
| End session (island button) | `.impact(.light)` |
| Emergency deactivate (intent) | `.warning()` before, `.success()` after |
| ARIA cancel | `.impact(.medium)` |
| In-app: session start that spawns an activity | `.impact(.light)` |
| In-app: delivery flips to out-for-delivery while app open | `.impact(.medium)` |

All respect the existing `prvio.hapticOn` gate automatically.

---

## 10. Accessibility specification

- Every compact/minimal region gets `accessibilityLabel` combining kind +
  state ("Livrare, în tranzit, ajunge azi").
- Dynamic Type: all text through `AppFont` (text-style relative); metrics
  use the new `AppFont.metric`; layouts already single-line + `lineLimit`.
- Color-blind safety: state = symbol + text + tint, never tint alone
  (delivered ⇒ checkmark symbol, not just green).
- RTL: pure `Label`/`HStack` composition — mirrors automatically; the
  milestone bar uses `layoutDirection`-aware fill.
- VoiceOver on Lock Screen actions: buttons already `Label`-based; add
  `accessibilityHint` ("Finalizează sarcina și închide sesiunea").
- Localization: full RO+EN audit of every LA string into `Localizable.xcstrings`
  (several currently unlocalized: "Complete! 🎉", "Plant watering",
  "ETA: %@", "Estimated: %@").

---

## 11. Platform notes

- **Apple Watch:** watchOS 11+ mirrors iPhone Live Activities in the Smart
  Stack automatically; `.supplementalActivityFamilies([.small])` gives us a
  designed small presentation instead of the generic one. No watch-side
  code. Series 4 / watchOS 10: not supported by the OS — no claims made.
- **iPad:** Live Activities render on the iPadOS Lock Screen; our lock card
  is width-flexible (no fixed widths besides timer slots). Verified as part
  of the iPad sprint.
- **StandBy:** lock card must stay legible under red night tint — the
  symbol+text rule (§10) already guarantees it.
- **Vision Pro:** no ActivityKit surface targeted today; architecture keeps
  attributes/state platform-neutral so a future visionOS presentation layer
  is additive. No speculative code ships.
- **Battery:** timer archetype needs zero updates (system-counted); session
  updates are user-action-driven; delivery pushes are server-event-driven
  (a handful per parcel per day); staleDates let the system decay instead
  of us polling. No timers in widget processes.

---

## 12. Implementation phases (each = one reviewable build)

- **Phase A — IslandKit + re-skin (foundation).** New `LiveActivityKind`
  (moved, extended), `IslandKit.swift`, all 5 activities recomposed on
  shared components with tokens, motion treatments, haptics in the two
  session intents, staleDates, RO/EN localization audit, accessibility
  labels, settings screen follows the enum (work session becomes
  customizable). No schema, no new activities. *Risk: low.*
- **Phase B — Delivery flagship.** Milestone bar + checkpoint line + ETA
  chip + warning/success treatments + AlertConfiguration; ActivityKit push
  end-to-end: token upload table + migration, `track-webhook` liveactivity
  push (reuses APNs p8), delivery cap = 3. *Risk: medium (server + APNs).*
- **Phase C — New honest activities.** Emergency Mode activity (critical
  archetype) + ARIA job activity for the monthly recap generation path
  (only if the job runs detached from the sheet — verified during build).
  *Risk: low–medium.*
- **Phase D — Platform polish.** `supplementalActivityFamilies` watch small
  presentation, StandBy/iPad verification pass, settings live-preview
  refresh to mirror the new visuals exactly.
- **Phase E — Smart-home control + alert islands.** `IoTActuator` model +
  `IoTService.send(command:)` (HTTP + Modbus write), cover/relay controls
  in the IoT hub, Cover Live Activity, IoT-alert Live Activity driven by
  local polling (`isAlerting` transitions), Energy island (sensor `role`
  tags + net gauge). Everything works with the app alive; honest about
  that limitation in UI copy. *Risk: medium (device protocols).*
- **Phase F — Locked-phone smart home.** `iot-event` edge function
  (secret-authenticated webhook), event persistence, APNs alert +
  liveactivity pushes for IoT kinds, automation "Call Webhook" preset that
  targets it, registration UI. Completes the promise: a leak at 3 AM
  lights up the island with the phone locked. *Risk: medium–high (server,
  security).*

Acceptance (every phase): CI green; no `.font(.system(size:))` or hardcoded
non-token colors in `Widgets/LiveActivityViews.swift`/`IslandKit.swift`;
every user-facing string localized RO+EN; every action performs exactly
what its label claims.
