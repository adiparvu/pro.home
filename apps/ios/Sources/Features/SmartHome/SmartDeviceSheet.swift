import SwiftUI
import HomeKit

// MARK: - Device hero page (Smart Home S3 — warm glass skin)
//
// The single-device control surface, presented as a sheet from the S2
// dashboard: warm photo backdrop, a back affordance plus device-picker
// pills (the room's devices of the same kind — real names, the selected
// one cream), the light-weight device name, the big glowing hero icon,
// then the control cards. Every control section is strictly
// capability-gated (honesty law): a section renders ONLY when its
// capability is in `device.capabilities`, so a relay never grows a
// brightness slider and a sensor never grows a power toggle.
//
// Live-state contract: `SmartDevice` is a value snapshot, so the sheet
// keeps only the selected device's ID and re-resolves the live projection
// from `SmartHomeService.devices` on every render — provider updates
// (reachability, power confirmations, sensor readings) flow into an open
// sheet with no mirroring layer.
//
// Write discipline (unchanged by the reskin):
// - Power: optimistic hold — the pill toggle holds the commanded state
//   until the provider round-trip finishes.
// - Brightness/hue: written on drag END only (never spammed mid-drag);
//   VoiceOver/keyboard adjustments — which never emit editing events — are
//   debounced so each step still lands as a real write.
// - Target temperature: 0.5 °C steps clamped to 10–30 °C, debounced 500 ms
//   so rapid taps coalesce into one HomeKit write.
// - Schedule: a real HMTimerTrigger pair (HomeKit) or the honest local
//   window (IoT relays) via SmartScheduleService — see SmartHomeChrome.

struct SmartDeviceSheet: View {
    /// Snapshot from the presenting surface — identity + fallback only;
    /// `live` below is the source of truth while the sheet is open.
    let device: SmartDevice

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(PropertyService.self) private var propertyService

    private let smartHome = SmartHomeService.shared
    private let homeKit = HomeKitService.shared

    /// The device currently shown — starts as the tapped device and moves
    /// with the picker pills (siblings of the same kind in the same room).
    @State private var selectedID: String? = nil

    /// The room name confirmed by the last successful HomeKit assignment —
    /// bridges the moment between the write landing and the provider
    /// mirror re-rendering. Set only AFTER the write succeeds (honesty).
    @State private var assignedRoomName: String? = nil
    @State private var isAssigningRoom = false
    @State private var roomAssignError: String? = nil

    /// Optimistic power state while the provider round-trip is in flight,
    /// so the toggle doesn't snap back before the accessory confirms.
    @State private var pendingOn: Bool? = nil

    /// User-set brightness. nil until the first interaction — the slider
    /// reads `brightness(of:)` live until then; afterwards the draft holds
    /// (optimistically) so the thumb never snaps while the write settles.
    /// `SmartLevelSlider` commits exactly once per drag AND once per
    /// VoiceOver adjustment step, so no debounce layer is needed here.
    @State private var brightnessDraft: Double? = nil

    /// User-set hue, same draft contract as brightness.
    @State private var hueDraft: Double? = nil

    /// User-set target temperature + the debounce task coalescing steps.
    @State private var targetDraft: Double? = nil
    @State private var targetWriteTask: Task<Void, Never>? = nil

    private static let targetRange: ClosedRange<Double> = 10...30
    private static let targetStep: Double = 0.5
    private static let fallbackTarget: Double = 21
    private static let debounceNanos: UInt64 = 500_000_000

    /// The live projection of the selected device, re-resolved from the
    /// service so provider updates re-render the open sheet. Falls back to
    /// the presentation snapshot if the device vanished mid-presentation.
    private var live: SmartDevice {
        let id = selectedID ?? device.id
        return smartHome.devices.first { $0.id == id } ?? device
    }

    /// The picker pills' population: same room, same kind — real devices
    /// only (an unassigned device matches other unassigned ones, never the
    /// whole home). A single device renders no picker at all.
    private var siblings: [SmartDevice] {
        smartHome.devices.filter { $0.kind == device.kind && $0.room == device.room }
    }

