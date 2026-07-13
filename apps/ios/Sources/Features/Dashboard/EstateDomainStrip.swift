import SwiftUI

// MARK: - "Domeniul" estate strip (Estate OS E1)
//
// The home page's ONE new element: a horizontally scrolling row of the
// property's spaces (Digital Twin zones), between the smart-home grid and
// the widgets. Each card: the zone's photo thumbnail (or its kind's warm
// scene gradient + SF icon), the zone name, and ONE honest live line, in
// priority order —
//   1. the first linked IoT sensor's reading (value + unit as stored),
//   2. for garden/greenhouse kinds, the count of plants needing water
//      whose location names this zone,
//   3. the room's device count when devices exist there,
//   4. nothing — no invented subline.
// Tap → the SpaceDetailView sheet. The strip renders ALWAYS: with zero
// zones it shows one honest "create your first space" card instead of
// disappearing, and with zones it appends a trailing "+" chip — both open
// the same create-space alert, which writes through PropertyZoneService's
// existing `add` exactly like the hub's create-room flow does. The strip
// owns its own sheet slot (the SmartHomeSection pattern) so the
// dashboard's single DashboardSheet stays single.

struct EstateDomainStrip: View {
    @Environment(PropertyService.self) private var propertyService
    @Environment(PropertyZoneService.self) private var zoneService
    @Environment(PlantService.self) private var plantService

    @State private var selectedZone: PropertyZone?

    // Create-space flow (the hub's create-room alert pattern).
    @State private var showCreateSpace = false
    @State private var newSpaceName = ""
    @State private var isCreating = false
    /// The truthful failure of the last creation attempt, surfaced as an
    /// alert — success needs no alert; the new card appearing is the proof.
    @State private var createFailure: String? = nil

    private let smartHome = SmartHomeService.shared
    private let iot = IoTService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm + 2) {
            Text("est_domain")
                .font(AppFont.label)
                .kerning(1.1)
                .textCase(.uppercase)
                .foregroundStyle(Color.smartTextSecondary)
                .padding(.horizontal, AppSpacing.lg)
            if zoneService.zones.isEmpty {
                CreateFirstSpaceCard(isCreating: isCreating) {
                    showCreateSpace = true
                }
                .disabled(isCreating)
                .padding(.horizontal, AppSpacing.lg)
                // Match the populated strip's shadow breathing room.
                .padding(.vertical, AppSpacing.xs)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.md) {
                        ForEach(zoneService.zones) { zone in
                            SpaceCard(zone: zone, subline: subline(for: zone)) {
                                selectedZone = zone
                            }
                        }
                        AddSpaceChip(isCreating: isCreating) {
                            showCreateSpace = true
                        }
                        .disabled(isCreating)
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    // Room for the cards' lift shadow inside the scroll clip.
                    .padding(.vertical, AppSpacing.xs)
                }
            }
        }
        .sheet(item: $selectedZone) { zone in
            SpaceDetailView(zone: zone)
        }
        .alert(Text("est_create_space"), isPresented: $showCreateSpace) {
            TextField("est_space_name_placeholder", text: $newSpaceName)
            Button { createSpace() } label: { Text("hub_create") }
                .disabled(newSpaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button(role: .cancel) { newSpaceName = "" } label: { Text("Cancel") }
        }
        .alert(
            Text("est_create_space"),
            isPresented: Binding(get: { createFailure != nil },
                                 set: { if !$0 { createFailure = nil } })
        ) {
            Button(role: .cancel) {} label: { Text("OK") }
        } message: {
            Text(verbatim: createFailure ?? "")
        }
    }

    // MARK: Create a space (the hub's PropertyZone half, verbatim)

    /// Creates the space as an in-app PropertyZone through the service's
    /// existing `add` — the same payload the hub's create-room flow builds:
    /// a named zone without geometry is valid (the shape can be drawn later
    /// in the Digital Twin). `add` appends into `zones`, so the strip
    /// re-renders with the new card by itself.
    private func createSpace() {
        let name = newSpaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        newSpaceName = ""
        guard !name.isEmpty else { return }
        guard !zoneService.zones.contains(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(name) == .orderedSame
        }) else {
            createFailure = String(localized: "est_space_exists")
            return
        }
        guard let propertyId = propertyService.primary?.id else {
            createFailure = String(localized: "hub_no_property")
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
                createFailure = zoneService.error
                    ?? String(localized: "est_create_failed")
            }
        }
    }

    // MARK: The one honest subline, in priority order

    private func subline(for zone: PropertyZone) -> Text? {
        let zoneName = zone.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !zoneName.isEmpty else { return nil }

        // 1. The first linked IoT sensor with a live reading.
        if let sensor = iot.sensors.first(where: {
            $0.value != nil &&
            $0.linkedZoneName.trimmingCharacters(in: .whitespacesAndNewlines) == zoneName
        }) {
            return Text(verbatim: sensor.displayValue)
        }

        // 2. Garden/greenhouse: plants needing water whose free-text
        //    location names this zone (the same name link sensors use).
        let kind = zone.resolvedSpaceKind
        if kind == .garden || kind == .greenhouse {
            let thirsty = plantService.plantsNeedingWater.filter { plant in
                guard let location = plant.location?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                      !location.isEmpty else { return false }
                return location.compare(zoneName,
                                        options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }.count
            if thirsty > 0 { return Text("est_water_count \(thirsty)") }
        }

        // 3. Devices actually in this room (either provider).
        let deviceCount = smartHome.devices(in: zone.name).count
        if deviceCount > 0 { return Text("sh_device_count \(deviceCount)") }

        // 4. Nothing real to say — say nothing.
        return nil
    }
}

