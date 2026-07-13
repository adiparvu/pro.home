import SwiftUI
import Network
import NetworkExtension

// MARK: - Non-device hero cards (Smart Home S2.6 — Liquid Glass)
//
// The grid is never empty: alongside the real device tiles it carries the
// alarm-style "Next up" card (the house agenda's next deadline), the
// temperature dial (which opens the climate page), and a compact glass
// connectivity card. Each one binds to REAL data — the agenda aggregator,
// an actual indoor sensor / the property's Apple Weather reading, and
// NWPathMonitor — and states are always honest ("All clear", "—",
// "Offline") rather than invented. Styling is the app's native adaptive
// glass language over the mood backdrop.

// MARK: - Connect HomeKit hero card (no devices from any provider)

/// The empty state's first grid slot, styled exactly like a device card:
/// accent-glow icon, short title/subtitle (sized so the Romanian strings
/// never wrap mid-word again), and a glass capsule that triggers the REAL
/// HomeKit permission flow.
struct ConnectHomeKitHeroCard: View {
    private let smartHome = SmartHomeService.shared

    var body: some View {
        GlassCard(padding: AppSpacing.base) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                ZStack {
                    SmartRadialGlow(diameter: 96)
                    Image(systemName: "lightbulb.fill")
                        .font(AppFont.scaled(28, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(height: 90)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityHidden(true)

                HStack(alignment: .bottom, spacing: AppSpacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("sh_connect_title_short")
                            .font(AppFont.scaled(16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text("sh_connect_homekit")
                            .font(AppFont.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }

                    Spacer(minLength: 0)

                    Button {
                        HapticFeedback.impact(.light)
                        smartHome.connectHomeKit()
                    } label: {
                        Text("sh_connect_start")
                            .font(AppFont.captionStrong)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(width: 72)
                            .padding(.vertical, AppSpacing.xs)
                            .mediaGlass(in: Capsule(), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("sh_connect_homekit"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - "Next up" alarm-style card (house agenda)

/// The alarm-style tile, backed by the REAL house agenda: the next
/// upcoming deadline within 30 days, its time (today, timed) or date big
/// in rounded type, the item's own title beneath. No upcoming item → an
/// honest "All clear"; the card never disappears.
struct NextUpCard: View {
    /// The next agenda item at/after now, computed by the dashboard from the
    /// same services the calendar reads (nil = nothing in the next 30 days).
    let item: AgendaItem?

    @Environment(AppSettings.self) private var appSettings

    var body: some View {
        GlassCard(padding: AppSpacing.base) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: item == nil ? "checkmark.circle.fill" : "alarm.fill")
                        .font(AppFont.captionStrong)
                        .foregroundStyle(.secondary)
                    Text("sh_next_up")
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                if let item {
                    Text(verbatim: bigText(for: item))
                        .font(AppFont.scaled(36, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(verbatim: item.title)
                        .font(AppFont.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("sh_all_clear")
                        .font(AppFont.scaled(22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("sh_all_clear_subtitle")
                        .font(AppFont.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    /// Today + a wall-clock time → the time ("14:30"); anything else → the
    /// short date ("Jul 14" / "14 iul."), in the APP's locale, not the device's.
    private func bigText(for item: AgendaItem) -> String {
        if item.hasTime, Calendar.current.isDateInToday(item.date) {
            return item.date.formatted(
                Date.FormatStyle(date: .omitted, time: .shortened)
                    .locale(appSettings.appLocale))
        }
        return item.date.formatted(
            Date.FormatStyle.dateTime.day().month(.abbreviated)
                .locale(appSettings.appLocale))
    }
}

// MARK: - Temperature dial card

/// Where the temperature reading genuinely comes from — the card's sublabel
/// says so, always honestly.
enum HomeTemperatureSource {
    /// A real indoor IoT temperature sensor.
    case indoor
    /// The property's Apple Weather current temperature.
    case outdoor
    /// No reading available from anywhere.
    case unavailable

    var labelKey: LocalizedStringKey {
        switch self {
        case .indoor:      "sh_temp_inside"
        case .outdoor:     "sh_temp_outside"
        case .unavailable: "sh_temp_unavailable"
        }
    }
}

/// The circular mini dial in the climate orange: the temperature big in the
/// center of a trimmed arc, "Home temperature" beneath, and — ONLY when a
/// real thermostat exists — that thermostat's actual power pill toggle.
/// Tapping the card body opens the climate page (always available).
struct TemperatureDialCard: View {
    /// Current temperature in °C; nil renders an honest "—".
    let celsius: Double?
    let source: HomeTemperatureSource
    /// A real thermostat with the `.power` capability, when one exists —
    /// unlocks the toggle (its live power state, written via the provider).
    let thermostat: SmartDevice?
    /// Invoked on a body tap — opens the climate page.
    let onOpen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let smartHome = SmartHomeService.shared

    /// Optimistic toggle state while the provider write is in flight —
    /// mirrors `SmartDeviceHeroCard`'s contract.
    @State private var pendingOn: Bool? = nil

    /// Display range the decorative arc maps over (indoor/outdoor °C).
    private static let dialRange: ClosedRange<Double> = -10...40

    /// The empty dial ring: a faint warm gradient instead of dead gray.
    private static let emptyDialGradient = LinearGradient(
        colors: [Color.brandWarning.opacity(0.30),
                 Color.primary.opacity(AppOpacity.subtleFill)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        // A real Button (press micro-interaction included) instead of the
        // old bare tap gesture; the pill toggle inside keeps its own
        // gesture, so flipping power never accidentally navigates.
        Button {
            HapticFeedback.impact(.light)
            onOpen()
        } label: {
            cardBody
        }
        .buttonStyle(SmartCardPressStyle())
        .accessibilityElement(children: .contain)
    }

    private var cardBody: some View {
        GlassCard(padding: AppSpacing.base) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                dial
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack(alignment: .bottom, spacing: AppSpacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("sh_home_temperature")
                            .font(AppFont.scaled(16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(source.labelKey)
                            .font(AppFont.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    // VoiceOver path to the tap gesture below: the title
                    // block is the button that opens the climate page,
                    // while the pill toggle stays its own element.
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(Text("sh_card_open_hint"))
                    .accessibilityAction { onOpen() }

                    Spacer(minLength: 0)

                    if let thermostat {
                        SmartPillToggle(isOn: powerBinding(for: thermostat),
                                        accessibilityLabel: Text(verbatim: thermostat.name))
                            .disabled(!thermostat.isReachable)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Dial

    private var dial: some View {
        ZStack {
            if celsius == nil {
                // Honest empty state: a faint gradient ring with a
                // thermometer glyph — the "no reading" caption below keeps
                // telling the truth.
                Circle()
                    .stroke(Self.emptyDialGradient,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round))
                Image(systemName: "thermometer.medium")
                    .font(AppFont.scaled(22, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else {
                Circle()
                    .stroke(Color.primary.opacity(AppOpacity.tintedFill),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round))
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Color.brandWarning, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: fraction)
                Text(verbatim: temperatureText)
                    .font(AppFont.scaled(22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, AppSpacing.sm)
            }
        }
        .frame(width: 84, height: 84)
        .padding(.vertical, 3)
        .accessibilityElement()
        .accessibilityLabel(Text("sh_home_temperature"))
        .accessibilityValue(celsius == nil
            ? Text("sh_temp_unavailable")
            : Text(verbatim: temperatureText))
    }

    private var fraction: Double {
        guard let celsius else { return 0 }
        let span = Self.dialRange.upperBound - Self.dialRange.lowerBound
        let clamped = min(Self.dialRange.upperBound,
                          max(Self.dialRange.lowerBound, celsius))
        return (clamped - Self.dialRange.lowerBound) / span
    }

    /// "21.5°" — locale-aware, at most one decimal; "—" when unavailable.
    private var temperatureText: String {
        guard let celsius else { return "—" }
        return "\(celsius.formatted(.number.precision(.fractionLength(0...1))))°"
    }

    private func powerBinding(for device: SmartDevice) -> Binding<Bool> {
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
}

// MARK: - Network connectivity card

/// Live path state from `NWPathMonitor`. The monitor runs for the model's
/// lifetime (it cannot be restarted after `cancel()`, so start/stop churn on
/// scroll is avoided by design) and is cancelled on deinit.
@MainActor
@Observable
final class NetworkStatusModel {
    enum Status {
        case wifi, cellular, wired, connected, offline

        var labelKey: LocalizedStringKey {
            switch self {
            case .wifi:      "sh_net_wifi"
            case .cellular:  "sh_net_cellular"
            case .wired:     "sh_net_wired"
            case .connected: "sh_net_connected"
            case .offline:   "sh_net_offline"
            }
        }

        var isOnline: Bool { self != .offline }
    }

    private(set) var status: Status = .offline
    /// The joined Wi-Fi's real name, when the system discloses it (needs the
    /// wifi-info entitlement + precise location authorization). Never guessed:
    /// nil simply falls back to the generic "Wi-Fi" label.
    private(set) var ssid: String?

    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let status: Status
            if path.status == .satisfied {
                if path.usesInterfaceType(.wifi)               { status = .wifi }
                else if path.usesInterfaceType(.cellular)      { status = .cellular }
                else if path.usesInterfaceType(.wiredEthernet) { status = .wired }
                else                                           { status = .connected }
            } else {
                status = .offline
            }
            Task { @MainActor [weak self] in
                self?.status = status
                self?.refreshSSID(for: status)
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
    }

    private func refreshSSID(for status: Status) {
        guard status == .wifi else { ssid = nil; return }
        NEHotspotNetwork.fetchCurrent { [weak self] network in
            let name = network?.ssid
            Task { @MainActor [weak self] in self?.ssid = name }
        }
    }

    deinit { monitor.cancel() }
}

/// Compact glass Wi-Fi tile: accent-tinted icon, "Network" title, and the
/// LIVE connection state with a green/red dot. On Wi-Fi the real SSID shows
/// when the system discloses it — a name is never invented.
struct NetworkStatusCard: View {
    @State private var model = NetworkStatusModel()

    var body: some View {
        GlassCard(padding: AppSpacing.base) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                // Slightly more presence than the old 40pt disc: a bigger
                // glow and glyph so the card holds its own in the balanced
                // grid without inventing extra data.
                ZStack {
                    SmartRadialGlow(diameter: 64)
                    Image(systemName: model.status.isOnline ? "wifi" : "wifi.slash")
                        .font(AppFont.scaled(20, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("sh_network")
                        .font(AppFont.scaled(16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    HStack(spacing: AppSpacing.xs) {
                        Circle()
                            .fill(model.status.isOnline ? Color.brandSuccess : Color.brandDanger)
                            .frame(width: 7, height: 7)
                        if model.status == .wifi, let ssid = model.ssid, !ssid.isEmpty {
                            Text(verbatim: ssid)
                                .font(AppFont.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text(model.status.labelKey)
                                .font(AppFont.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
