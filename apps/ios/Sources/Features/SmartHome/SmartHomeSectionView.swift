import SwiftUI
import HomeKit

// MARK: - Smart Home dashboard section (Smart Home S2.5 — reference fidelity)
//
// The home tab's smart-home-first page, bound entirely to the S1 aggregation
// layer (`SmartHomeService` + `HomeKitService`): a room filter chip row, a
// HomeKit scene chip row, and a two-column STAGGERED layout of per-DEVICE
// hero cards. Every card control writes real provider state (`setPower`);
// thermostats draw a mini target-temperature dial instead of an icon disc.
//
// Honest states throughout:
// - No devices at all → ONE onboarding card (never an empty grid, never
//   mock tiles) whose button triggers the real HomeKit permission flow.
// - IoT devices but HomeKit unauthorized → the cards plus a slim
//   "Connect HomeKit" row; the row disappears once authorization lands.
// - A power toggle is drawn only when the device actually has the `.power`
//   capability; sensor cards show a live reading instead.
// - More than 6 devices in the selected room → the 6 most relevant
//   (controllable first, then passive sensors) plus a "See all" glass row
//   that opens the full device list — never an endless dashboard.

struct SmartHomeSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedRoom: String? = nil

    /// What a tap presents: the tapped device's hero sheet (S3), or the
    /// "See all" list when the room holds more devices than the dashboard
    /// shows. One optional drives `.sheet(item:)`, so the two presentations
    /// can never stack or race.
    private enum ActiveSheet: Identifiable {
        case device(SmartDevice)
        case allDevices

        var id: String {
            switch self {
            case .device(let device): "device-\(device.id)"
            case .allDevices:         "all-devices"
            }
        }
    }

    @State private var activeSheet: ActiveSheet? = nil

    private let smartHome = SmartHomeService.shared
    private let homeKit = HomeKitService.shared

    /// How many hero cards the dashboard shows before folding the rest
    /// behind the "See all" row.
    private static let maxVisibleDevices = 6

    /// The selection, ignoring a room that no longer exists (its last
    /// device was removed) — falls back to "All" instead of filtering the
    /// dashboard down to an empty grid.
    private var effectiveRoom: String? {
        guard let selectedRoom, smartHome.rooms.contains(selectedRoom) else { return nil }
        return selectedRoom
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if smartHome.hasAnyDevice {
                if !smartHome.rooms.isEmpty { roomChips }
                if !scenePairs.isEmpty { sceneChips }
                deviceCards
                if scopedDevices.count > Self.maxVisibleDevices { seeAllRow }
                if !smartHome.homeKitAuthorized { connectHomeKitRow }
            } else {
                SmartHomeOnboardingCard()
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .device(let device):
                SmartDeviceSheet(device: device)
            case .allDevices:
                SmartHomeDeviceListSheet(kind: nil, room: effectiveRoom)
            }
        }
    }

    // MARK: - Room filter chips

    private var roomChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                GlassFilterChip(label: String(localized: "sh_room_all"),
                                isSelected: effectiveRoom == nil) {
                    select(nil)
                }
                ForEach(smartHome.rooms, id: \.self) { room in
                    GlassFilterChip(label: room, isSelected: effectiveRoom == room) {
                        select(room)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.xxs)
        }
    }

    private func select(_ room: String?) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
            selectedRoom = room
        }
    }

    // MARK: - HomeKit scenes

    /// Home × action-set pairs so chips from several homes share one row
    /// (a struct because ForEach can't key-path into tuple elements).
    private struct ScenePair: Identifiable {
        let home: HMHome
        let actionSet: HMActionSet
        var id: UUID { actionSet.uniqueIdentifier }
    }

    private var scenePairs: [ScenePair] {
        guard homeKit.isAuthorized else { return [] }
        return homeKit.homes.flatMap { home in
            homeKit.actionSets(in: home).map { ScenePair(home: home, actionSet: $0) }
        }
    }

    private var sceneChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(scenePairs) { pair in
                    sceneChip(pair.actionSet, in: pair.home)
                }
            }
            .padding(.horizontal, AppSpacing.xxs)
        }
    }

    private func sceneChip(_ actionSet: HMActionSet, in home: HMHome) -> some View {
        Button {
            HapticFeedback.impact(.light)
            Task {
                do {
                    try await homeKit.execute(actionSet, in: home)
                    HapticFeedback.success()
                } catch {
                    HapticFeedback.error()
                    debugLog("Scene execution failed:", error)
                }
            }
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "sparkles")
                    .font(AppFont.captionStrong)
                Text(verbatim: actionSet.name)
                    .font(AppFont.captionEmphasis)
                    .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.sm)
            .mediaGlass(in: Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: actionSet.name))
    }

    // MARK: - Device hero cards (staggered two-column layout)

    /// Devices in the selected room, most relevant first: anything the user
    /// can act on (power, brightness, climate, lock) leads; passive sensors
    /// and read-only devices follow. Order is otherwise stable (provider
    /// order), so cards don't shuffle between renders.
    private var scopedDevices: [SmartDevice] {
        let scoped = smartHome.devices(in: effectiveRoom)
        return scoped.filter(\.isControllable) + scoped.filter { !$0.isControllable }
    }

    private var visibleDevices: [SmartDevice] {
        let all = scopedDevices
        guard all.count > Self.maxVisibleDevices else { return all }
        return Array(all.prefix(Self.maxVisibleDevices))
    }

    /// Two top-aligned columns filled alternately — cards keep their natural
    /// (deliberately varied) heights, which is what produces the reference's
    /// staggered rhythm without a GeometryReader. At most 6 cards render, so
    /// plain VStacks stay cheaper than a lazy grid here.
    private var deviceCards: some View {
        let devices = visibleDevices
        let left = stride(from: 0, to: devices.count, by: 2).map { devices[$0] }
        let right = stride(from: 1, to: devices.count, by: 2).map { devices[$0] }
        return HStack(alignment: .top, spacing: AppSpacing.md) {
            deviceColumn(left)
            deviceColumn(right)
        }
    }

    private func deviceColumn(_ devices: [SmartDevice]) -> some View {
        VStack(spacing: AppSpacing.md) {
            ForEach(devices) { device in
                SmartDeviceHeroCard(device: device) {
                    activeSheet = .device(device)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - "See all" row (room holds more devices than the dashboard shows)

    private var seeAllRow: some View {
        Button {
            HapticFeedback.impact(.light)
            activeSheet = .allDevices
        } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "square.grid.2x2")
                    .font(AppFont.headline)
                    .foregroundStyle(Color.brandIndigo)
                Text("sh_see_all")
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(.primary)
                Spacer(minLength: AppSpacing.sm)
                Text("sh_device_count \(scopedDevices.count)")
                    .font(AppFont.caption2)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(AppFont.captionStrong)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .liquidGlass(cornerRadius: AppRadius.lg)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Slim "Connect HomeKit" row (IoT devices exist, HomeKit not yet authorized)

    private var connectHomeKitRow: some View {
        Button {
            HapticFeedback.impact(.light)
            smartHome.connectHomeKit()
        } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "homekit")
                    .font(AppFont.headline)
                    .foregroundStyle(Color.brandIndigo)
                Text("sh_connect_homekit")
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(.primary)
                Spacer(minLength: AppSpacing.sm)
                Image(systemName: "chevron.right")
                    .font(AppFont.captionStrong)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .liquidGlass(cornerRadius: AppRadius.lg)
    }
}

// MARK: - Per-device hero card

/// One large card per DEVICE (the reference's staggered tiles): a tinted
/// icon disc — or, for thermostats with a target, a mini circular dial —
/// the device name, an honest one-line state, and a power toggle drawn only
/// when the device genuinely has the `.power` capability. Nothing else; no
/// dead controls.
///
/// Height staggering comes from the CONTENT: thermostat/light cards carry a
/// ~90pt visual area, plain switch/sensor cards a compact disc — no fixed
/// frames, no GeometryReader, so Dynamic Type can grow every card safely.
///
/// Tapping the card BODY opens the S3 device sheet; the toggle keeps its
/// own gesture, so flipping power never accidentally navigates.
private struct SmartDeviceHeroCard: View {
    let device: SmartDevice
    /// Invoked on a body tap (and via the VoiceOver activate action).
    let onOpen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let smartHome = SmartHomeService.shared

    /// Optimistic state while the provider round-trip is in flight, so the
    /// toggle doesn't snap back before HomeKit/the hub confirms. Cleared
    /// the moment the write finishes; the model stays the source of truth.
    @State private var pendingOn: Bool? = nil

    /// The thermostat dial's commanded range — mirrors the S3 sheet's
    /// climate control (10–30 °C) so both surfaces tell the same story.
    private static let targetRange: ClosedRange<Double> = 10...30

    /// Tall cards (the reference's hero tiles): thermostats and lights get
    /// the ~90pt visual area; switches/outlets/sensors stay compact.
    private var isTall: Bool { device.kind == .thermostat || device.kind == .light }

    private var isOn: Bool { pendingOn ?? (device.isOn == true) }

    private var powerBinding: Binding<Bool> {
        Binding(
            get: { isOn },
            set: { on in
                HapticFeedback.impact(.light)
                pendingOn = on
                Task { @MainActor in
                    await smartHome.setPower(device, on: on)
                    pendingOn = nil
                }
            })
    }

    var body: some View {
        GlassCard(padding: AppSpacing.base, cornerRadius: AppRadius.xl) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                visualArea
                    .frame(maxWidth: .infinity, alignment: isTall ? .center : .leading)

                HStack(alignment: .bottom, spacing: AppSpacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: device.name)
                            .font(AppFont.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        stateLine
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    // VoiceOver path to the tap gesture below (gestures on
                    // the card container aren't reachable as elements): the
                    // title block is a button that opens the device sheet,
                    // while the toggle stays its own element.
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(Text("sh_card_open_hint"))
                    .accessibilityAction { onOpen() }

                    Spacer(minLength: 0)

                    if device.hasPower {
                        Toggle(isOn: powerBinding) {
                            Text(verbatim: device.name)
                        }
                        .labelsHidden()
                        .fixedSize()
                        .tint(device.kind.accent)
                        .disabled(!device.isReachable)
                        .accessibilityLabel(Text(verbatim: device.name))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // A tap anywhere on the card body opens the device sheet; the
        // Toggle's own gesture takes precedence, so it never navigates.
        .onTapGesture {
            HapticFeedback.impact(.light)
            onOpen()
        }
    }

    // MARK: Visual area — tinted icon disc, or the thermostat mini dial

    @ViewBuilder private var visualArea: some View {
        if device.kind == .thermostat, let target = smartHome.targetTemperature(of: device) {
            thermostatDial(target)
        } else {
            Image(systemName: device.kind.icon)
                .font(AppFont.scaled(isTall ? 24 : 17, weight: .semibold))
                .foregroundStyle(device.kind.accent)
                .frame(width: isTall ? 64 : 40, height: isTall ? 64 : 40)
                .background(device.kind.accent.opacity(AppOpacity.tintedFill), in: Circle())
                .frame(height: isTall ? 90 : 40)
                .accessibilityHidden(true)
        }
    }

    /// The reference's mini climate dial: a subtle full-circle track with a
    /// trimmed accent arc marking where the commanded target sits in the
    /// 10–30 °C range, the target itself bold in the center. Read-only here —
    /// the real control lives in the S3 sheet a tap away.
    private func thermostatDial(_ target: Double) -> some View {
        let span = Self.targetRange.upperBound - Self.targetRange.lowerBound
        let clamped = min(Self.targetRange.upperBound,
                          max(Self.targetRange.lowerBound, target))
        let fraction = (clamped - Self.targetRange.lowerBound) / span
        return ZStack {
            Circle()
                .stroke(Color.subtleFill, style: StrokeStyle(lineWidth: 6, lineCap: .round))
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(device.kind.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: fraction)
            Text(verbatim: Self.temperatureText(clamped))
                .font(AppFont.metricLarge)
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, AppSpacing.sm)
        }
        .frame(width: 84, height: 84)
        .padding(.vertical, 3)
        .accessibilityElement()
        .accessibilityLabel(Text("sh_climate_target"))
        .accessibilityValue(Text(verbatim: Self.temperatureText(clamped)))
    }

    // MARK: State line — honest, in priority order

    /// Unreachable → live brightness (lit lights) → live sensor reading →
    /// thermostat's own measured temperature → reported power state →
    /// the kind name (never a blank line, never a guessed state).
    @ViewBuilder private var stateLine: some View {
        if !device.isReachable {
            Text("sh_unreachable")
                .font(AppFont.caption2)
                .foregroundStyle(Color.brandWarning)
        } else if device.isOn != false,
                  device.capabilities.contains(.brightness),
                  let percent = smartHome.brightness(of: device) {
            Text("sh_state_brightness \(percent)")
                .font(AppFont.caption2)
                .foregroundStyle(.secondary)
        } else if let value = device.readingValue {
            Text(verbatim: Self.readingText(value, unit: device.readingUnit))
                .font(AppFont.metricSmall)
                .foregroundStyle(device.kind.accent)
        } else if device.kind == .thermostat,
                  let current = smartHome.currentTemperature(of: device) {
            Text("sh_state_now \(Self.temperatureText(current))")
                .font(AppFont.caption2)
                .foregroundStyle(.secondary)
        } else if let isOn = device.isOn {
            Text(LocalizedStringKey((pendingOn ?? isOn) ? "sh_state_on" : "sh_state_off"))
                .font(AppFont.caption2)
                .foregroundStyle(.secondary)
        } else {
            Text(LocalizedStringKey(device.kind.titleKey))
                .font(AppFont.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// "21.5°" — locale-aware number, at most one decimal (the 0.5° steps).
    private static func temperatureText(_ celsius: Double) -> String {
        "\(celsius.formatted(.number.precision(.fractionLength(0...1))))°"
    }

    /// "21.5 °C" — at most one decimal, unit appended only when present.
    private static func readingText(_ value: Double, unit: String?) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...1)))
        guard let unit, !unit.isEmpty else { return number }
        return "\(number) \(unit)"
    }
}

// MARK: - Relevance

/// Whether the user can ACT on the device from a card — drives the "most
/// relevant first" ordering when a room holds more devices than the
/// dashboard shows. Presentation-only, so it lives with the S2 view rather
/// than in the frozen S1 model.
private extension SmartDevice {
    var isControllable: Bool {
        hasPower || !capabilities.isDisjoint(with: [.brightness, .color, .targetTemperature, .lock])
    }
}

// MARK: - Onboarding card (no devices from any provider)

/// The honest empty state: one card inviting the user to connect HomeKit —
/// never an empty grid, never placeholder devices.
private struct SmartHomeOnboardingCard: View {
    private let smartHome = SmartHomeService.shared

    var body: some View {
        GlassCard(padding: AppSpacing.xl, cornerRadius: AppRadius.xxl) {
            VStack(spacing: AppSpacing.base) {
                Image(systemName: "homekit")
                    .font(AppFont.scaled(30, weight: .semibold))
                    .foregroundStyle(Color.brandIndigo)
                    .frame(width: 64, height: 64)
                    .background(Color.brandIndigo.opacity(AppOpacity.tintedFill), in: Circle())

                VStack(spacing: AppSpacing.xxs) {
                    Text("sh_onboarding_title")
                        .font(AppFont.title3)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                    Text("sh_onboarding_subtitle")
                        .font(AppFont.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                GlassWideButton(icon: "homekit", label: "sh_connect_homekit") {
                    smartHome.connectHomeKit()
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Kind accents

/// Per-kind brand accent — presentation-only, so it lives with the S2 view
/// rather than in the frozen S1 model. Internal (not private) on purpose:
/// the S3 device sheets (`SmartDeviceSheet.swift`) reuse the same mapping,
/// keeping one source of truth per kind's hue.
extension SmartDeviceKind {
    var accent: Color {
        switch self {
        case .light:      .brandGold
        case .outlet:     .brandSuccess
        case .switcher:   .brandTeal
        case .thermostat: .brandWarning
        case .sensor:     .brandSkyBlue
        case .camera:     .brandIndigo
        case .lock:       .brandPurple
        case .cover:      .brandPrimaryBlue
        case .other:      .brandPrimaryBlue
        }
    }
}
