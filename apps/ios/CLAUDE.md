# iOS Engineering Standard (permanent)

Every feature, screen, animation, refactor, and UI component in this app must
meet Apple's first-party quality bar. This is not an optional pass at the end
— it is the default mindset for every change, applied automatically, not only
when explicitly requested.

Work from the mindset of a Senior Apple Frameworks Engineer.

## Always prioritize

- 120 FPS on ProMotion devices; stable 60 FPS on all supported devices.
- Zero unnecessary view body recomputations; minimal SwiftUI invalidation.
- Minimal memory, CPU, GPU, and battery usage.
- Instant interaction responsiveness.
- Production-ready architecture — follow Apple's Human Interface Guidelines
  and modern SwiftUI best practices throughout.

## SwiftUI rules

- Prefer the Observation framework (`@Observable`) over `ObservableObject`
  where the codebase's target/toolchain allows it; minimize `ObservableObject`
  usage otherwise.
- Avoid unnecessary `AnyView` and `GeometryReader`.
- Use `Lazy*Stack`/`Lazy*Grid` for scrollable collections.
- Keep view hierarchies lightweight; break large views into small, reusable
  components rather than one large `body`.
- Avoid nested `ScrollView`s.
- Reuse expensive views; cache images; load data asynchronously.
- Never block the main actor — move expensive work off the main thread.
- Optimize navigation, state updates, and re-render triggers; prevent
  unnecessary recomputation.
- Respect Reduce Motion.
- Keep scrolling perfectly smooth — no dropped frames, no stutter.

## Animation rules

Animations must feel identical to Apple's own apps.

- Prefer `.smooth`, `.snappy`, `.bouncy`, or `spring(duration:bounce:)`.
- Never ship an animation that feels slow or heavy.
- Animate only what actually needs to move.

## Rendering rules

Minimize overdraw, blur, transparency, shadows, and offscreen rendering.
Every one of these has a real compositor cost — use them deliberately, not by
default.

## Navigation

Sheets, popovers, transitions, keyboard presentation, gestures, and scrolling
must never stutter. Navigation should feel instantaneous.

## Profiling mindset — before calling anything done

- Look for bottlenecks; remove unnecessary work.
- Reduce allocations, layout recalculations, and redraws.
- Optimize memory, CPU, and GPU cost.
- If a better implementation exists, use it — don't stop at "it works."

A task is finished only when it is production-ready, highly optimized,
scalable, maintainable, and indistinguishable from a first-party Apple
application. When choosing between easier code and Apple's level of polish,
always choose the polish.
