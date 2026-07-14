import SwiftUI
import HomeKit
import WeatherKit

// MARK: - Smart Home dashboard section (Smart Home S2.6 — Liquid Glass)
//
// The home tab's smart-home-first page, bound entirely to the S1 aggregation
// layer (`SmartHomeService` + `HomeKitService`): a room filter chip row
// (devices ∪ Digital Twin zones) ending in the "+" connect chip, a HomeKit
// scene chip row, the now-playing media card, and a two-column STAGGERED
// hero grid — per-DEVICE cards followed by the always-present
// agenda/temperature/network cards. Every card control writes real provider
// state (`setPower`); thermostats draw a mini target-temperature dial
// instead of an icon disc. Visuals are the app's native Liquid Glass
// language (adaptive glass over the mood backdrop the dashboard renders).
//
// Honest states throughout:
// - Room chips union the smart-home providers' rooms with the property's
//   Digital Twin zones, so the row exists even with zero smart devices.
// - No devices at all → the grid's FIRST slot is a "Connect HomeKit" hero
//   card styled like a device tile (never an empty grid, never mock tiles)
//   whose button triggers the real HomeKit permission flow.
// - IoT devices but HomeKit unauthorized → the cards plus a slim
//   "Connect HomeKit" row; the row disappears once authorization lands.
// - A power toggle is drawn only when the device actually has the `.power`
//   capability; sensor cards show a live reading instead.
// - The grid is ALWAYS populated: after the device tiles come the "Next up"
//   agenda card, the home-temperature dial (opens the climate page), and
//   the live network card — each backed by real data.
// - More than 6 devices in the selected room → the 6 most relevant
//   (controllable first, then passive sensors) plus a "See all" glass row
//   that opens the full device list — never an endless dashboard.

