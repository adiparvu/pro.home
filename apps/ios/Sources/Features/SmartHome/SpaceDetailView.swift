import SwiftUI

// MARK: - Space detail page (Estate OS E2 — warm glass skin)
//
// The ONE template every space kind shares — presentation-agnostic: a
// sheet from the dashboard's "Domeniul" strip (the original contract,
// unchanged) or a NavigationStack push from the Spaces tab (`presentation:
// .push`, which hides the system bar and drops the tab-switching menu
// entry — from tab 2 it would route to itself). The scene leads: the zone's own photo
// through the SmartHomeBackdrop pipeline (or the kind's warm scene gradient
// when no photo exists yet), ~140pt of pure breathing scene, then the space
// NAME floating free over it — no card, no chenar — in the app's light
// typography, with a small "Domeniul · <kind>" kicker above and an honest
// status pill below.
//
// Honest states throughout (honesty law):
// - Status pill: "Fără senzori încă" with zero linked sensors; "Fără
//   semnal" when sensors exist but none has delivered a reading; "Necesită
//   atenție" when any linked sensor is genuinely alerting; "În parametri"
//   only when live readings exist and none alerts.
// - Metrics: up to 3 glass tiles from the zone's REAL linked IoT sensors
//   (linked by zone name in the IoT hub — the one sensor→zone link the app
//   has). No sensors → one empty-state glass card that says so and explains
//   where linking happens. Never a fabricated pH/EC/level tile.
// - Devices: `SmartHomeService.devices(in: zone.name)` rows (IoT sensors
//   excluded — they already ARE the metrics row); the amber pill toggle is
//   drawn only for devices with the real `.power` capability. No devices →
//   an honest empty row.
// - Kind extras: garden/greenhouse spaces list plants needing water whose
//   free-text location names THIS zone (the same name-based link sensors
//   use) — the section simply doesn't exist without such plants.
// - Toolbar menu: the SpaceKind picker persists through
//   `PropertyZoneService.setSpaceKind`, and "Deschide în Control" routes to
//   the real Digital Twin tab — both live controls, nothing dead.
//
// Live-state contract mirrors SmartDeviceSheet: the presented zone is a
// value snapshot, so the page re-resolves the live zone from
// PropertyZoneService by id on every render — a saved kind re-dresses the
// open page the moment the reload lands.

struct SpaceDetailView: View {
    /// How the page is on screen — `dismiss` handles both (sheet dismissal
    /// / stack pop); the difference is chrome and the toolbar menu's
    /// tab-switching entry.
    enum Presentation { case sheet, push }

    /// Snapshot from the presenting surface — identity + fallback only.
    let zone: PropertyZone
    var presentation: Presentation = .sheet

    @Environment(\.dismiss) private var dismiss
    @Environment(PropertyZoneService.self) private var zoneService
    @Environment(PlantService.self) private var plantService
    @Environment(AppRouter.self) private var router

    private let smartHome = SmartHomeService.shared

    /// The live projection of the presented zone; falls back to the
    /// snapshot if the zone vanished mid-presentation.
    private var live: PropertyZone {
        zoneService.zones.first { $0.id == zone.id } ?? zone
    }

    private var kind: SpaceKind { live.resolvedSpaceKind }

    /// The zone's linked IoT sensors — the shared `SpaceCardModel` match
    /// (trimmed zone name, like everywhere else the two worlds meet).
    private var zoneSensors: [IoTSensor] {
        SpaceCardModel.sensors(for: live)
    }

    /// Devices in this space across both providers, minus IoT sensors —
    /// those already render as the metrics row above.
    private var spaceDevices: [SmartDevice] {
        smartHome.devices(in: live.name).filter {
            if case .iotSensor = $0.backing { return false }
            return true
        }
    }

    /// Plants needing water located in this zone — the shared
    /// `SpaceCardModel` name-based link. Empty when plants aren't tied here.
    private var thirstyPlants: [Plant] {
        SpaceCardModel.thirstyPlants(in: live, plantService: plantService)
    }