    var body: some View {
        let current = live
        ZStack {
            SmartHomeBackdrop(photoSource: propertyService.primary?.photoUrl)
            ScrollView(showsIndicators: false) {
                VStack(spacing: AppSpacing.lg) {
                    topBar
                    header(current)
                    hero(current)
                    if current.capabilities.contains(.power) { powerCard(current) }
                    if current.hasPower { SmartScheduleCard(device: current) }
                    if current.capabilities.contains(.brightness) { brightnessCard(current) }
                    if current.capabilities.contains(.color) { softLightCard(current) }
                    if current.capabilities.contains(.targetTemperature) { climateCard(current) }
                    if current.capabilities.contains(.reading) { readingCard(current) }
                    // Room assignment exists only for HomeKit accessories —
                    // IoT relays/sensors have no such concept, so they never
                    // grow the row (honesty law).
                    if case .homeKit(let accessory) = current.backing {
                        roomCard(accessory: accessory)
                    }
                    Spacer(minLength: AppSpacing.xxl)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.lg)
            }
            .environment(\.colorScheme, .dark)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onChange(of: selectedID) { _, _ in
            // A different device — drop every in-flight draft so controls
            // read the new device's real state, never the old one's.
            pendingOn = nil
            brightnessDraft = nil
            hueDraft = nil
            targetDraft = nil
            targetWriteTask?.cancel()
            assignedRoomName = nil
            roomAssignError = nil
        }
    }

    // MARK: Top bar — back affordance + device-picker pills

    private var topBar: some View {
        HStack(spacing: AppSpacing.sm) {
            Button {
                HapticFeedback.impact(.light)
                dismiss()
            } label: {
                Image(systemName: "chevron.backward")
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(Color.smartTextPrimary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .glassCircle()
            .accessibilityLabel(Text("sh_close"))

            if siblings.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.sm) {
                        ForEach(siblings) { sibling in
                            SmartChip(label: sibling.name,
                                      isSelected: sibling.id == live.id) {
                                withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
                                    selectedID = sibling.id
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AppSpacing.xxs)
                }
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Header — light-weight name, room, honest reachability

    private func header(_ device: SmartDevice) -> some View {
        VStack(spacing: AppSpacing.xxs) {
            Text(verbatim: device.name)
                .font(AppFont.scaled(26, weight: .light))
                .foregroundStyle(Color.smartTextPrimary)
                .multilineTextAlignment(.center)

            if let room = device.room, !room.isEmpty {
                Text(verbatim: room)
                    .font(AppFont.caption)
                    .foregroundStyle(Color.smartTextSecondary)
            }

            if !device.isReachable {
                HStack(spacing: AppSpacing.xxs) {
                    Image(systemName: "wifi.slash")
                        .font(AppFont.caption2)
                    Text("sh_unreachable")
                        .font(AppFont.captionStrong)
                }
                .foregroundStyle(Color.brandWarning)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.xxs)
                .background(Color.brandWarning.opacity(AppOpacity.tintedFill), in: Capsule())
                .padding(.top, AppSpacing.xxs)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Hero — the big icon over the warm radial glow

    private func hero(_ device: SmartDevice) -> some View {
        ZStack {
            SmartRadialGlow(diameter: 190)
            Image(systemName: device.kind.icon)
                .font(AppFont.scaled(64, weight: .medium))
                .foregroundStyle(Color.smartAmber)
        }
        .frame(height: 130)
        .accessibilityHidden(true)
    }

    // MARK: .power — pill toggle row (optimistic hold)

    private func powerCard(_ device: SmartDevice) -> some View {
        SmartGlassCard(padding: AppSpacing.base) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "power")
                    .font(AppFont.headline)
                    .foregroundStyle(Color.smartAmber)
                Text("sh_power")
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(Color.smartTextPrimary)
                Spacer(minLength: 0)
                SmartPillToggle(isOn: powerBinding(device),
                                accessibilityLabel: Text("sh_power"))
                    .disabled(!device.isReachable)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func powerBinding(_ device: SmartDevice) -> Binding<Bool> {
        Binding(
            get: { pendingOn ?? (device.isOn == true) },
            set: { on in
                pendingOn = on
                Task { @MainActor in
                    await smartHome.setPower(device, on: on)
                    pendingOn = nil
                }
            })
    }

    // MARK: .brightness — thin slider, written on drag end

    private func brightnessCard(_ device: SmartDevice) -> some View {
        let percent = brightnessDraft ?? Double(smartHome.brightness(of: device) ?? 0)
        return SmartGlassCard(padding: AppSpacing.base) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack {
                    Text("sh_light_brightness")
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(Color.smartTextPrimary)
                    Spacer(minLength: AppSpacing.sm)
                    Text(verbatim: "\(Int(percent.rounded()))%")
                        .font(AppFont.metricLarge)
                        .foregroundStyle(Color.smartTextPrimary)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .accessibilityHidden(true) // the slider's value speaks
                }
                SmartLevelSlider(percent: brightnessBinding(device),
                                 isEnabled: device.isReachable) { value in
                    // Drag END / accessibility step — the one write per gesture.
                    HapticFeedback.impact(.light)
                    Task { @MainActor in
                        await smartHome.setBrightness(device, percent: Int(value.rounded()))
                    }
                }
            }
        }
    }

    private func brightnessBinding(_ device: SmartDevice) -> Binding<Double> {
        Binding(
            get: { brightnessDraft ?? Double(smartHome.brightness(of: device) ?? 0) },
            set: { brightnessDraft = $0 })
    }

    // MARK: .color — "Soft Light" spectrum bar, written on drag end

    private func softLightCard(_ device: SmartDevice) -> some View {
        let degrees = hueDraft ?? smartHome.hue(of: device) ?? 0
        return SmartGlassCard(padding: AppSpacing.base) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack {
                    Text("sh_soft_light")
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(Color.smartTextPrimary)
                    Spacer(minLength: AppSpacing.sm)
                    // Live swatch of the selected hue.
                    Circle()
                        .fill(Color(hue: degrees / 360, saturation: 1, brightness: 1))
                        .frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
                        .accessibilityHidden(true)
                }
                HueSpectrumSlider(
                    degrees: Binding(get: { degrees }, set: { hueDraft = $0 }),
                    isEnabled: device.isReachable
                ) { value in
                    HapticFeedback.impact(.light)
                    Task { @MainActor in
                        await smartHome.setHue(device, degrees: value)
                    }
                }
            }
        }
    }

    // MARK: .targetTemperature — climate control (debounced steps)

    private func climateCard(_ device: SmartDevice) -> some View {
        let target = targetDraft ?? smartHome.targetTemperature(of: device) ?? Self.fallbackTarget
        return SmartGlassCard(padding: AppSpacing.lg) {
            VStack(spacing: AppSpacing.base) {
                // Shown only when the thermostat actually reports one.
                if let current = smartHome.currentTemperature(of: device) {
                    VStack(spacing: AppSpacing.xxs) {
                        Text(verbatim: Self.temperatureText(current))
                            .font(AppFont.metricLarge)
                            .foregroundStyle(Color.smartTextSecondary)
                            .monospacedDigit()
                        Text("sh_climate_current")
                            .font(AppFont.label)
                            .foregroundStyle(Color.smartTextSecondary)
                            .textCase(.uppercase)
                    }
                    .accessibilityElement(children: .combine)
                }

                HStack(spacing: AppSpacing.xl) {
                    stepButton(icon: "minus",
                               enabled: device.isReachable && target > Self.targetRange.lowerBound,
                               label: "sh_temp_decrease") {
                        step(device, from: target, by: -Self.targetStep)
                    }

                    Text(verbatim: Self.temperatureText(target))
                        .font(AppFont.scaled(40, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.smartAmber)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(minWidth: 116)
                        .accessibilityLabel(Text("sh_climate_target"))
                        .accessibilityValue(Text(verbatim: Self.temperatureText(target)))

                    stepButton(icon: "plus",
                               enabled: device.isReachable && target < Self.targetRange.upperBound,
                               label: "sh_temp_increase") {
                        step(device, from: target, by: Self.targetStep)
                    }
                }

                Text("sh_climate_target")
                    .font(AppFont.caption2)
                    .foregroundStyle(Color.smartTextSecondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func stepButton(icon: String, enabled: Bool, label: LocalizedStringKey,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(AppFont.scaled(20, weight: .semibold))
                .foregroundStyle(enabled ? Color.smartTextPrimary : Color.smartTextSecondary)
                .frame(width: 52, height: 52)
                .glassCircle()
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(Text(label))
    }

    private func step(_ device: SmartDevice, from current: Double, by delta: Double) {
        let clamped = min(Self.targetRange.upperBound,
                          max(Self.targetRange.lowerBound, current + delta))
        guard clamped != current else { return }
        HapticFeedback.selection()
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            targetDraft = clamped
        }
        // Debounce 500 ms so rapid −/+ taps coalesce into one HomeKit write.
        targetWriteTask?.cancel()
        targetWriteTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.debounceNanos)
            guard !Task.isCancelled else { return }
            await smartHome.setTargetTemperature(device, celsius: clamped)
        }
    }

    /// "21.5°" — locale-aware number, at most one decimal (the 0.5° steps).
    private static func temperatureText(_ celsius: Double) -> String {
        "\(celsius.formatted(.number.precision(.fractionLength(0...1))))°"
    }

    // MARK: Room assignment — HomeKit accessories only (Apple-Home style)

    /// The "Room" row: the accessory's current room and a menu of the
    /// home's real rooms; picking one performs the actual
    /// `assignAccessory` write. Rendered only when the home has rooms to
    /// move the accessory into — an empty menu would be a dead control.
    @ViewBuilder
    private func roomCard(accessory: HMAccessory) -> some View {
        if let home = homeKit.home(of: accessory) {
            let rooms = homeKit.rooms(in: home)
            if !rooms.isEmpty {
                let currentName = assignedRoomName
                    ?? accessory.room?.name
                    ?? String(localized: "hub_room_unassigned")
                SmartGlassCard(padding: AppSpacing.base) {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        HStack(spacing: AppSpacing.md) {
                            Image(systemName: "door.left.hand.closed")
                                .font(AppFont.headline)
                                .foregroundStyle(Color.smartAmber)
                            Text("hub_device_room")
                                .font(AppFont.scaled(16, weight: .semibold))
                                .foregroundStyle(Color.smartTextPrimary)
                            Spacer(minLength: AppSpacing.sm)
                            Menu {
                                ForEach(rooms, id: \.uniqueIdentifier) { room in
                                    Button {
                                        assign(accessory, to: room, in: home)
                                    } label: {
                                        if room.name == currentName {
                                            Label(room.name, systemImage: "checkmark")
                                        } else {
                                            Text(verbatim: room.name)
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: AppSpacing.xxs) {
                                    Text(verbatim: currentName)
                                        .font(AppFont.footnoteEmphasis)
                                        .lineLimit(1)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(AppFont.captionStrong)
                                }
                                .foregroundStyle(Color.smartTextSecondary)
                            }
                            .disabled(isAssigningRoom)
                            .accessibilityLabel(Text("hub_device_room"))
                            .accessibilityValue(Text(verbatim: currentName))
                        }
                        if let roomAssignError {
                            Text(verbatim: roomAssignError)
                                .font(AppFont.caption2)
                                .foregroundStyle(Color.brandWarning)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func assign(_ accessory: HMAccessory, to room: HMRoom, in home: HMHome) {
        HapticFeedback.impact(.light)
        isAssigningRoom = true
        roomAssignError = nil
        Task { @MainActor in
            defer { isAssigningRoom = false }
            do {
                try await homeKit.assignAccessory(accessory, to: room, in: home)
                assignedRoomName = room.name
                HapticFeedback.success()
            } catch {
                HapticFeedback.error()
                roomAssignError = String(
                    format: String(localized: "hub_room_assign_failed"),
                    error.localizedDescription)
            }
        }
    }

    // MARK: .reading — live sensor value, large

    private func readingCard(_ device: SmartDevice) -> some View {
        SmartGlassCard(padding: AppSpacing.lg) {
            VStack(spacing: AppSpacing.xs) {
                Text("sh_sensor_reading")
                    .font(AppFont.label)
                    .foregroundStyle(Color.smartTextSecondary)
                    .textCase(.uppercase)
                if let value = device.readingValue {
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                        Text(verbatim: value.formatted(.number.precision(.fractionLength(0...1))))
                            .font(AppFont.scaled(40, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.smartAmber)
                            .monospacedDigit()
                            .contentTransition(reduceMotion ? .identity : .numericText())
                        if let unit = device.readingUnit, !unit.isEmpty {
                            Text(verbatim: unit)
                                .font(AppFont.title3)
                                .foregroundStyle(Color.smartTextSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    // The sensor exists but has no value — which for IoT
                    // sensors means offline; say so instead of inventing one.
                    Text(verbatim: "—")
                        .font(AppFont.scaled(40, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.smartTextSecondary)
                        .accessibilityLabel(Text("sh_unreachable"))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Device-list sheet
//
// Presented from the dashboard's "See all" row (kind == nil → every device
// in the filtered room) — and reusable as the per-kind list it originally
// was: a simple glass row list (name, room, honest state text) over the
// warm backdrop that drills into the hero page. Devices re-resolve from
// the service on every render, so rows stay live.

struct SmartHomeDeviceListSheet: View {
    /// Restricts the list to one kind; nil shows every device in the room.
    let kind: SmartDeviceKind?
    /// The dashboard's room filter at tap time; nil = all rooms.
    let room: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(PropertyService.self) private var propertyService
    @State private var selectedDevice: SmartDevice? = nil

    private let smartHome = SmartHomeService.shared

    private var devices: [SmartDevice] {
        let scoped = smartHome.devices(in: room)
        guard let kind else { return scoped }
        return scoped.filter { $0.kind == kind }
    }

    private var title: Text {
        if let kind { Text(LocalizedStringKey(kind.titleKey)) } else { Text("sh_all_devices") }
    }

    var body: some View {
        ZStack {
            SmartHomeBackdrop(photoSource: propertyService.primary?.photoUrl)
            ScrollView(showsIndicators: false) {
                VStack(spacing: AppSpacing.sm) {
                    HStack(spacing: AppSpacing.sm) {
                        Button {
                            HapticFeedback.impact(.light)
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.backward")
                                .font(AppFont.footnoteEmphasis)
                                .foregroundStyle(Color.smartTextPrimary)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .glassCircle()
                        .accessibilityLabel(Text("sh_close"))

                        Spacer(minLength: 0)
                        title
                            .font(AppFont.scaled(16, weight: .semibold))
                            .foregroundStyle(Color.smartTextPrimary)
                        Spacer(minLength: 0)
                        // Symmetry spacer matching the back button's width.
                        Color.clear.frame(width: 36, height: 36)
                    }
                    .padding(.bottom, AppSpacing.sm)
                    .accessibilityAddTraits(.isHeader)

                    if devices.isEmpty {
                        // Devices can vanish mid-presentation (accessory
                        // removed); say so instead of an empty scroll.
                        Text("sh_list_empty")
                            .font(AppFont.caption)
                            .foregroundStyle(Color.smartTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, AppSpacing.xl)
                    } else {
                        ForEach(devices) { device in
                            deviceRow(device)
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.lg)
            }
            .environment(\.colorScheme, .dark)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(item: $selectedDevice) { device in
            SmartDeviceSheet(device: device)
        }
    }

    private func deviceRow(_ device: SmartDevice) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
        return Button {
            HapticFeedback.impact(.light)
            selectedDevice = device
        } label: {
            HStack(spacing: AppSpacing.md) {
                ZStack {
                    SmartRadialGlow(diameter: 44)
                    Image(systemName: device.kind.icon)
                        .font(AppFont.subheadline)
                        .foregroundStyle(Color.smartAmber)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: device.name)
                        .font(AppFont.subheadline)
                        .foregroundStyle(Color.smartTextPrimary)
                        .lineLimit(1)
                    if let room = device.room, !room.isEmpty {
                        Text(verbatim: room)
                            .font(AppFont.caption2)
                            .foregroundStyle(Color.smartTextSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: AppSpacing.sm)

                stateText(device)

                Image(systemName: "chevron.right")
                    .font(AppFont.captionStrong)
                    .foregroundStyle(Color.smartTextSecondary)
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            shape.fill(.ultraThinMaterial)
            shape.fill(Color.smartGlassFill)
        }
        .clipShape(shape)
    }

    /// Honest state, in priority order: unreachable → live reading →
    /// reported power state → nothing (never a guessed state).
    @ViewBuilder
    private func stateText(_ device: SmartDevice) -> some View {
        if !device.isReachable {
            Text("sh_unreachable")
                .font(AppFont.caption2)
                .foregroundStyle(Color.brandWarning)
        } else if let value = device.readingValue {
            Text(verbatim: smartReadingText(value, unit: device.readingUnit))
                .font(AppFont.metric)
                .foregroundStyle(Color.smartAmber)
        } else if let isOn = device.isOn {
            Text(LocalizedStringKey(isOn ? "sh_state_on" : "sh_state_off"))
                .font(AppFont.captionEmphasis)
                .foregroundStyle(isOn ? Color.smartAmber : Color.smartTextSecondary)
        }
    }
}

/// "21.5 °C" — at most one decimal, unit appended only when present.
/// Deliberately mirrors `SmartDeviceHeroCard.readingText` (private to the
/// S2 file) so this sheet doesn't force visibility changes on the dashboard.
private func smartReadingText(_ value: Double, unit: String?) -> String {
    let number = value.formatted(.number.precision(.fractionLength(0...1)))
    guard let unit, !unit.isEmpty else { return number }
    return "\(number) \(unit)"
}

// MARK: - Hue spectrum slider ("Soft Light" bar)

/// The reference's spectrum bar: a slim full-width track painted with the
/// hue wheel and a round white-ringed thumb carrying the selected hue.
/// Custom because the system Slider can't paint a gradient track. Commits
/// ONCE per interaction — on drag end, or per VoiceOver adjustment step —
/// never mid-drag.
private struct HueSpectrumSlider: View {
    /// Hue in degrees, 0–360.
    @Binding var degrees: Double
    var isEnabled: Bool = true
    /// Called with the final value on drag end / accessibility step.
    var onCommit: (Double) -> Void

    private static let trackHeight: CGFloat = 14
    private static let thumbSize: CGFloat = 24
    private static let accessibilityStep: Double = 15

    private static let spectrum = LinearGradient(
        colors: stride(from: 0.0, through: 360.0, by: 30.0)
            .map { Color(hue: $0 / 360.0, saturation: 1, brightness: 1) },
        startPoint: .leading, endPoint: .trailing)

    var body: some View {
        // GeometryReader is required here: the thumb position is a function
        // of the track's resolved width. Height is fixed, so layout stays cheap.
        GeometryReader { geo in
            let usable = max(geo.size.width - Self.thumbSize, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Self.spectrum)
                    .frame(height: Self.trackHeight)
                Circle()
                    .fill(Color(hue: degrees / 360, saturation: 1, brightness: 1))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .frame(width: Self.thumbSize, height: Self.thumbSize)
                    .offset(x: CGFloat(degrees / 360) * usable)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled else { return }
                        let fraction = Double((value.location.x - Self.thumbSize / 2) / usable)
                        degrees = min(360, max(0, fraction * 360))
                    }
                    .onEnded { _ in
                        guard isEnabled else { return }
                        onCommit(degrees)
                    })
        }
        .frame(height: Self.thumbSize + 2)
        // Disabled = desaturated spectrum; the sheet's unreachable pill says why.
        .saturation(isEnabled ? 1 : 0.3)
        .accessibilityElement()
        .accessibilityLabel(Text("sh_soft_light"))
        .accessibilityValue(Text(verbatim: "\(Int(degrees.rounded()))°"))
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            switch direction {
            case .increment: degrees = min(360, degrees + Self.accessibilityStep)
            case .decrement: degrees = max(0, degrees - Self.accessibilityStep)
            @unknown default: return
            }
            onCommit(degrees)
        }
    }
}
