import SwiftUI

// MARK: - Smart-home warm glass chrome (shared by all three surfaces)
//
// The reference concept's visual vocabulary, built once and reused by the
// dashboard (S2), the device page (S3) and the climate page: the warm
// blurred-photo backdrop, the glass card, the vertical amber pill toggle,
// the cream/glass selector chips, the radial icon glow, the thin level
// slider, and the shared Schedule card. Every color comes from the
// `SmartHomeTheme` tokens in DesignSystem.swift — no accentColor, no brand
// blues on these surfaces.

// MARK: - Backdrop

/// The warm backdrop behind every smart-home surface: the property's real
/// cover photo blurred at ~40pt under a warm-brown darkening gradient, or —
/// honestly, when no photo exists yet — the dark bronze fallback gradient.
/// Callers place it in a ZStack behind their content and wrap the content
/// in `.environment(\.colorScheme, .dark)` so materials and system text
/// resolve against the deliberately dark surface.
struct SmartHomeBackdrop: View {
    /// The property's stored cover-photo reference (public-form URL);
    /// resolved through the signed-storage pipeline like every property image.
    let photoSource: String?

    var body: some View {
        ZStack {
            SmartHomeTheme.fallbackGradient
            if let photoSource, !photoSource.isEmpty {
                GeometryReader { geo in
                    StorageImage(source: photoSource, targetSize: 480) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                                .blur(radius: SmartHomeTheme.backdropBlur, opaque: true)
                        }
                    }
                }
                SmartHomeTheme.overlayGradient
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Glass card

/// The reference card: ~26pt continuous corners, `.ultraThinMaterial` plus
/// the 8%-white glass fill over the photo, and deliberately NO border —
/// depth comes from the material, not a stroke.
struct SmartGlassCard<Content: View>: View {
    var padding: CGFloat = AppSpacing.lg
    @ViewBuilder let content: () -> Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SmartHomeTheme.cardRadius, style: .continuous)
    }

    var body: some View {
        content()
            .padding(padding)
            .background {
                shape.fill(.ultraThinMaterial)
                shape.fill(Color.smartGlassFill)
            }
            .clipShape(shape)
    }
}

/// The one cream card per grid (the reference's white Alarm card): solid
/// `smartCream`, dark ink content, a soft lift shadow.
struct SmartCreamCard<Content: View>: View {
    var padding: CGFloat = AppSpacing.lg
    @ViewBuilder let content: () -> Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SmartHomeTheme.cardRadius, style: .continuous)
    }

    var body: some View {
        content()
            .padding(padding)
            .background(Color.smartCream, in: shape)
            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
    }
}

// MARK: - Radial icon glow

/// The lamp-photo mood behind a device icon: a soft amber radial glow.
/// Decorative only — always paired with a real icon on top.
struct SmartRadialGlow: View {
    var diameter: CGFloat = 120

    var body: some View {
        Circle()
            .fill(RadialGradient(
                colors: [Color.smartAmber.opacity(SmartHomeTheme.glowOpacity), .clear],
                center: .center,
                startRadius: 0,
                endRadius: diameter / 2))
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(true)
    }
}

// MARK: - Vertical pill toggle

/// The reference's toggle: a vertical ~30×52 capsule. Off — translucent
/// 10% white with the dot resting at the bottom; on — amber-filled with a
/// white dot at the top. The dot travels with a `.snappy` spring (frozen
/// under Reduce Motion). Exposed to accessibility as a switch.
struct SmartPillToggle: View {
    @Binding var isOn: Bool
    /// Spoken name of what the toggle controls (device name, "Schedule"…).
    var accessibilityLabel: Text

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    private static let dotSize: CGFloat = 22

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
                isOn.toggle()
            }
        } label: {
            Capsule(style: .continuous)
                .fill(isOn ? Color.smartAmber : Color.white.opacity(0.10))
                .overlay(alignment: isOn ? .top : .bottom) {
                    Circle()
                        .fill(.white)
                        .frame(width: Self.dotSize, height: Self.dotSize)
                        .padding(4)
                }
                .frame(width: SmartHomeTheme.pillToggleSize.width,
                       height: SmartHomeTheme.pillToggleSize.height)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityRepresentation {
            Toggle(isOn: $isOn) { accessibilityLabel }
        }
    }
}

// MARK: - Selector chip

/// The reference's filter/selector chip, rounded ~14pt: selected — cream
/// fill, dark ink text, a subtle lift shadow; unselected — 8%-white glass
/// with warm-white text.
struct SmartChip: View {
    let label: String
    /// Optional leading SF Symbol (scene chips carry a sparkle).
    var systemImage: String? = nil
    let isSelected: Bool
    var action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SmartHomeTheme.chipRadius, style: .continuous)
    }

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            action()
        } label: {
            HStack(spacing: AppSpacing.xxs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(AppFont.scaled(11, weight: .semibold))
                }
                Text(verbatim: label)
                    .font(AppFont.scaled(13, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.smartInk : Color.smartTextPrimary)
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.sm + 1)
            .background {
                if isSelected {
                    shape.fill(Color.smartCream)
                } else {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(Color.smartGlassFill)
                }
            }
            .clipShape(shape)
            .shadow(color: .black.opacity(isSelected ? 0.16 : 0), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The square-ish "+" glass chip that ends the chip row — a real control:
/// it starts the existing Connect-HomeKit flow (adding devices happens in
/// the Home app; this is the app's honest entry point to more devices).
struct SmartPlusChip: View {
    var action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SmartHomeTheme.chipRadius, style: .continuous)
    }

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            action()
        } label: {
            Image(systemName: "plus")
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(Color.smartTextPrimary)
                .frame(width: 34, height: 34)
                .background {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(Color.smartGlassFill)
                }
                .clipShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("sh_connect_homekit"))
    }
}

// MARK: - Thin level slider (brightness)

/// The reference's brightness control: a 4pt track with a 22pt white round
/// thumb. Commits ONCE per interaction (drag end / accessibility step) —
/// the same write discipline as the rest of the S3 surface.
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
                    .fill(Color.white.opacity(0.15))
                    .frame(height: Self.trackHeight)
                Capsule()
                    .fill(Color.smartAmber)
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

/// The reference's Schedule card: title + pill toggle, and when ON, the
/// From/To time chips. Wiring is real per provider:
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
        SmartGlassCard {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(alignment: .center, spacing: AppSpacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("sh_schedule")
                            .font(AppFont.scaled(16, weight: .semibold))
                            .foregroundStyle(Color.smartTextPrimary)
                        if case .iotRelay = device.backing {
                            // Honest: the relay schedule runs only while
                            // the app itself is running.
                            Text("sh_schedule_note_iot")
                                .font(AppFont.caption2)
                                .foregroundStyle(Color.smartTextSecondary)
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
        let shape = RoundedRectangle(cornerRadius: SmartHomeTheme.chipRadius,
                                     style: .continuous)
        return HStack(spacing: AppSpacing.xs) {
            Text(titleKey)
                .font(AppFont.caption)
                .foregroundStyle(Color.smartTextSecondary)
            DatePicker("", selection: dateBinding(minutes),
                       displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(Color.smartAmber)
                .accessibilityLabel(Text(titleKey))
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xxs)
        .background {
            shape.fill(.ultraThinMaterial)
            shape.fill(Color.smartGlassFill)
        }
        .clipShape(shape)
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
