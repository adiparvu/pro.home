import SwiftUI
import HomeKit

// MARK: - Climate page (Smart Home — Liquid Glass)
//
// Opened by tapping the dashboard's temperature dial card — ALWAYS
// available. The app's mood backdrop, the page's one room-filter circle
// (real rooms, one-circle law), the big dotted-arc dial (48 dots over
// 270°, lit in the climate orange up to the current position), −/+
// steppers, four mode buttons, and the shared Schedule card when a real
// thermostat exists.
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

    private let smartHome = SmartHomeService.shared
    private let homeKit = HomeKitService.shared
    /// The cached HomeKit indoor readings the "Now in the house" rows bind
    /// to — @Observable, so the section repaints when a refresh lands.
    private let indoorClimate = IndoorClimateStore.shared

    @State private var selectedRoom: String? = nil
    /// Row tap → the sensor's real history chart (same sheet the space
    /// page's tiles present).
    @State private var historyTarget: SensorHistoryTarget? = nil

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
            appBackground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: AppSpacing.xl) {
                    topBar
                    Text("sh_kind_thermostats")
                        .font(AppFont.scaled(26, weight: .light))
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(.isHeader)
                    dialSection
                    if thermostat == nil {
                        // Honest: without a thermostat this is a displayed
                        // comfort target, not a hardware command.
                        Text("sh_climate_no_thermostat")
                            .font(AppFont.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppSpacing.lg)
                    }
                    modeRow
                    if mode == .humid { humidityLine }
                    outdoorSection
                    indoorSection
                    if let thermostat, thermostat.hasPower {
                        SmartScheduleCard(device: thermostat)
                    }
                    Spacer(minLength: AppSpacing.xxl)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.lg)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(item: $historyTarget) { target in
            SensorHistorySheet(target: target)
        }
        // Fresh-enough indoor readings on arrival (R3): the same fan-out
        // that feeds the dial also refreshes the characteristic cache the
        // humidity line reads from.
        .task { await IndoorClimateStore.shared.refreshIfStale() }
        .onChange(of: selectedRoom) { _, _ in
            // Another room may mean another (or no) thermostat — drop the
            // draft so the dial reads the new scope's real target.
            targetDraft = nil
            targetWriteTask?.cancel()
        }
    }

    // MARK: Top bar — back + the one room-filter circle

    /// The old room chip row folded into the page's ONE circle (the
    /// one-circle law): a single-select room section behind a standalone
    /// glass trigger, sized to sit flush with the back circle. The accent
    /// dot is honest — lit only when a specific room narrows the scope.
    private var topBar: some View {
        HStack(spacing: AppSpacing.sm) {
            Button {
                HapticFeedback.impact(.light)
                dismiss()
            } label: {
                Image(systemName: "chevron.backward")
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .glassCircle()
            .accessibilityLabel(Text("sh_close"))

            Spacer(minLength: 0)

            if !rooms.isEmpty {
                GlassFilterButton(isActive: effectiveRoom != nil,
                                  standaloneSize: 36) {
                    GlassFilterSection(
                        title: "Room",
                        options: roomOptions,
                        selection: Binding(get: { effectiveRoom },
                                           set: { select($0) }))
                }
            }
        }
    }

    /// "All" + every real room, in the providers' order.
    private var roomOptions: [GlassPickerOption<String?>] {
        [GlassPickerOption<String?>(value: nil,
                                    title: String(localized: "sh_room_all"))]
            + rooms.map { GlassPickerOption<String?>(value: $0, title: $0) }
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
                        .foregroundStyle(.secondary)
                    Text(verbatim: temperatureText(displayedTarget))
                        .font(AppFont.scaled(44, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("sh_climate_celsius")
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
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
        .foregroundStyle(.secondary)
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
                .foregroundStyle(enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
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
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor)
                                                : AnyShapeStyle(.primary))
                    .frame(width: 56, height: 56)
                    // A capsule over a square frame is a circle — the
                    // sanctioned selected-filter glass, in the round.
                    .glassFilterCapsule(selected: isSelected)
                Text(candidate.labelKey)
                    .font(AppFont.caption2)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.primary)
                                                : AnyShapeStyle(.secondary))
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
                .foregroundStyle(Color.brandWarning)
            if let humidity {
                Text(verbatim: "\(humidity.formatted(.number.precision(.fractionLength(0))))%")
                    .font(AppFont.metric)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            } else {
                Text("sh_temp_unavailable")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("sh_mode_humid"))
        .accessibilityValue(Text(verbatim: humidity.map {
            "\($0.formatted(.number.precision(.fractionLength(0))))%"
        } ?? ""))
    }

    // MARK: Outside — the property's real weather as context

    /// The real outdoor reading: the cached property weather first, then a
    /// live WeatherKit value; nil renders nothing (honesty law).
    private var outdoorCelsius: Double? {
        if let cached = PropertyWeather.cached() { return cached.temp }
        return WeatherKitService.shared.currentWeather?
            .temperature.converted(to: .celsius).value
    }

    @ViewBuilder
    private var outdoorSection: some View {
        if let outdoor = outdoorCelsius {
            let delta = outdoor - displayedTarget
            VStack(spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "thermometer.sun.fill")
                        .font(AppFont.captionStrong)
                        .foregroundStyle(Color.brandWarning)
                    Text("sh_climate_outside")
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                    Text(verbatim: temperatureText(outdoor))
                        .font(AppFont.captionStrong)
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                    Text(verbatim: "·")
                        .foregroundStyle(.secondary)
                    deltaText(delta)
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                }
                // Honest hint, only when the numbers actually support it:
                // cooling intent + genuinely cooler air outside.
                if mode == .cold, delta < -0.5 {
                    Text("sh_climate_open_window")
                        .font(AppFont.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// "1.5° above target" / "at your target" — vs the dial's value.
    private func deltaText(_ delta: Double) -> Text {
        if abs(delta) < 0.5 { return Text("sh_climate_at_target") }
        let amount = temperatureText(abs(delta))
        return delta > 0
            ? Text(String(format: String(localized: "sh_climate_above"), amount))
            : Text(String(format: String(localized: "sh_climate_below"), amount))
    }

    // MARK: Now in the house — real per-room rows

    private struct ClimateRow: Identifiable {
        let id: String
        let name: String
        let celsius: Double
        let humidity: Double?
        /// The row's real history stream, when one accrues for it.
        let history: SensorHistoryTarget?
    }

    /// Every real indoor reading in scope: the cached HomeKit rows (room-
    /// filtered when the page's circle narrows it) plus the IoT hub's
    /// degree-unit sensors. Empty means no sensor reported — the section
    /// simply doesn't render.
    private var indoorRows: [ClimateRow] {
        var rows: [ClimateRow] = indoorClimate.readings
            .filter { reading in
                guard let room = effectiveRoom else { return true }
                return reading.roomName?.compare(
                    room, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
            .map { reading in
                ClimateRow(
                    id: reading.id.uuidString,
                    name: reading.roomName ?? reading.accessoryName,
                    celsius: reading.celsius,
                    humidity: reading.humidity,
                    history: SensorHistoryTarget(
                        id: IoTService.homeKitSensorId(accessory: reading.id,
                                                       metric: "temperature"),
                        name: reading.roomName ?? reading.accessoryName,
                        unit: "°C",
                        tint: IoTSensor.SensorType.temperature.color))
            }
        for device in smartHome.devices(in: effectiveRoom) where device.kind == .sensor {
            guard let value = device.readingValue,
                  let unit = device.readingUnit, unit.contains("°") else { continue }
            let celsius = unit.contains("F") ? (value - 32) * 5 / 9 : value
            var history: SensorHistoryTarget?
            if case .iotSensor(let sensor) = device.backing {
                history = SensorHistoryTarget(id: sensor.id.uuidString,
                                              name: sensor.name,
                                              unit: sensor.unit,
                                              tint: sensor.type.color)
            }
            rows.append(ClimateRow(id: device.id,
                                   name: device.room ?? device.name,
                                   celsius: celsius,
                                   humidity: nil,
                                   history: history))
        }
        return rows
    }

    @ViewBuilder
    private var indoorSection: some View {
        let rows = indoorRows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("sh_climate_now_home")
                    .font(AppFont.label)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                GlassCard {
                    VStack(spacing: 0) {
                        ForEach(rows) { row in
                            climateRowView(row)
                            if row.id != rows.last?.id {
                                Rectangle()
                                    .fill(Color.hairline)
                                    .frame(height: 0.5)
                                    .padding(.leading, AppSpacing.lg)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func climateRowView(_ row: ClimateRow) -> some View {
        Button {
            guard let history = row.history else { return }
            HapticFeedback.impact(.light)
            historyTarget = history
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Text(row.name)
                    .font(AppFont.scaled(14))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: AppSpacing.sm)
                if let humidity = row.humidity {
                    Text(verbatim: "\(humidity.formatted(.number.precision(.fractionLength(0))))%")
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text(verbatim: temperatureText(row.celsius))
                    .font(AppFont.metricSmall)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                if row.history != nil {
                    Image(systemName: "chevron.right")
                        .font(AppFont.scaled(12, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.35))
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(row.history == nil)
        .accessibilityLabel(Text(verbatim: row.name))
        .accessibilityValue(Text(verbatim: temperatureText(row.celsius)))
        .accessibilityHint(row.history == nil ? Text(verbatim: "") : Text("sh_climate_row_hint"))
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

/// The dial: ~48 small circles along a 270° arc (opening at the bottom),
/// lit in the climate orange up to the current fraction, the rest a faint
/// primary tint; arbitrary center content. Pure geometry — no
/// GeometryReader (the size is fixed) and only the dot colors change per
/// value, so re-renders stay cheap.
private struct SmartDottedDial<Center: View>: View {
    /// 0…1 — how far along the arc the lit fill reaches.
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
            .fill(lit ? Color.brandWarning : Color.primary.opacity(0.2))
            .frame(width: Self.dotSize, height: Self.dotSize)
            .offset(x: radius * cos(angle.radians),
                    y: radius * sin(angle.radians))
    }
}
