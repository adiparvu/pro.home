import SwiftUI
import Network
import NetworkExtension

// MARK: - Non-device hero cards (Smart Home S2.6 — Liquid Glass)
//
// Alongside the real device tiles the grid carries the temperature dial
// (which opens the climate page); "Who's home" and the energy card live in
// their own feature files. NetworkStatusModel stays here — the live
// NWPathMonitor + SSID model the house menu's network row binds to (the
// old Wi-Fi grid card retired in IMG_8601). Every state is honest ("—",
// "Offline") rather than invented.

// MARK: - Temperature dial card

/// The circular mini dial in the climate orange: the temperature big in the
/// center of a trimmed arc, "Home temperature" beneath, and — ONLY when a
/// real thermostat exists — that thermostat's actual power pill toggle.
/// Tapping the card body opens the climate page (always available).
struct TemperatureDialCard: View {
    /// Current temperature in °C; nil renders an honest "—".
    let celsius: Double?
    /// The honest sublabel — built by the section from what the value
    /// GENUINELY is: the per-space indoor readings ("Living 21,5°"), the
    /// "media a n senzori" summary, "Exterior · vremea" when only the
    /// weather reading exists, or "no reading". Never a guessed source.
    let caption: Text
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
                        caption
                            .font(AppFont.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
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
