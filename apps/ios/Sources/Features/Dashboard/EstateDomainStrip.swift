import SwiftUI

// MARK: - "Domeniul" estate strip (Estate OS E1)
//
// The home page's ONE new element: a horizontally scrolling row of the
// property's spaces (Digital Twin zones), between the smart-home grid and
// the widgets. Each card: the zone's photo thumbnail (or its kind's tinted
// scene wash + SF icon), the zone name, and ONE honest live line, in
// priority order —
//   1. the first linked IoT sensor's reading (value + unit as stored),
//   2. for garden/greenhouse kinds, the count of plants needing water
//      whose location names this zone,
//   3. the room's device count when devices exist there,
//   4. nothing — no invented subline.
// Tap → the SpaceDetailView sheet. The strip renders ALWAYS: with zero
// zones it shows one honest "create your first space" card instead of
// disappearing, and with zones it appends a trailing "+" chip — both open
// the shared create-space flow (`SpaceCreateFlow`), which writes through
// PropertyZoneService's existing `add` exactly like the hub's create-room
// flow does. The subline/status logic lives in the shared `SpaceCardModel`
// so this strip and the Spaces tab can never drift apart. The strip owns
// its own sheet slot (the SmartHomeSection pattern) so the dashboard's
// single DashboardSheet stays single.

struct EstateDomainStrip: View {
    @Environment(PropertyService.self) private var propertyService
    @Environment(PropertyZoneService.self) private var zoneService
    @Environment(PlantService.self) private var plantService

    @State private var selectedZone: PropertyZone?

    // Create-space flow (the hub's create-room alert pattern, shared with
    // the Spaces tab).
    @State private var createFlow = SpaceCreateFlow()

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm + 2) {
            Text("est_domain")
                .font(AppFont.label)
                .kerning(1.1)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.horizontal, AppSpacing.lg)
            if zoneService.zones.isEmpty {
                CreateFirstSpaceCard(isCreating: createFlow.isCreating) {
                    createFlow.begin()
                }
                .disabled(createFlow.isCreating)
                .padding(.horizontal, AppSpacing.lg)
                // Match the populated strip's shadow breathing room.
                .padding(.vertical, AppSpacing.xs)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.md) {
                        ForEach(zoneService.zones) { zone in
                            SpaceCard(zone: zone,
                                      subline: SpaceCardModel.subline(for: zone,
                                                                      plantService: plantService)) {
                                selectedZone = zone
                            }
                        }
                        AddSpaceChip(isCreating: createFlow.isCreating) {
                            createFlow.begin()
                        }
                        .disabled(createFlow.isCreating)
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
        .spaceCreateAlerts(createFlow,
                           zoneService: zoneService,
                           propertyService: propertyService)
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
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let subline {
                        subline
                            .font(AppFont.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, AppSpacing.xxs)
            }
            .padding(AppSpacing.sm + 2)
            .frame(width: Self.cardWidth, alignment: .leading)
            .liquidGlass(cornerRadius: AppRadius.xl)
        }
        .buttonStyle(SmartCardPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("spaces_open_hint"))
    }

    private var thumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: AppRadius.md,
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
                    .foregroundStyle(kind.accent)
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
                        .frame(width: 30)
                } else {
                    Image(systemName: "house")
                        .font(AppFont.scaled(22, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 30)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("est_create_first")
                        .font(AppFont.scaled(14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("est_create_first_caption")
                        .font(AppFont.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(AppSpacing.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .liquidGlass(cornerRadius: AppRadius.xl)
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
                } else {
                    Image(systemName: "plus")
                        .font(AppFont.scaled(17, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
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
