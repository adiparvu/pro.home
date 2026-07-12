import SwiftUI
import HomeKit

// MARK: - Climate page (Smart Home — warm glass skin)
//
// Opened by tapping the dashboard's temperature dial card — ALWAYS
// available. Warm photo backdrop, room pills (real rooms), the reference's
// big dotted-arc dial (48 dots over 270°, amber up to the current
// position), −/+ steppers, four mode buttons, and the shared Schedule card
// when a real thermostat exists.
//
// Honesty contract:
// - With a thermostat (with the .targetTemperature capability) in scope,
//   the dial shows its commanded target and −/+ WRITE it (debounced 500 ms
//   through the same SmartHomeService path as the device page), and the
//   Heat/Cold/Air modes write HMCharacteristicTypeTargetHeatingCooling.
// - Without one, the dial adjusts only a locally stored comfort target and
//   the caption says exactly that (sh_climate_no_thermostat) — the page
//   never pretends to command hardware it doesn't have.
// - "Humid" is a read mode: selecting it surfaces the home's real humidity
//   reading (HomeKit characteristic first, then an IoT %-sensor); when no
//   sensor reports one, the caption says so instead of inventing a number.

struct ClimateView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(PropertyService.self) private var propertyService

    private let smartHome = SmartHomeService.shared
    private let homeKit = HomeKitService.shared

    @State private var selectedRoom: String? = nil

    /// Comfort target shown when NO thermostat exists — persisted locally,
    /// clearly labeled as display-only.
    @AppStorage("smartHome.climate.comfortTarget") private var comfortTarget: Double = 22
    /// The selected mode, persisted across launches.
    @AppStorage("smartHome.climate.mode") private var storedMode: String = ClimateUIMode.heat.rawValue

    /// Draft + debounce for thermostat target writes (mirrors the S3 page).
    @State private var targetDraft: Double? = nil
    @State private var targetWriteTask: Task<Void, Never>? = nil

    private static let range: ClosedRange<Double> = 17...28
    private static let step: Double = 0.5
    private static let debounceNanos: UInt64 = 500_000_000

    // MARK: Modes

    enum ClimateUIMode: String, CaseIterable, Identifiable {
        case heat, cold, air, humid
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .heat:  "flame.fill"
            case .cold:  "snowflake"
            case .air:   "wind"
            case .humid: "humidity.fill"
            }
        }

        var labelKey: LocalizedStringKey {
            switch self {
            case .heat:  "sh_mode_heat"
            case .cold:  "sh_mode_cold"
            case .air:   "sh_mode_air"
            case .humid: "sh_mode_humid"
            }
        }

        /// The HomeKit target state this mode commands; nil = read-only mode.
        var homeKitMode: HomeKitService.ClimateMode? {
            switch self {
            case .heat:  .heat
            case .cold:  .cool
            case .air:   .auto
            case .humid: nil
            }
        }
    }

    private var mode: ClimateUIMode {
        ClimateUIMode(rawValue: storedMode) ?? .heat
    }

    // MARK: Scope

    private var rooms: [String] { smartHome.rooms }

    private var effectiveRoom: String? {
        guard let selectedRoom, rooms.contains(selectedRoom) else { return nil }
        return selectedRoom
    }

    /// The thermostat the page commands: the selected room's, when it has
    /// one with a commandable target.
    private var thermostat: SmartDevice? {
        smartHome.devices(in: effectiveRoom).first {
            $0.kind == .thermostat && $0.capabilities.contains(.targetTemperature)
        }
    }

    /// What the dial displays: the thermostat's commanded target (draft
    /// while a write settles), else the local comfort target.
    private var displayedTarget: Double {
        let value = targetDraft
            ?? thermostat.flatMap { smartHome.targetTemperature(of: $0) }
            ?? (thermostat == nil ? comfortTarget : 21)
        return min(Self.range.upperBound, max(Self.range.lowerBound, value))
    }

    /// The home's real humidity, when anything reports one: the HomeKit
    /// characteristic first, then an IoT sensor with a "%" unit.
    private var humidity: Double? {
        if let value = homeKit.firstHumidityReading() { return value }
        return smartHome.devices.first {
            $0.kind == .sensor && $0.readingValue != nil
                && ($0.readingUnit?.contains("%") == true)
        }?.readingValue
    }

    // MARK: Body

    var body: some View {
        ZStack {
            SmartHomeBackdrop(photoSource: propertyService.primary?.photoUrl)
            ScrollView(showsIndicators: false) {
                VStack(spacing: AppSpacing.xl) {
                    topBar
                    Text("sh_kind_thermostats")
                        .font(AppFont.scaled(26, weight: .light))
                        .foregroundStyle(Color.smartTextPrimary)
                        .accessibilityAddTraits(.isHeader)
                    dialSection
                    if thermostat == nil {
                        // Honest: without a thermostat this is a displayed
                        // comfort target, not a hardware command.
                        Text("sh_climate_no_thermostat")
                            .font(AppFont.caption2)
                            .foregroundStyle(Color.smartTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppSpacing.lg)
                    }
                    modeRow
                    if mode == .humid { humidityLine }
                    if let thermostat, thermostat.hasPower {
                        SmartScheduleCard(device: thermostat)
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
        .onChange(of: selectedRoom) { _, _ in
            // Another room may mean another (or no) thermostat — drop the
            // draft so the dial reads the new scope's real target.
            targetDraft = nil
            targetWriteTask?.cancel()
        }
    }

    // MARK: Top bar — back + room pills

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

            if rooms.isEmpty {
                Spacer(minLength: 0)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.sm) {
                        SmartChip(label: String(localized: "sh_room_all"),
                                  isSelected: effectiveRoom == nil) {
                            select(nil)
                        }
                        ForEach(rooms, id: \.self) { room in
                            SmartChip(label: room, isSelected: effectiveRoom == room) {
                                select(room)
                            }
                        }
                    }
                    .padding(.horizontal, AppSpacing.xxs)
                }
            }
        }
    }

    private func select(_ room: String?) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
            selectedRoom = room
        }
    }

    // MARK: Dial section — steppers flanking the dotted arc

    private var dialSection: some View {
        HStack(spacing: AppSpacing.md) {
            stepButton(icon: "minus",
                       enabled: displayedTarget > Self.range.lowerBound,
                       label: "sh_temp_decrease") {
                step(by: -Self.step)
            }

            SmartDottedDial(fraction: fraction) {
                VStack(spacing: 2) {
                    Text("sh_climate_air")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.smartTextSecondary)
                    Text(verbatim: temperatureText(displayedTarget))
                        .font(AppFont.scaled(44, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.smartTextPrimary)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("sh_climate_celsius")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.smartTextSecondary)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("sh_climate_target"))
            .accessibilityValue(Text(verbatim: temperatureText(displayedTarget)))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: step(by: Self.step)
                case .decrement: step(by: -Self.step)
                @unknown default: return
                }
            }

            stepButton(icon: "plus",
                       enabled: displayedTarget < Self.range.upperBound,
                       label: "sh_temp_increase") {
                step(by: Self.step)
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) { rangeLabels }
        .padding(.bottom, AppSpacing.sm)
    }

    /// "17°C / 28°C" at the arc's open ends.
    private var rangeLabels: some View {
        HStack {
            Text(verbatim: rangeText(Self.range.lowerBound))
            Spacer()
            Text(verbatim: rangeText(Self.range.upperBound))
        }
        .font(AppFont.caption2)
        .foregroundStyle(Color.smartTextSecondary)
        .frame(width: 190)
        .offset(y: 6)
        .accessibilityHidden(true) // the dial element already speaks range/value
    }

    private var fraction: Double {
        let span = Self.range.upperBound - Self.range.lowerBound
        return (displayedTarget - Self.range.lowerBound) / span
    }

    private func stepButton(icon: String, enabled: Bool, label: LocalizedStringKey,
                            action: @escaping () -> Void) -> some View {
        Button {
            HapticFeedback.selection()
            action()
        } label: {
            Image(systemName: icon)
                .font(AppFont.scaled(18, weight: .semibold))
                .foregroundStyle(enabled ? Color.smartTextPrimary : Color.smartTextSecondary)
                .frame(width: 48, height: 48)
                .glassCircle()
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(Text(label))
    }

    private func step(by delta: Double) {
        let clamped = min(Self.range.upperBound,
                          max(Self.range.lowerBound, displayedTarget + delta))
        guard clamped != displayedTarget else { return }

        if let thermostat {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                targetDraft = clamped
            }
            // Debounce 500 ms so rapid −/+ taps coalesce into one HomeKit write.
            targetWriteTask?.cancel()
            targetWriteTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: Self.debounceNanos)
                guard !Task.isCancelled else { return }
                await smartHome.setTargetTemperature(thermostat, celsius: clamped)
            }
        } else {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                comfortTarget = clamped
            }
        }
    }

    // MARK: Mode row — Heat / Cold / Air / Humid

    private var modeRow: some View {
        HStack(spacing: AppSpacing.lg) {
            ForEach(ClimateUIMode.allCases) { candidate in
                modeButton(candidate)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func modeButton(_ candidate: ClimateUIMode) -> some View {
        let isSelected = candidate == mode
        return Button {
            HapticFeedback.impact(.light)
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                storedMode = candidate.rawValue
            }
            // Real command when a thermostat exists and the mode maps to a
            // HomeKit state; "Humid" is a read mode by design.
            if let thermostat, case .homeKit(let accessory) = thermostat.backing,
               let hkMode = candidate.homeKitMode {
                Task { @MainActor in
                    try? await homeKit.setTargetHeatingCoolingMode(accessory, mode: hkMode)
                }
            }
        } label: {
            VStack(spacing: AppSpacing.xs) {
                Image(systemName: candidate.icon)
                    .font(AppFont.scaled(18, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.smartInk : Color.smartTextPrimary)
                    .frame(width: 56, height: 56)
                    .background {
                        if isSelected {
                            Circle().fill(Color.smartCream)
                                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                        } else {
                            Circle().fill(.ultraThinMaterial)
                            Circle().fill(Color.smartGlassFill)
                        }
                    }
                Text(candidate.labelKey)
                    .font(AppFont.caption2)
                    .foregroundStyle(isSelected ? Color.smartTextPrimary : Color.smartTextSecondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(candidate.labelKey))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// The humidity readout surfaced by the "Humid" mode — the real value,
    /// or the honest unavailable label.
    private var humidityLine: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "humidity.fill")
                .font(AppFont.captionStrong)
                .foregroundStyle(Color.smartAmber)
            if let humidity {
                Text(verbatim: "\(humidity.formatted(.number.precision(.fractionLength(0))))%")
                    .font(AppFont.metric)
                    .foregroundStyle(Color.smartTextPrimary)
                    .monospacedDigit()
            } else {
                Text("sh_temp_unavailable")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.smartTextSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("sh_mode_humid"))
        .accessibilityValue(Text(verbatim: humidity.map {
            "\($0.formatted(.number.precision(.fractionLength(0))))%"
        } ?? ""))
    }

    // MARK: Formatting

    /// "21.5°" — locale-aware, at most one decimal (the 0.5° steps).
    private func temperatureText(_ celsius: Double) -> String {
        "\(celsius.formatted(.number.precision(.fractionLength(0...1))))°"
    }

    /// "17°C" — the arc's end labels.
    private func rangeText(_ celsius: Double) -> String {
        "\(celsius.formatted(.number.precision(.fractionLength(0))))°C"
    }
}

// MARK: - Dotted-arc dial

/// The reference's dial: ~48 small circles along a 270° arc (opening at the
/// bottom), filled amber up to the current fraction, the rest faint white;
/// arbitrary center content. Pure geometry — no GeometryReader (the size is
/// fixed) and only the dot colors change per value, so re-renders stay cheap.
private struct SmartDottedDial<Center: View>: View {
    /// 0…1 — how far along the arc the amber fill reaches.
    let fraction: Double
    @ViewBuilder let center: () -> Center

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static var size: CGFloat { 260 }
    private static var dotCount: Int { 48 }
    private static var dotSize: CGFloat { 7 }
    /// 270° of arc, opening centered at the bottom: 135° → 405°
    /// (measured clockwise from the positive x-axis).
    private static var startAngle: Double { 135 }
    private static var sweep: Double { 270 }

    var body: some View {
        ZStack {
            ForEach(0..<Self.dotCount, id: \.self) { index in
                dot(at: index)
            }
            center()
                .padding(Self.size * 0.16)
        }
        .frame(width: Self.size, height: Self.size)
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: fraction)
    }

    private func dot(at index: Int) -> some View {
        let progress = Double(index) / Double(Self.dotCount - 1)
        let angle = Angle.degrees(Self.startAngle + progress * Self.sweep)
        let radius = (Self.size - Self.dotSize) / 2
        let lit = progress <= fraction
        return Circle()
            .fill(lit ? Color.smartAmber : Color.white.opacity(0.2))
            .frame(width: Self.dotSize, height: Self.dotSize)
            .offset(x: radius * cos(angle.radians),
                    y: radius * sin(angle.radians))
    }
}