// MARK: - One space card

/// A rich chip: photo thumbnail (or kind scene + icon), the zone name, and
/// the honest subline the strip computed. The whole card is one button that
/// opens the space page, with the shared press micro-interaction.
private struct SpaceCard: View {
    let zone: PropertyZone
    let subline: Text?
    let onOpen: () -> Void

    private static let cardWidth: CGFloat = 156
    private static let thumbHeight: CGFloat = 76

    private var kind: SpaceKind { zone.resolvedSpaceKind }

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            onOpen()
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                thumbnail
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: zone.name)
                        .font(AppFont.scaled(14, weight: .semibold))
                        .foregroundStyle(Color.smartTextPrimary)
                        .lineLimit(1)
                    if let subline {
                        subline
                            .font(AppFont.caption2)
                            .foregroundStyle(Color.smartTextSecondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, AppSpacing.xxs)
            }
            .padding(AppSpacing.sm + 2)
            .frame(width: Self.cardWidth, alignment: .leading)
            .smartWidgetGlass()
        }
        .buttonStyle(SmartCardPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("sh_card_open_hint"))
    }

    private var thumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: SmartHomeTheme.chipRadius,
                                     style: .continuous)
        return ZStack {
            // The kind's scene gradient is also the photo's loading state.
            kind.sceneGradient
            if let photo = zone.photoUrl, !photo.isEmpty {
                StorageImage(source: photo, targetSize: Self.cardWidth) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: Self.cardWidth - 2 * (AppSpacing.sm + 2),
                                   height: Self.thumbHeight)
                            .clipped()
                    }
                }
            } else {
                Image(systemName: kind.icon)
                    .font(AppFont.scaled(22, weight: .semibold))
                    .foregroundStyle(Color.smartAmber)
            }
        }
        .frame(height: Self.thumbHeight)
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}

// MARK: - Zero-zones state: one honest create card

/// The strip's empty state — instead of vanishing, the section offers the
/// one real action: create the first space. Same glass chrome and press
/// micro-interaction as the space cards it will become.
private struct CreateFirstSpaceCard: View {
    let isCreating: Bool
    let onCreate: () -> Void

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            onCreate()
        } label: {
            HStack(spacing: AppSpacing.md) {
                if isCreating {
                    ProgressView()
                        .tint(Color.smartAmber)
                        .frame(width: 30)
                } else {
                    Image(systemName: "house")
                        .font(AppFont.scaled(22, weight: .semibold))
                        .foregroundStyle(Color.smartAmber)
                        .frame(width: 30)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("est_create_first")
                        .font(AppFont.scaled(14, weight: .semibold))
                        .foregroundStyle(Color.smartTextPrimary)
                    Text("est_create_first_caption")
                        .font(AppFont.caption2)
                        .foregroundStyle(Color.smartTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(AppSpacing.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .smartWidgetGlass()
        }
        .buttonStyle(SmartCardPressStyle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Populated state: the trailing "+" chip

/// A small circular glass "+" at the end of the strip — the same
/// create-space alert the empty state opens, kept discoverable once
/// spaces exist (consistent with the hub's create-room row).
private struct AddSpaceChip: View {
    let isCreating: Bool
    let onCreate: () -> Void

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            onCreate()
        } label: {
            Group {
                if isCreating {
                    ProgressView()
                        .tint(Color.smartAmber)
                } else {
                    Image(systemName: "plus")
                        .font(AppFont.scaled(17, weight: .semibold))
                        .foregroundStyle(Color.smartAmber)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(SmartCardPressStyle())
        .glassCircle()
        .padding(.horizontal, AppSpacing.xs)
        .accessibilityLabel(Text("est_create_space"))
    }
}
