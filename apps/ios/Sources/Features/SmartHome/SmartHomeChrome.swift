import SwiftUI

// MARK: - Smart-home chrome (shared by the home tab, device page, climate page)
//
// Since the Liquid Glass re-skin this file speaks the app's ONE native
// component language: `liquidGlass` / `GlassCard` materials, adaptive
// `.primary`/`.secondary` foregrounds, and the AppFont/AppSpacing/AppRadius
// tokens — the mood backdrop (`appBackground`) shows through every surface,
// in both light (morning/day) and dark (night) schemes. The warm bronze
// `SmartHomeTheme` skin is retired here; only the retired twin files still
// reference it (see the legacy shims at the bottom).
//
// What lives here: the press micro-interaction, the radial icon glow, the
// vertical pill toggle, the "+" chip, the thin level slider, the shared
// Schedule card, and the space-hero typography constants shared by the
// Spaces tab and the space page.

// MARK: - Space hero typography (shared: SpacesTabView + SpaceDetailView)

/// The free-floating space title's shared metrics, so tab 2 and the space
/// page can never drift apart.
enum SpaceHero {
    /// Breathing room of pure backdrop above the space page's floating title.
    static let breath: CGFloat = 140
    /// The free-floating space name — large and light, tracking tight.
    static let nameSize: CGFloat = 36
    static let nameTracking: CGFloat = -0.5
    /// Metric tile live-value size on the space page.
    static let metricValueSize: CGFloat = 22
}

// MARK: - Card press micro-interaction

/// The shared press feedback for tappable cards (hero tiles, widgets):
/// a subtle scale-down while pressed, sprung back with `.snappy`. Under
/// Reduce Motion the scale is off entirely — the tap still lands, nothing
/// moves. Haptics stay in the button ACTIONS (one light impact per tap),
/// not here, so a cancelled press never buzzes.
struct SmartCardPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Pressed-card scale for the shared press micro-interaction.
    private static let pressedScale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(!reduceMotion && configuration.isPressed
                         ? Self.pressedScale : 1)
            .animation(reduceMotion ? nil : AppMotion.tap,
                       value: configuration.isPressed)
    }
}

// MARK: - Radial icon glow

/// A soft radial glow behind a device icon — decorative only, always paired
/// with a real icon on top. Tinted per surface (device cards use the app
/// accent, climate uses orange, cameras blue); the low opacity reads on both
/// the light and dark mood grounds.
struct SmartRadialGlow: View {
    var diameter: CGFloat = 120
    var color: Color = .accentColor

    /// Glow opacity at the glow's center (fades to clear).
    private static let opacity: Double = 0.25

    var body: some View {
        Circle()
            .fill(RadialGradient(
                colors: [color.opacity(Self.opacity), .clear],
                center: .center,
                startRadius: 0,
                endRadius: diameter / 2))
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(true)
    }
}

// MARK: - Vertical pill toggle

/// The smart-home toggle: a vertical ~30×52 capsule. Off — a quiet primary
/// tint with the dot resting at the bottom; on — accent-filled with the
/// white dot at the top (the system switch's own color contract, so it
/// reads on both schemes). The dot travels with a `.snappy` spring (frozen
/// under Reduce Motion). Exposed to accessibility as a switch.
struct SmartPillToggle: View {
    @Binding var isOn: Bool
    /// Spoken name of what the toggle controls (device name, "Schedule"…).
    var accessibilityLabel: Text

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    private static let dotSize: CGFloat = 22
    private static let size = CGSize(width: 30, height: 52)

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
                isOn.toggle()
            }
        } label: {
            Capsule(style: .continuous)
                .fill(isOn ? Color.accentColor : Color.primary.opacity(AppOpacity.tintedFill))
                .overlay(alignment: isOn ? .top : .bottom) {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        .frame(width: Self.dotSize, height: Self.dotSize)
                        .padding(4)
                }
                .frame(width: Self.size.width, height: Self.size.height)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityRepresentation {
            Toggle(isOn: $isOn) { accessibilityLabel }
        }
    }
}

// MARK: - Thin level slider (brightness)

/// The brightness control: a 4pt track with a 22pt white round thumb.
/// Commits ONCE per interaction (drag end / accessibility step) — the same
/// write discipline as the rest of the device surface.
struct SmartLevelSlider: View {
    /// 0…100 percent.
    @Binding var percent: Double
    var isEnabled: Bool = true
    /// Called with the final value on drag end / accessibility step.
    var onCommit: (Double) -> Void

    private static let trackHeight: CGFloat = 4
    private static let thumbSize: CGFloat = 22
    private static let accessibilityStep: Double = 10

    var body: some View {
        // GeometryReader is required: the thumb position is a function of
        // the resolved track width. Height is fixed, so layout stays cheap.
        GeometryReader { geo in
            let usable = max(geo.size.width - Self.thumbSize, 1)
            let fraction = min(1, max(0, percent / 100))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(AppOpacity.tintedFill))
                    .frame(height: Self.trackHeight)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: Self.thumbSize / 2 + fraction * usable,
                           height: Self.trackHeight)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .frame(width: Self.thumbSize, height: Self.thumbSize)
                    .offset(x: fraction * usable)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled else { return }
                        let f = Double((value.location.x - Self.thumbSize / 2) / usable)
                        percent = min(100, max(0, f * 100))
                    }
                    .onEnded { _ in
                        guard isEnabled else { return }
                        onCommit(percent)
                    })
        }
        .frame(height: Self.thumbSize + 4)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityElement()
        .accessibilityLabel(Text("sh_brightness"))
        .accessibilityValue(Text(verbatim: "\(Int(percent.rounded()))%"))
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            switch direction {
            case .increment: percent = min(100, percent + Self.accessibilityStep)
            case .decrement: percent = max(0, percent - Self.accessibilityStep)
            @unknown default: return
            }
            onCommit(percent)
        }
    }
}