struct SmartHomeSection: View {
    /// The house agenda's next upcoming item (≥ now, next 30 days), computed
    /// by the dashboard from the same services the calendar reads.
    var nextAgendaItem: AgendaItem? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PropertyZoneService.self) private var zoneService
    @Environment(TaskService.self) private var taskService

    @State private var selectedRoom: String? = nil

    /// Set when THIS surface triggered the HomeKit connect flow — the
    /// moment authorization lands, the import wizard presents (Smart
    /// Control R1). Local by design: the hub sheet tracks its own taps,
    /// so the two surfaces can never double-present.
    @State private var awaitingConnectWizard = false

    /// Flips true on the grid's first appearance and never resets for this
    /// view's lifetime — the one-shot gate for the entrance stagger. Cards
    /// that arrive LATER (async provider loads) render with it already
    /// true, i.e. fully visible, no re-runs.
    @State private var revealCards = false

    /// Bumped after the `.task` weather probe so the dial re-renders once
    /// with whatever the probe produced (summary or recorded error) — the
    /// PropertyWeather cache lives in UserDefaults and is not observable.
    @State private var weatherProbeTick = 0

    /// What a tap presents: the tapped device's hero sheet (S3), the
    /// climate page, or the "See all" list when the room holds more devices
    /// than the dashboard shows. One optional drives `.sheet(item:)`, so
    /// the presentations can never stack or race.
    private enum ActiveSheet: Identifiable {
        case device(SmartDevice)
        case allDevices
        case climate
        case importWizard
        case rules

        var id: String {
            switch self {
            case .device(let device): "device-\(device.id)"
            case .allDevices:         "all-devices"
            case .climate:            "climate"
            case .importWizard:       "import-wizard"
            case .rules:              "rules"
            }
        }
    }

    @State private var activeSheet: ActiveSheet? = nil

    private let smartHome = SmartHomeService.shared
    private let homeKit = HomeKitService.shared
    /// Cached HomeKit indoor readings (R3) — the dial's first truth.
    private let indoorClimate = IndoorClimateStore.shared
    /// The rules engine (R5) — loaded here so the dashboard is the moment
    /// rules start evaluating; its compact row renders only when ≥1 exists.
    private let rulesStore = PropertyRulesStore.shared

    /// How many hero cards the dashboard shows before folding the rest
    /// behind the "See all" row.
    private static let maxVisibleDevices = 6

    /// Provider rooms UNIONED with the property's Digital Twin zone names —
    /// the chip row always reflects the whole home, even before the first
    /// smart device exists. Device rooms lead (they actually filter the
    /// grid); zones follow in their stored sort order, deduplicated.
    private var allRooms: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for room in smartHome.rooms where seen.insert(room).inserted {
            out.append(room)
        }
        for zone in zoneService.zones {
            let name = zone.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name).inserted else { continue }
            out.append(name)
        }
        return out
    }

    /// The selection, ignoring a room that no longer exists (its last
    /// device or zone was removed) — falls back to "All" instead of
    /// filtering the dashboard down to an empty grid.
    private var effectiveRoom: String? {
        guard let selectedRoom, allRooms.contains(selectedRoom) else { return nil }
        return selectedRoom
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            if !allRooms.isEmpty { roomChips }
            let scenes = homeKitScenes
            if !scenes.isEmpty { SmartSceneChipRow(scenes: scenes) }
            NowPlayingCard()
            heroGrid
            if scopedDevices.count > Self.maxVisibleDevices { seeAllRow }
            if smartHome.hasAnyDevice, !smartHome.homeKitAuthorized { connectHomeKitRow }
            // R5: only once at least one rule genuinely exists — never a
            // promotional slot for an empty feature.
            if !rulesStore.rules.isEmpty { rulesRow }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .device(let device):
                SmartDeviceSheet(device: device)
            case .allDevices:
                SmartHomeDeviceListSheet(kind: nil, room: effectiveRoom)
            case .climate:
                ClimateView()
            case .importWizard:
                HomeKitImportWizardSheet()
            case .rules:
                PropertyRulesView()
            }
        }
        // Indoor climate cache (R3): fill on first appearance, refresh on
        // scene re-activation — never a polling loop.
        // Rules engine (R5): load the property's rules alongside, and adopt
        // the app's TaskService so rule-created tasks land in the live list.
        .task {
            rulesStore.adopt(taskService: taskService)
            await rulesStore.loadIfNeeded()
            await indoorClimate.refreshIfStale()
            // The dial's outdoor fallback: when the launch refresh failed
            // silently (empty cache), one error-RECORDING attempt with the
            // engine's property coordinates either fills the cache or gives
            // the dial an honest failure caption. No-op while the cache is
            // fresh (1h TTL). The tick forces one re-render — the UserDefaults
            // cache is not observable, so a summary landing after first
            // render would otherwise never reach the dial.
            if let lat = AppMoodEngine.shared.latitude,
               let lon = AppMoodEngine.shared.longitude,
               !PropertyWeather.hasFreshCache {
                await PropertyWeather.refreshRecordingErrors(latitude: lat, longitude: lon)
                weatherProbeTick += 1
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // Scene-active is an R5 evaluation trigger of its own; the
            // climate refresh below feeds the engine's observation hook too.
            rulesStore.evaluateSoon()
            Task { await indoorClimate.refresh() }
        }
        // The post-connect moment (R1): authorization landing after a
        // connect tap on THIS surface presents the import wizard, and the
        // freshly reachable sensors feed the dial.
        .onChange(of: homeKit.isAuthorized) { _, authorized in
            guard authorized else { return }
            Task { await indoorClimate.refresh() }
            if awaitingConnectWizard {
                awaitingConnectWizard = false
                activeSheet = .importWizard
            }
        }
    }

    /// The connect slots' shared action: unauthorized → the real HomeKit
    /// permission flow (the wizard follows once it lands); already
    /// authorized → straight to the import wizard, so the control always
    /// does something real.
    private func connectOrImport() {
        if smartHome.homeKitAuthorized {
            activeSheet = .importWizard
        } else {
            awaitingConnectWizard = true
            smartHome.connectHomeKit()
        }
    }

    // MARK: - Room filter chips (+ the connect chip)

    /// Room name → the Digital Twin zone's stored SF Symbol, when the room
    /// corresponds to a real zone that carries one. Rooms known only to the
    /// smart-home providers have no icon anywhere — their chips honestly
    /// stay text-only rather than guessing a glyph.
    private var zoneIcons: [String: String] {
        var out: [String: String] = [:]
        for zone in zoneService.zones {
            let name = zone.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let icon = zone.icon.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !icon.isEmpty, out[name] == nil else { continue }
            out[name] = icon
        }
        return out
    }

    private var roomChips: some View {
        let icons = zoneIcons
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                GlassFilterChip(label: String(localized: "sh_room_all"),
                                isSelected: effectiveRoom == nil) {
                    select(nil)
                }
                ForEach(allRooms, id: \.self) { room in
                    GlassFilterChip(label: room,
                                    systemImage: icons[room],
                                    isSelected: effectiveRoom == room) {
                        select(room)
                    }
                }
                // The reference's trailing "+" chip — a REAL action: the
                // Connect-HomeKit flow (the import wizard follows), or the
                // wizard directly once HomeKit is already authorized.
                SmartPlusChip { connectOrImport() }
            }
            .padding(.horizontal, AppSpacing.xxs)
        }
    }

    private func select(_ room: String?) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
            selectedRoom = room
        }
    }

    // MARK: - HomeKit scenes (Smart Control R2 — the shared chip row)

    /// Every executable scene across the homes — empty (and the row absent)
    /// when HomeKit is unauthorized or no scene exists. Scenes live in ONE
    /// provider today (HomeKit); the row and its execution contract are the
    /// shared `SmartSceneChipRow`, so this surface, the space page, and the
    /// hub list can never drift apart.
    private var homeKitScenes: [HomeKitScene] {
        homeKit.scenes
    }

    // MARK: - Hero grid (staggered two-column layout, always populated)

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

    /// One grid slot: a real device tile, or one of the always-present
    /// non-device hero cards. Stable string identity keeps SwiftUI diffing
    /// cheap across aggregation rebuilds.
    private enum GridEntry: Identifiable {
        case device(SmartDevice)
        case connectHomeKit
        case nextUp
        case temperature
        case network

        var id: String {
            switch self {
            case .device(let device): "device-\(device.id)"
            case .connectHomeKit:     "connect-homekit"
            case .nextUp:             "next-up"
            case .temperature:        "temperature"
            case .network:            "network"
            }
        }

        /// Honest height estimate at the default content size, measured from
        /// each card's actual paddings/frames (card padding 14×2 everywhere):
        /// - tall device (thermostat/light): 90pt visual + 12 + 52pt toggle
        ///   row ≈ 185; compact device: 40pt visual + 12 + 52 ≈ 135
        /// - connect hero: 90pt glow + 12 + ~35pt title block ≈ 165
        /// - temperature: 90pt dial + 12 + title block/toggle row ≈ 185
        /// - next up (cream): header ~16 + 8 + 42pt big line + 8 + 13 ≈ 125
        /// - network: 48pt visual + 12 + ~37pt title block ≈ 130
        /// Only the RELATIVE weights matter — they steer which column each
        /// card lands in; the cards still take their natural heights.
        var estimatedHeight: CGFloat {
            switch self {
            case .device(let device):
                (device.kind == .thermostat || device.kind == .light) ? 185 : 135
            case .connectHomeKit: 165
            case .nextUp:         125
            case .temperature:    185
            case .network:        130
            }
        }
    }

    /// The reference's fixed rhythm: device tiles first (or, with zero
    /// devices anywhere, the Connect HomeKit hero in the first slot), then
    /// the agenda, temperature, and network cards — the grid is NEVER empty.
    private var gridEntries: [GridEntry] {
        var entries: [GridEntry] = []
        if !smartHome.hasAnyDevice { entries.append(.connectHomeKit) }
        entries += visibleDevices.map(GridEntry.device)
        entries += [.nextUp, .temperature, .network]
        return entries
    }

    /// Two top-aligned columns, height-balanced greedily: each entry (in
    /// stable order) lands in whichever column is currently shorter by the
    /// cards' honest height estimates — so mixed tall/short line-ups never
    /// leave a dead hole under one column. Cards keep their natural
    /// (deliberately varied) heights; no GeometryReader, no measurement
    /// passes. At most ~9 cards render, so plain VStacks stay cheaper than
    /// a lazy grid here. Each entry keeps its position in the ORIGINAL
    /// stable order — that index drives the one-time entrance stagger.
    private struct GridSlot: Identifiable {
        let index: Int
        let entry: GridEntry
        var id: String { entry.id }
    }

    private var heroGrid: some View {
        var left: [GridSlot] = []
        var right: [GridSlot] = []
        var leftHeight: CGFloat = 0
        var rightHeight: CGFloat = 0
        for (index, entry) in gridEntries.enumerated() {
            if leftHeight <= rightHeight {
                left.append(GridSlot(index: index, entry: entry))
                leftHeight += entry.estimatedHeight
            } else {
                right.append(GridSlot(index: index, entry: entry))
                rightHeight += entry.estimatedHeight
            }
        }
        return HStack(alignment: .top, spacing: AppSpacing.md) {
            gridColumn(left)
            gridColumn(right)
        }
        // One-time staggered entrance, once per view LIFETIME: the flag is
        // @State, so tab switches (same identity) never replay it; only a
        // fresh dashboard does. Reduce Motion reveals instantly — the flag
        // flips with no animation attached to it.
        .onAppear { revealCards = true }
    }

    private func gridColumn(_ slots: [GridSlot]) -> some View {
        VStack(spacing: AppSpacing.md) {
            ForEach(slots) { slot in
                gridCard(slot.entry)
                    .heroEntrance(revealed: revealCards,
                                  index: slot.index,
                                  reduceMotion: reduceMotion)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func gridCard(_ entry: GridEntry) -> some View {
        switch entry {
        case .device(let device):
            SmartDeviceHeroCard(device: device) {
                activeSheet = .device(device)
            }
        case .connectHomeKit:
            ConnectHomeKitHeroCard { connectOrImport() }
        case .nextUp:
            NextUpCard(item: nextAgendaItem)
        case .temperature:
            let temperature = homeTemperature
            TemperatureDialCard(celsius: temperature.celsius,
                                caption: temperature.caption,
                                thermostat: primaryThermostat) {
                activeSheet = .climate
            }
        case .network:
            NetworkStatusCard()
        }
    }

    // MARK: - Temperature sources (real, in honesty order)

    /// One indoor temperature sample with the space (or sensor) it belongs
    /// to — the dial's caption is built from these.
    private struct IndoorSample {
        let label: String
        let celsius: Double
    }

    /// Every REAL indoor temperature: the HomeKit readings cached by
    /// `IndoorClimateStore` (each tagged with its accessory's room), plus
    /// the IoT hub's degree-unit sensors. Empty means no indoor sensor has
    /// reported — never padded.
    private var indoorSamples: [IndoorSample] {
        var samples = indoorClimate.readings.map {
            IndoorSample(label: $0.roomName ?? $0.accessoryName, celsius: $0.celsius)
        }
        for sensor in indoorTemperatureSensors {
            guard let value = sensor.readingValue else { continue }
            // Normalize a Fahrenheit sensor to the app's Celsius display.
            let celsius = (sensor.readingUnit?.contains("F") == true)
                ? (value - 32) * 5 / 9 : value
            samples.append(IndoorSample(label: sensor.room ?? sensor.name,
                                        celsius: celsius))
        }
        return samples
    }

    /// The dial's truth (R3): with ≥1 indoor sensor reporting, the AVERAGE
    /// indoor temperature captioned by the per-space values (two or fewer)
    /// or the honest "media a n senzori"; with none, the outdoor Apple
    /// Weather reading captioned exactly as what it is — "Exterior ·
    /// vremea" — never presented as the house's own temperature.
    private var homeTemperature: (celsius: Double?, caption: Text) {
        let samples = indoorSamples
        if !samples.isEmpty {
            let average = samples.map(\.celsius).reduce(0, +) / Double(samples.count)
            return (average, indoorCaption(for: samples))
        }
        if let cached = PropertyWeather.cached() {
            return (cached.temp, Text("sh_temp_outdoor_weather"))
        }
        if let current = WeatherKitService.shared.currentWeather {
            return (current.temperature.converted(to: .celsius).value,
                    Text("sh_temp_outdoor_weather"))
        }
        // No sensor and no weather: when a weather fetch actually FAILED
        // (recorded by the diagnostics refresh), say so instead of the
        // bare "no reading" — same honesty as the Fundal weather row.
        if PropertyWeather.lastRefreshError != nil {
            return (nil, Text("weather_dial_fetch_failed"))
        }
        return (nil, Text("sh_temp_unavailable"))
    }

    private func indoorCaption(for samples: [IndoorSample]) -> Text {
        guard samples.count > 2 else {
            // Per-space values, real names verbatim: "Living 21,5° · Birou 19°".
            let items = samples.map {
                "\($0.label) \(Self.shortDegrees($0.celsius))"
            }
            return Text(verbatim: items.joined(separator: " · "))
        }
        return Text("sh_temp_avg_count \(samples.count)")
    }

    /// "21,5°" — locale-aware, at most one decimal (the dial's own format).
    private static func shortDegrees(_ celsius: Double) -> String {
        "\(celsius.formatted(.number.precision(.fractionLength(0...1))))°"
    }

    /// IoT sensors whose live reading is a temperature — identified by the
    /// degree unit ("°C"/"°F"), the one honest signal the model carries.
    /// (HomeKit sensors come through `IndoorClimateStore` instead, so the
    /// two sources can never double-count.)
    private var indoorTemperatureSensors: [SmartDevice] {
        smartHome.devices.filter {
            if case .homeKit = $0.backing { return false }
            return $0.kind == .sensor && $0.readingValue != nil
                && ($0.readingUnit?.contains("°") == true)
        }
    }

    /// The thermostat whose power the dial card's toggle drives — drawn only
    /// when one genuinely exists with the `.power` capability.
    private var primaryThermostat: SmartDevice? {
        smartHome.devices.first { $0.kind == .thermostat && $0.hasPower }
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
                    .foregroundStyle(Color.accentColor)
                Text("sh_see_all")
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(.primary)
                Spacer(minLength: AppSpacing.sm)
                Text("sh_device_count \(scopedDevices.count)")
                    .font(AppFont.caption2)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(AppFont.captionStrong)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .smartGlassRow()
        .accessibilityElement(children: .combine)
    }

    // MARK: - Slim rules row (Smart Control R5 — only when ≥1 rule exists)

    /// Compact entry to the rules page, mirroring the see-all row's
    /// language: title, enabled count, chevron. Rendered only when the
    /// household actually has rules — creation lives on the rules page
    /// itself (reached via the ☰ hub), never as dashboard bait.
    private var rulesRow: some View {
        let enabled = rulesStore.enabledCount
        return Button {
            HapticFeedback.impact(.light)
            activeSheet = .rules
        } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "bolt.badge.automatic")
                    .font(AppFont.headline)
                    .foregroundStyle(Color.accentColor)
                Text("rule_hub_title")
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(.primary)
                Spacer(minLength: AppSpacing.sm)
                (enabled == 1 ? Text("rule_enabled_one")
                              : Text("rule_enabled_count \(enabled)"))
                    .font(AppFont.caption2)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(AppFont.captionStrong)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .smartGlassRow()
        .accessibilityElement(children: .combine)
    }

    // MARK: - Slim "Connect HomeKit" row (IoT devices exist, HomeKit not yet authorized)

    private var connectHomeKitRow: some View {
        Button {
            HapticFeedback.impact(.light)
            connectOrImport()
        } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "homekit")
                    .font(AppFont.headline)
                    .foregroundStyle(Color.accentColor)
                Text("sh_connect_homekit")
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(.primary)
                Spacer(minLength: AppSpacing.sm)
                Image(systemName: "chevron.right")
                    .font(AppFont.captionStrong)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .smartGlassRow()
    }
}

