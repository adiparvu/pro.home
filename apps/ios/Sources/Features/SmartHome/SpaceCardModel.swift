import SwiftUI
import Observation

// MARK: - Shared space-card truth (Estate OS)
//
// The ONE source for what the estate surfaces SAY about a space, so the
// home strip (EstateDomainStrip), the Spaces tab (SpacesTabView) and the
// space page (SpaceDetailView) can never drift apart:
// - the zone's linked IoT sensors (linked by zone NAME in the IoT hub —
//   the one sensor→zone link the app has),
// - the one honest live subline, in priority order,
// - the honest status (the space page's pill, the grid card's dot),
// - the create-space flow (the hub's create-room PropertyZone half).
// Everything here reads REAL data or says nothing — the honesty law.

// MARK: - Status

/// The honest live status of a space, computed from its REAL linked
/// sensors only: no sensors → say so; sensors but no reading → "no
/// signal"; any live alert → attention; live readings, none alerting → ok.
enum SpaceStatus {
    case ok, attention, noSignal, noSensors

    var titleKey: LocalizedStringKey {
        switch self {
        case .ok:        "est_status_ok"
        case .attention: "est_status_attention"
        case .noSignal:  "est_status_no_signal"
        case .noSensors: "est_status_no_sensors"
        }
    }

    /// The status dot's color — nil when there is nothing live to signal
    /// (no sensors / no readings), so surfaces never draw an empty promise.
    var dotColor: Color? {
        switch self {
        case .attention:            Color.brandWarning
        case .ok:                   Color.smartAmber
        case .noSignal, .noSensors: nil
        }
    }
}

// MARK: - Live facts per zone