// MARK: - Schedule card (shared: device page + climate page)

/// The Schedule card: title + pill toggle, and when ON, the From/To time
/// chips. Wiring is real per provider:
/// - HomeKit accessories with power → a daily `HMTimerTrigger` pair on the
///   accessory's home (on at From, off at To) via `SmartScheduleService`.
/// - IoT relays → the schedule persists locally and is evaluated by a
///   lightweight foreground check; the caption says so honestly.
/// Rendered only for devices the service can genuinely schedule.
struct SmartScheduleCard: View {
    let device: SmartDevice

    @Environment(\.scenePhase) private var scenePhase

    private let service = SmartScheduleService.shared

    /// Draft mirrors the persisted schedule; edits apply through the
    /// service and are reverted if the (HomeKit) apply fails.
    @State private var draft: SmartSchedule = .default
    @State private var isApplying = false
    @State private var applyFailed = false

    var body: some View {
        GlassCard(padding: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(alignment: .center, spacing: AppSpacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("sh_schedule")
                            .font(AppFont.scaled(16, weight: .semibold))
                            .foregroundStyle(.primary)
                        if case .iotRelay = device.backing {
                            // Honest: the relay schedule runs only while
                            // the app itself is running.
                            Text("sh_schedule_note_iot")
                                .font(AppFont.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    SmartPillToggle(isOn: enabledBinding,
                                    accessibilityLabel: Text("sh_schedule"))
                        .disabled(isApplying)
                }

                if draft.isEnabled {
                    HStack(spacing: AppSpacing.md) {
                        timeChip(titleKey: "sh_schedule_from", minutes: fromBinding)
                        timeChip(titleKey: "sh_schedule_to", minutes: toBinding)
                    }
                }

                if applyFailed {
                    Text("sh_schedule_error")
                        .font(AppFont.caption2)
                        .foregroundStyle(Color.brandWarning)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // task(id:) instead of onAppear: the device page's picker pills can
        // swap the device UNDER this card (same view identity), and the
        // draft must re-read the new device's persisted schedule.
        .task(id: device.id) {
            draft = service.schedule(for: device.id) ?? .default
            applyFailed = false
            service.evaluateIoTSchedules()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { service.evaluateIoTSchedules() }
        }
    }

    // MARK: Time chips — compact hour/minute pickers in glass chips

    private func timeChip(titleKey: LocalizedStringKey,
                          minutes: Binding<Int>) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Text(titleKey)
                .font(AppFont.caption)
                .foregroundStyle(.secondary)
            DatePicker("", selection: dateBinding(minutes),
                       displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)
                .labelsHidden()
                .accessibilityLabel(Text(titleKey))
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xxs)
        .liquidGlass(cornerRadius: AppRadius.md)
        .disabled(isApplying)
    }

    /// Bridges minutes-from-midnight (the persisted form) to the Date the
    /// system picker needs, anchored to today.
    private func dateBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: minutes.wrappedValue / 60,
                                      minute: minutes.wrappedValue % 60,
                                      second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            })
    }

    // MARK: Bindings → service applies

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { draft.isEnabled },
            set: { on in
                draft.isEnabled = on
                apply()
            })
    }

    private var fromBinding: Binding<Int> {
        Binding(get: { draft.fromMinutes },
                set: { draft.fromMinutes = $0; apply() })
    }

    private var toBinding: Binding<Int> {
        Binding(get: { draft.toMinutes },
                set: { draft.toMinutes = $0; apply() })
    }

    /// Applies the draft through the service (best-effort): success keeps
    /// the draft as the new saved state; failure reverts to what is truly
    /// persisted and says so.
    private func apply() {
        let pending = draft
        isApplying = true
        applyFailed = false
        Task { @MainActor in
            let ok = await service.setSchedule(pending, for: device)
            isApplying = false
            if !ok {
                applyFailed = true
                draft = service.schedule(for: device.id) ?? .default
            }
        }
    }
}

// MARK: - Legacy shims (retired twin files only)
//
// The unreferenced Digital Twin files (Twin3DView, TwinInsightsSheet, …)
// still compile against these two names. They now render the native
// language too, so nothing bronze survives in code that builds; both shims
// go away with the twin cleanup pass. Live surfaces use `appBackground`
// and `GlassCard` directly — never these.

/// LEGACY: the old warm photo backdrop. Now the living mood backdrop; the
/// photo parameter is ignored (the mood ground is the app-wide backdrop).
struct SmartHomeBackdrop: View {
    let photoSource: String?

    var body: some View {
        AppBackdrop()
            .ignoresSafeArea()
    }
}

/// LEGACY: the old warm glass card. Now exactly `GlassCard`.
struct SmartGlassCard<Content: View>: View {
    var padding: CGFloat = AppSpacing.lg
    @ViewBuilder let content: () -> Content

    var body: some View {
        GlassCard(padding: padding) {
            content()
        }
    }
}