    var body: some View {
        ZStack {
            backdrop
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    topBar
                    // The hero's breathing room: nothing but scene.
                    Spacer().frame(height: SmartHomeTheme.spaceHeroBreath)
                    hero
                    metricsSection
                    devicesSection
                    if kind == .garden || kind == .greenhouse, !thirstyPlants.isEmpty {
                        plantsSection
                    }
                    Spacer(minLength: AppSpacing.xxl)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.lg)
            }
            .environment(\.colorScheme, .dark)
        }
        // Sheet chrome (ignored when pushed).
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // Push chrome: the page owns its top bar (the glass back circle),
        // so the system navigation bar stays hidden on the stack.
        .navigationBarBackButtonHidden(true)
        .toolbar(presentation == .push ? .hidden : .automatic, for: .navigationBar)
    }

    // MARK: Backdrop — the zone's photo, else the kind's warm scene

    @ViewBuilder private var backdrop: some View {
        if let photo = live.photoUrl, !photo.isEmpty {
            SmartHomeBackdrop(photoSource: photo)
        } else {
            // Same recipe as SmartHomeBackdrop's photo-less path, tinted by
            // the kind: the scene gradient under the two static ambient
            // glows — no blur views, no animation.
            ZStack {
                kind.sceneGradient
                RadialGradient(
                    colors: [Color.smartAmber.opacity(SmartHomeTheme.ambientTopGlowOpacity),
                             .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: SmartHomeTheme.ambientTopGlowRadius)
                RadialGradient(
                    colors: [SmartHomeTheme.ambientEmber.opacity(SmartHomeTheme.ambientBottomGlowOpacity),
                             .clear],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: SmartHomeTheme.ambientBottomGlowRadius)
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
    }

    // MARK: Top bar — back + the edit menu

    private var topBar: some View {
        HStack {
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

            Spacer(minLength: AppSpacing.sm)

            Menu {
                Picker("est_kind_menu", selection: kindBinding) {
                    ForEach(SpaceKind.allCases) { option in
                        Label {
                            Text(LocalizedStringKey(option.titleKey))
                        } icon: {
                            Image(systemName: option.icon)
                        }
                        .tag(option)
                    }
                }
                if presentation == .sheet {
                    // From the home strip's sheet this jumps to tab 2 (the
                    // Spaces page). Pushed FROM that tab it would route to
                    // itself, so it doesn't exist there — no dead controls.
                    Button {
                        HapticFeedback.impact(.light)
                        dismiss()
                        router.navigate(to: .twin)
                    } label: {
                        Label("est_open_twin", systemImage: "square.split.2x2")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(Color.smartTextPrimary)
                    .frame(width: 36, height: 36)
            }
            .glassCircle()
            .accessibilityLabel(Text("est_kind_menu"))
        }
    }

    /// Selecting a kind persists it through the service extension (targeted
    /// PATCH + sanctioned reload); the open page re-dresses from `live`.
    private var kindBinding: Binding<SpaceKind> {
        Binding(
            get: { kind },
            set: { newKind in
                guard newKind != kind else { return }
                HapticFeedback.impact(.light)
                let current = live
                Task { @MainActor in
                    await zoneService.setSpaceKind(newKind, for: current,
                                                   propertyId: current.propertyId)
                }
            })
    }

    // MARK: Hero — kicker, the free-floating name, the honest status pill

    private var hero: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(verbatim: "\(String(localized: "est_domain")) · \(kind.title)")
                .font(AppFont.scaled(11, weight: .semibold))
                .kerning(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Color.smartTextSecondary)
            Text(verbatim: live.name)
                .font(AppFont.scaled(SmartHomeTheme.spaceNameSize, weight: .light))
                .kerning(SmartHomeTheme.spaceNameTracking)
                .foregroundStyle(Color.smartTextPrimary)
                // Legibility over an unpredictable photo — a shadow, not a card.
                .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            statusPill
        }
        .accessibilityElement(children: .combine)
    }

    /// The pill's honest states — the shared `SpaceCardModel` priority
    /// order (also the Spaces tab's card dot).
    private var status: SpaceStatus {
        SpaceCardModel.status(for: live)
    }

    private var statusPill: some View {
        let status = status
        return HStack(spacing: AppSpacing.xs) {
            if let dot = status.dotColor {
                Circle()
                    .fill(dot)
                    .frame(width: 6, height: 6)
            }
            Text(status.titleKey)
                .font(AppFont.scaled(12, weight: .medium))
                .foregroundStyle(Color.smartTextPrimary)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.xs)
        .background {
            Capsule(style: .continuous).fill(.ultraThinMaterial)
            Capsule(style: .continuous).fill(Color.smartGlassFill)
        }
        .clipShape(Capsule(style: .continuous))
    }

    // MARK: Metrics — up to 3 real sensor tiles, or the honest empty card

    @ViewBuilder private var metricsSection: some View {
        let sensors = Array(zoneSensors.prefix(3))
        if sensors.isEmpty {
            SmartGlassCard {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("est_no_sensors_title")
                        .font(AppFont.scaled(15, weight: .semibold))
                        .foregroundStyle(Color.smartTextPrimary)
                    Text("est_no_sensors_caption")
                        .font(AppFont.caption2)
                        .foregroundStyle(Color.smartTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack(spacing: AppSpacing.md) {
                ForEach(sensors) { sensor in
                    metricTile(sensor)
                }
            }
        }
    }

    private func metricTile(_ sensor: IoTSensor) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            // `displayValue` is the hub's own formatting: value + unit as
            // stored, "—" while no reading has arrived (never invented).
            Text(verbatim: sensor.displayValue)
                .font(AppFont.scaled(SmartHomeTheme.spaceMetricValueSize, weight: .light))
                .foregroundStyle(Color.smartTextPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(verbatim: sensor.name)
                .font(AppFont.caption2)
                .foregroundStyle(Color.smartTextSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.base)
        .smartWidgetGlass()
        .accessibilityElement(children: .combine)
    }

    // MARK: Devices — real rows or the honest empty row

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionLabel("est_devices")
            if spaceDevices.isEmpty {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: "cube")
                        .font(AppFont.headline)
                        .foregroundStyle(Color.smartTextSecondary)
                    Text("est_no_devices")
                        .font(AppFont.footnote)
                        .foregroundStyle(Color.smartTextSecondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, AppSpacing.base)
                .padding(.vertical, AppSpacing.md)
                .spaceGlassRow()
            } else {
                VStack(spacing: AppSpacing.sm) {
                    ForEach(spaceDevices) { device in
                        SpaceDeviceRow(device: device)
                    }
                }
            }
        }
    }

    // MARK: Kind extras — Plant OS chips (garden/greenhouse, real data only)

    private var plantsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionLabel("est_plants_water")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.sm) {
                    ForEach(thirstyPlants) { plant in
                        plantChip(plant)
                    }
                }
                .padding(.horizontal, AppSpacing.xxs)
            }
        }
    }

    /// Informational chip — deliberately NOT a button (no dead controls):
    /// it states which real plant is thirsty, nothing more.
    private func plantChip(_ plant: Plant) -> some View {
        let shape = RoundedRectangle(cornerRadius: SmartHomeTheme.chipRadius,
                                     style: .continuous)
        return HStack(spacing: AppSpacing.xxs) {
            Text(verbatim: plant.emoji)
                .font(AppFont.scaled(13))
            Text(verbatim: plant.name)
                .font(AppFont.scaled(13, weight: .medium))
                .foregroundStyle(Color.smartTextPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.sm)
        .background {
            shape.fill(.ultraThinMaterial)
            shape.fill(Color.smartGlassFill)
        }
        .clipShape(shape)
        .accessibilityElement(children: .combine)
    }

    private func sectionLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(AppFont.label)
            .kerning(1.1)
            .textCase(.uppercase)
            .foregroundStyle(Color.smartTextSecondary)
    }
}