/// The hero grid's one-time entrance: each card fades in from 8pt below,
/// `.snappy`, staggered ~35ms per card in the grid's stable order. Under
/// Reduce Motion the animation is nil — cards simply appear in place.
private extension View {
    /// Rise distance and per-card stagger delay of the one-time entrance.
    static var entranceRise: CGFloat { 8 }
    static var entranceStagger: Double { 0.035 }

    func heroEntrance(revealed: Bool, index: Int, reduceMotion: Bool) -> some View {
        opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : Self.entranceRise)
            .animation(reduceMotion
                       ? nil
                       : .snappy(duration: 0.35)
                           .delay(Double(index) * Self.entranceStagger),
                       value: revealed)
    }
}

/// Slim glass row backing (see-all / connect rows) — the card material at
/// a tighter radius, still borderless.
private extension View {
    func smartGlassRow() -> some View {
        liquidGlass(cornerRadius: AppRadius.lg)
    }
}

// MARK: - Per-device hero card

/// One large card per DEVICE (the reference's staggered tiles): the icon
/// over a soft accent radial glow — or, for thermostats with a target, a
/// mini circular dial — the device name bottom-left, an honest one-line
/// state under it, and the vertical pill toggle bottom-trailing, drawn
/// only when the device genuinely has the `.power` capability. Nothing
/// else; no dead controls.
///
/// Height staggering comes from the CONTENT: thermostat/light cards carry a
/// ~90pt visual area, plain switch/sensor cards a compact one — no fixed
/// frames, no GeometryReader, so Dynamic Type can grow every card safely.
///
/// Tapping the card BODY opens the S3 device page; the toggle keeps its
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

    /// How much of the radial glow survives when the device is OFF — the
    /// lamp is out, only an ember of the mood remains.
    private static let glowOffOpacity: Double = 0.15
    /// The big light-weight live value (brightness %, sensor reading).
    private static let heroValueSize: CGFloat = 30

    /// Tall cards (the reference's hero tiles): thermostats and lights get
    /// the ~90pt visual area; switches/outlets/sensors stay compact.
    private var isTall: Bool { device.kind == .thermostat || device.kind == .light }

    private var isOn: Bool { pendingOn ?? (device.isOn == true) }

    /// True only when the device REPORTS being off (optimistic state
    /// included) — devices without a power state (sensors) stay at full
    /// brightness; there is nothing honest to dim.
    private var isVisuallyOff: Bool { (pendingOn ?? device.isOn) == false }

    private var powerBinding: Binding<Bool> {
        Binding(
            get: { isOn },
            set: { on in
                pendingOn = on
                Task { @MainActor in
                    await smartHome.setPower(device, on: on)
                    pendingOn = nil
                }
            })
    }

    var body: some View {
        // A real Button (press micro-interaction included) instead of the
        // old bare tap gesture; inner controls (the pill toggle) keep their
        // own gestures, so flipping power never navigates.
        Button {
            HapticFeedback.impact(.light)
            onOpen()
        } label: {
            GlassCard(padding: AppSpacing.base) {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    visualArea
                        .frame(maxWidth: .infinity, alignment: isTall ? .center : .leading)

                    HStack(alignment: .bottom, spacing: AppSpacing.sm) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: device.name)
                                .font(AppFont.scaled(16, weight: .semibold))
                                .foregroundStyle(isVisuallyOff
                                                 ? AnyShapeStyle(.secondary)
                                                 : AnyShapeStyle(.primary))
                                .lineLimit(1)
                            stateLine
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        // VoiceOver path (the container below is `.contain`,
                        // so this stays its own element, as before): the
                        // title block is a button that opens the device
                        // page, while the toggle stays its own element.
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint(Text("sh_card_open_hint"))
                        .accessibilityAction { onOpen() }

                        Spacer(minLength: 0)

                        if device.hasPower {
                            SmartPillToggle(isOn: powerBinding,
                                            accessibilityLabel: Text(verbatim: device.name))
                                .disabled(!device.isReachable)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // On/off re-dress (glow, glyph, title, value) glides with
                // `.smooth`; Reduce Motion snaps instantly.
                .animation(reduceMotion ? nil : .smooth(duration: 0.35),
                           value: isVisuallyOff)
            }
        }
        .buttonStyle(SmartCardPressStyle())
        // Keep the card an accessibility CONTAINER (the pre-Button
        // contract): the title block keeps the open action, the toggle
        // stays independent — the wrapping button never swallows them.
        .accessibilityElement(children: .contain)
    }

    // MARK: Visual area — icon over the accent glow, or the thermostat mini dial

    @ViewBuilder private var visualArea: some View {
        if device.kind == .thermostat, let target = smartHome.targetTemperature(of: device) {
            thermostatDial(target)
        } else {
            ZStack {
                // OFF: the lamp is out — the glow drops to an ember and the
                // glyph dims; ON restores the full mood.
                SmartRadialGlow(diameter: isTall ? 96 : 52)
                    .opacity(isVisuallyOff ? Self.glowOffOpacity : 1)
                Image(systemName: device.kind.icon)
                    .font(AppFont.scaled(isTall ? 26 : 17, weight: .semibold))
                    .foregroundStyle(isVisuallyOff ? AnyShapeStyle(.secondary)
                                                   : AnyShapeStyle(device.kind.accent))
            }
            .frame(width: isTall ? 64 : 40, height: isTall ? 90 : 40)
            .accessibilityHidden(true)
        }
    }

    /// The reference's mini climate dial: a subtle full-circle track with a
    /// trimmed climate-orange arc marking where the commanded target sits in
    /// the 10–30 °C range, the target itself bold in the center. Read-only
    /// here — the real control lives in the S3 page a tap away.
    private func thermostatDial(_ target: Double) -> some View {
        let span = Self.targetRange.upperBound - Self.targetRange.lowerBound
        let clamped = min(Self.targetRange.upperBound,
                          max(Self.targetRange.lowerBound, target))
        let fraction = (clamped - Self.targetRange.lowerBound) / span
        return ZStack {
            Circle()
                .stroke(Color.primary.opacity(AppOpacity.tintedFill),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round))
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.brandWarning, style: StrokeStyle(lineWidth: 6, lineCap: .round))
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
            // The reference's big light-weight live value — just the real
            // number; VoiceOver still speaks the full "Brightness 72%".
            Text(verbatim: "\(percent)%")
                .font(AppFont.scaled(Self.heroValueSize, weight: .light))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .accessibilityLabel(Text("sh_state_brightness \(percent)"))
        } else if let value = device.readingValue {
            Text(verbatim: Self.readingText(value, unit: device.readingUnit))
                .font(AppFont.scaled(Self.heroValueSize, weight: .light))
                .foregroundStyle(isVisuallyOff ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .monospacedDigit()
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

// MARK: - Kind accents

/// Per-kind accent — since the Liquid Glass re-skin every kind shares the
/// app's accent color (adaptive on both mood schemes); the mapping survives
/// as one switch point should kinds ever diverge again. Internal (not
/// private) on purpose: the S3 surfaces reuse it, keeping one source of
/// truth.
extension SmartDeviceKind {
    var accent: Color { .accentColor }
}
