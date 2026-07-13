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
// Tap → the SpaceDetailView sheet. The presenting DashboardView renders
// this strip ONLY when zones exist; zero zones → the home page is
// untouched. The strip owns its own sheet slot (the SmartHomeSection
// pattern) so the dashboard's single DashboardSheet stays single.

struct EstateDomainStrip: View {
    @Environment(PropertyZoneService.self) private var zoneService
    @Environment(PlantService.self) private var plantService

    @State private var selectedZone: PropertyZone?

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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.md) {
                    ForEach(zoneService.zones) { zone in
                        SpaceCard(zone: zone, subline: subline(for: zone)) {
                            selectedZone = zone
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                // Room for the cards' lift shadow inside the scroll clip.
                .padding(.vertical, AppSpacing.xs)
            }
        }
        .sheet(item: $selectedZone) { zone in
            SpaceDetailView(zone: zone)
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
