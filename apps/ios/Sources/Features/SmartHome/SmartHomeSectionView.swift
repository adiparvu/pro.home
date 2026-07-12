import SwiftUI
import HomeKit

// MARK: - Smart Home dashboard section (Smart Home S2)
//
// The home tab's smart-home strip, bound entirely to the S1 aggregation
// layer (`SmartHomeService` + `HomeKitService`): a room filter chip row,
// a HomeKit scene chip row, and a two-column grid of per-kind device
// cards whose toggles write real power state through `setPower`.
//
// Honest states throughout:
// - No devices at all → ONE onboarding card (never an empty grid, never
//   mock tiles) whose button triggers the real HomeKit permission flow.
// - IoT devices but HomeKit unauthorized → the grid plus a slim
//   "Connect HomeKit" row; the row disappears once authorization lands.
// - A power toggle is drawn only when a device in the group actually has
//   the `.power` capability; sensor cards show a live reading instead.

struct SmartHomeSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedRoom: String? = nil

    private let smartHome = SmartHomeService.shared
    private let homeKit = HomeKitService.shared

    /// The selection, ignoring a room that no longer exists (its last
    /// device was removed) — falls back to "All" instead of filtering the
    /// dashboard down to an empty grid.
    private var effectiveRoom: String? {
        guard let selectedRoom, smartHome.rooms.contains(selectedRoom) else { return nil }
        return selectedRoom
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("sh_section_title")
                .font(AppFont.label)
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.leading, AppSpacing.xxs)

            if smartHome.hasAnyDevice {
                if !smartHome.rooms.isEmpty { roomChips }
                if !scenePairs.isEmpty { sceneChips }
                deviceGrid
                if !smartHome.homeKitAuthorized { connectHomeKitRow }
            } else {
                SmartHomeOnboardingCard()
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

    // MARK: - Device grid

    private var gridColumns: [GridItem] {
        [GridItem(.flexible(), spacing: AppSpacing.md),
         GridItem(.flexible(), spacing: AppSpacing.md)]
    }

    /// `devicesByKind` returns labeled tuples; ForEach can't key-path into
    /// tuple elements, so wrap each group in an Identifiable struct keyed by
    /// the kind (stable per room selection — SwiftUI diffing survives).
    private struct KindGroup: Identifiable {
        let kind: SmartDeviceKind
        let devices: [SmartDevice]
        var id: String { kind.id }
    }

    private var kindGroups: [KindGroup] {
        smartHome.devicesByKind(in: effectiveRoom)
            .map { KindGroup(kind: $0.kind, devices: $0.devices) }
    }

    private var deviceGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: AppSpacing.md) {
            ForEach(kindGroups) { group in
                SmartHomeKindCard(kind: group.kind, devices: group.devices)
            }
        }
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

// MARK: - Per-kind device card

/// One card per device kind in the selected room: icon, localized kind
/// title, device count, and — only when the group genuinely supports it —
/// a power toggle that flips every powered device in the group, or the
/// first live sensor reading. Nothing else; no dead controls.
private struct SmartHomeKindCard: View {
    let kind: SmartDeviceKind
    let devices: [SmartDevice]

    private let smartHome = SmartHomeService.shared

    /// Optimistic state while the provider round-trip is in flight, so the
    /// toggle doesn't snap back before HomeKit/the hub confirms. Cleared
    /// the moment the writes finish; the model stays the source of truth.
    @State private var pendingOn: Bool? = nil

    private var powerDevices: [SmartDevice] { devices.filter(\.hasPower) }
    private var readingDevice: SmartDevice? { devices.first { $0.readingValue != nil } }

    private var isOn: Bool {
        pendingOn ?? powerDevices.contains { $0.isOn == true }
    }

    private var powerBinding: Binding<Bool> {
        Binding(
            get: { isOn },
            set: { on in
                HapticFeedback.impact(.light)
                pendingOn = on
                let targets = powerDevices
                Task { @MainActor in
                    for device in targets {
                        await smartHome.setPower(device, on: on)
                    }
                    pendingOn = nil
                }
            })
    }

    var body: some View {
        GlassCard(padding: AppSpacing.base, cornerRadius: AppRadius.xl) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(alignment: .top) {
                    Image(systemName: kind.icon)
                        .font(AppFont.subheadline)
                        .foregroundStyle(kind.accent)
                        .frame(width: 34, height: 34)
                        .background(kind.accent.opacity(AppOpacity.tintedFill), in: Circle())

                    Spacer(minLength: AppSpacing.sm)

                    if !powerDevices.isEmpty {
                        Toggle(isOn: powerBinding) {
                            Text(LocalizedStringKey(kind.titleKey))
                        }
                        .labelsHidden()
                        .tint(kind.accent)
                        .accessibilityLabel(Text(LocalizedStringKey(kind.titleKey)))
                    } else if let device = readingDevice, let value = device.readingValue {
                        Text(verbatim: Self.readingText(value, unit: device.readingUnit))
                            .font(AppFont.metric)
                            .foregroundStyle(kind.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(kind.titleKey))
                        .font(AppFont.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("sh_device_count \(devices.count)")
                        .font(AppFont.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// "21.5 °C" — at most one decimal, unit appended only when present.
    private static func readingText(_ value: Double, unit: String?) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...1)))
        guard let unit, !unit.isEmpty else { return number }
        return "\(number) \(unit)"
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
/// rather than in the frozen S1 model.
private extension SmartDeviceKind {
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