@MainActor
enum SpaceCardModel {
    /// The zone's linked IoT sensors — sensors carry the zone NAME (set in
    /// the IoT hub), so the match is the trimmed name, like everywhere else
    /// the two worlds meet.
    static func sensors(for zone: PropertyZone) -> [IoTSensor] {
        let name = zone.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return [] }
        return IoTService.shared.sensors.filter {
            $0.linkedZoneName.trimmingCharacters(in: .whitespacesAndNewlines) == name
        }
    }

    /// The pill/dot states, in priority order (SpaceDetailView's contract).
    static func status(for zone: PropertyZone) -> SpaceStatus {
        let sensors = sensors(for: zone)
        if sensors.isEmpty { return .noSensors }
        if sensors.contains(where: \.isLiveAlerting) { return .attention }
        if sensors.allSatisfy({ $0.value == nil }) { return .noSignal }
        return .ok
    }

    /// Plants needing water whose free-text location names this zone
    /// (case/diacritic-insensitive) — the same name-based link the IoT
    /// sensors use. Empty when plants aren't tied to this space.
    static func thirstyPlants(in zone: PropertyZone,
                              plantService: PlantService) -> [Plant] {
        let name = zone.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return [] }
        return plantService.plantsNeedingWater.filter { plant in
            guard let location = plant.location?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !location.isEmpty else { return false }
            return location.compare(name,
                                    options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    /// The ONE honest subline under a space card's name, in priority order:
    ///   1. the first linked IoT sensor's live reading (value + unit as stored),
    ///   2. garden/greenhouse: the count of plants needing water here,
    ///   3. the room's device count when devices exist there,
    ///   4. nothing — no invented subline.
    static func subline(for zone: PropertyZone,
                        plantService: PlantService) -> Text? {
        let zoneName = zone.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !zoneName.isEmpty else { return nil }

        // 1. The first linked IoT sensor with a live reading.
        if let sensor = IoTService.shared.sensors.first(where: {
            $0.value != nil &&
            $0.linkedZoneName.trimmingCharacters(in: .whitespacesAndNewlines) == zoneName
        }) {
            return Text(verbatim: sensor.displayValue)
        }

        // 2. Garden/greenhouse: plants needing water located in this zone.
        let kind = zone.resolvedSpaceKind
        if kind == .garden || kind == .greenhouse {
            let thirsty = thirstyPlants(in: zone, plantService: plantService).count
            if thirsty > 0 { return Text("est_water_count \(thirsty)") }
        }

        // 3. Devices actually in this room (either provider).
        let deviceCount = SmartHomeService.shared.devices(in: zone.name).count
        if deviceCount > 0 { return Text("sh_device_count \(deviceCount)") }

        // 4. Nothing real to say — say nothing.
        return nil
    }
}

// MARK: - Create-space flow (shared by the strip and the Spaces tab)

/// The create-space alert flow: prompt for a name, validate against the
/// existing zones, then write through `PropertyZoneService.add` — the same
/// payload the hub's create-room flow builds (a named zone without geometry
/// is valid). `add` appends into `zones`, so every surface re-renders with
/// the new card by itself. Success needs no alert; only a truthful failure
/// is surfaced.
@MainActor
@Observable
final class SpaceCreateFlow {
    /// The name-prompt alert's presentation flag.
    var isPrompting = false
    /// The draft name typed into the prompt.
    var draftName = ""
    /// True while the round-trip is in flight (drives spinners, disables
    /// the entry controls).
    var isCreating = false
    /// The truthful failure of the last creation attempt, surfaced as an
    /// alert — nil when there is nothing honest to report.
    var failure: String? = nil

    func begin() { isPrompting = true }

    func create(zoneService: PropertyZoneService, propertyService: PropertyService) {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        draftName = ""
        guard !name.isEmpty else { return }
        guard !zoneService.zones.contains(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(name) == .orderedSame
        }) else {
            failure = String(localized: "est_space_exists")
            return
        }
        guard let propertyId = propertyService.primary?.id else {
            failure = String(localized: "hub_no_property")
            return
        }
        isCreating = true
        Task { @MainActor in
            defer { isCreating = false }
            let now = ISODate.string(from: Date())
            let payload = NewPropertyZone(
                propertyId: propertyId,
                name: name,
                icon: "door.left.hand.closed",
                colorHex: PropertyLayer.property.color.hexString(),
                layer: PropertyLayer.property.rawValue,
                healthScore: 100,
                polygon: [],
                sortOrder: zoneService.zones.count,
                createdAt: now,
                updatedAt: now)
            if await zoneService.add(payload) != nil {
                HapticFeedback.success()
            } else {
                HapticFeedback.error()
                failure = zoneService.error
                    ?? String(localized: "est_create_failed")
            }
        }
    }
}

// MARK: - The flow's two alerts, as one modifier

/// Installs the name prompt + the truthful failure alert for a
/// `SpaceCreateFlow` — one modifier so the strip and the tab present the
/// exact same flow.
private struct SpaceCreateAlerts: ViewModifier {
    @Bindable var flow: SpaceCreateFlow
    let zoneService: PropertyZoneService
    let propertyService: PropertyService

    func body(content: Content) -> some View {
        content
            .alert(Text("est_create_space"), isPresented: $flow.isPrompting) {
                TextField("est_space_name_placeholder", text: $flow.draftName)
                Button {
                    flow.create(zoneService: zoneService, propertyService: propertyService)
                } label: { Text("hub_create") }
                    .disabled(flow.draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(role: .cancel) { flow.draftName = "" } label: { Text("Cancel") }
            }
            .alert(
                Text("est_create_space"),
                isPresented: Binding(get: { flow.failure != nil },
                                     set: { if !$0 { flow.failure = nil } })
            ) {
                Button(role: .cancel) {} label: { Text("OK") }
            } message: {
                Text(verbatim: flow.failure ?? "")
            }
    }
}

extension View {
    /// The shared create-space alerts (name prompt + honest failure).
    func spaceCreateAlerts(_ flow: SpaceCreateFlow,
                           zoneService: PropertyZoneService,
                           propertyService: PropertyService) -> some View {
        modifier(SpaceCreateAlerts(flow: flow,
                                   zoneService: zoneService,
                                   propertyService: propertyService))
    }
}