// MARK: - Device row (icon, name, honest state, pill toggle)

/// One slim glass row per device: kind icon, name, an honest one-line
/// state, and the amber pill toggle only when the device genuinely has
/// `.power` — the S2 hero card's contract at row density.
private struct SpaceDeviceRow: View {
    let device: SmartDevice

    private let smartHome = SmartHomeService.shared

    /// Optimistic hold while the provider round-trip is in flight — the
    /// same discipline as the dashboard's hero cards.
    @State private var pendingOn: Bool? = nil

    private var powerBinding: Binding<Bool> {
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

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: device.kind.icon)
                .font(AppFont.headline)
                .foregroundStyle(Color.smartAmber)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: device.name)
                    .font(AppFont.scaled(15, weight: .semibold))
                    .foregroundStyle(Color.smartTextPrimary)
                    .lineLimit(1)
                stateLine
            }
            Spacer(minLength: AppSpacing.sm)
            if device.hasPower {
                SmartPillToggle(isOn: powerBinding,
                                accessibilityLabel: Text(verbatim: device.name))
                    .disabled(!device.isReachable)
            }
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .spaceGlassRow()
    }

    /// Unreachable → reported power state → the kind name. Never a guess.
    @ViewBuilder private var stateLine: some View {
        if !device.isReachable {
            Text("sh_unreachable")
                .font(AppFont.caption2)
                .foregroundStyle(Color.brandWarning)
        } else if let isOn = device.isOn {
            Text(LocalizedStringKey((pendingOn ?? isOn) ? "sh_state_on" : "sh_state_off"))
                .font(AppFont.caption2)
                .foregroundStyle(Color.smartTextSecondary)
        } else {
            Text(LocalizedStringKey(device.kind.titleKey))
                .font(AppFont.caption2)
                .foregroundStyle(Color.smartTextSecondary)
        }
    }
}

// MARK: - Slim glass row backing (shared by the rows above)

private extension View {
    func spaceGlassRow() -> some View {
        let shape = RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
        return background {
            shape.fill(.ultraThinMaterial)
            shape.fill(Color.smartGlassFill)
        }
        .clipShape(shape)
    }
}
