import SwiftUI

// MARK: - "Spațiile casei" — tab 2 (Estate OS)
//
// The full-page home of the estate's spaces, replacing the Digital Twin by
// user decision (no 3D, no maps, no twin of any kind). Same warm language
// as the approved Apple-Home direction: the property's cover photo through
// SmartHomeBackdrop, a free-floating light title, a quick row of real
// destinations (all devices, cameras, the home's health), and a 2-column
// grid of space cards — each the zone's own photo (or its kind's warm scene
// gradient + icon) with the ONE honest live subline and the honest status
// dot, all computed by the shared `SpaceCardModel` so this page, the home
// strip and the space page can never drift apart.
//
// Navigation is a page hierarchy, not a stack of sheets: tapping a card
// PUSHES SpaceDetailView onto the tab's existing NavigationStack (the one
// MainTabView owns — same `navigationDestination(item:)` pattern as
// TasksView). The trailing "+" card and the zero-spaces full-page state
// both open the shared create-space flow.

struct SpacesTabView: View {
    @Environment(PropertyService.self) private var propertyService
    @Environment(PropertyZoneService.self) private var zoneService
    @Environment(PlantService.self) private var plantService
    @Environment(PropertyElementService.self) private var elementService
    @Environment(CurrencyService.self) private var currencyService
    @Environment(AppSettings.self) private var appSettings
    @Environment(AppRouter.self) private var router

    @State private var createFlow = SpaceCreateFlow()
    /// The pushed space page's target (id, not snapshot — the destination
    /// re-resolves the live zone, the TasksView pattern).
    @State private var pushedZoneId: UUID?

    /// One nested-presentation slot — the hub's single-`sheet(item:)`
    /// discipline, so presentations never race.
    private enum ActiveSheet: String, Identifiable {
        case allDevices, health
        var id: String { rawValue }
    }

    @State private var activeSheet: ActiveSheet? = nil

    var body: some View {
        ZStack {
            SmartHomeBackdrop(photoSource: propertyService.primary?.photoUrl)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    header
                    quickRow
                    if zoneService.zones.isEmpty {
                        emptyState
                    } else {
                        grid
                    }
                    Spacer(minLength: AppSpacing.xxl)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.lg)
            }
            .environment(\.colorScheme, .dark)
        }
        // The page owns its chrome (free-floating title over the scene) —
        // the stack's system bar stays hidden, like the Tasks tab root.
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $pushedZoneId) { id in
            // Re-resolve the live zone; a space deleted mid-navigation
            // simply has no page (the pop gesture returns to the grid).
            if let zone = zoneService.zones.first(where: { $0.id == id }) {
                SpaceDetailView(zone: zone, presentation: .push)
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .allDevices:
                SmartHomeDeviceListSheet(kind: nil, room: nil)
            case .health:
                PropertyHealthDashboardView()
                    .environment(elementService)
                    .environment(currencyService)
                    .environment(appSettings)
                    .environment(propertyService)
            }
        }
        .spaceCreateAlerts(createFlow,
                           zoneService: zoneService,
                           propertyService: propertyService)
        .task(id: propertyService.primary?.id) { await loadData() }
    }

    // MARK: Header — the free-floating light title + honest count

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text("spaces_title")
                .font(AppFont.scaled(SmartHomeTheme.spaceNameSize, weight: .light))
                .kerning(SmartHomeTheme.spaceNameTracking)
                .foregroundStyle(Color.smartTextPrimary)
                .accessibilityAddTraits(.isHeader)
            if !zoneService.zones.isEmpty {
                Text("spaces_count \(zoneService.zones.count)")
                    .font(AppFont.footnote)
                    .foregroundStyle(Color.smartTextSecondary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: Quick row — three real destinations, glass chips

    private var quickRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                quickChip(icon: "square.grid.2x2", titleKey: "hub_devices") {
                    activeSheet = .allDevices
                }
                quickChip(icon: "video.fill", titleKey: "hub_cameras") {
                    // Cameras is a pushed content page (AppRoute.cameras) —
                    // the router lands it on THIS tab's stack.
                    router.navigate(to: .cameras)
                }
                quickChip(icon: "heart.text.square.fill", titleKey: "spaces_health") {
                    activeSheet = .health
                }
            }
            // Room for the chips' press scale inside the scroll clip.
            .padding(.vertical, 1)
        }
    }

    private func quickChip(icon: String, titleKey: LocalizedStringKey,
                           action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: SmartHomeTheme.chipRadius,
                                     style: .continuous)
        return Button {
            HapticFeedback.impact(.light)
            action()
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: icon)
                    .font(AppFont.scaled(12, weight: .semibold))
                    .foregroundStyle(Color.smartAmber)
                Text(titleKey)
                    .font(AppFont.scaled(13, weight: .medium))
                    .foregroundStyle(Color.smartTextPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.sm + 1)
            .background {
                shape.fill(.ultraThinMaterial)
                shape.fill(Color.smartGlassFill)
            }
            .clipShape(shape)
            .contentShape(shape)
        }
        .buttonStyle(SmartCardPressStyle())
    }

    // MARK: Grid — 2 columns of big space cards + the trailing "+" card

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: AppSpacing.md),
         GridItem(.flexible(), spacing: AppSpacing.md)]
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: AppSpacing.md) {
            ForEach(zoneService.zones) { zone in
                SpaceGridCard(
                    zone: zone,
                    subline: SpaceCardModel.subline(for: zone, plantService: plantService),
                    status: SpaceCardModel.status(for: zone)
                ) {
                    pushedZoneId = zone.id
                }
            }
            AddSpaceGridCard(isCreating: createFlow.isCreating) {
                createFlow.begin()
            }
            .disabled(createFlow.isCreating)
        }
        // Room for the cards' lift shadow inside the scroll clip.
        .padding(.vertical, AppSpacing.xs)
    }

    // MARK: Zero spaces — the honest full-page create-first state

    private var emptyState: some View {
        VStack(spacing: AppSpacing.lg) {
            ZStack {
                SmartRadialGlow(diameter: 150)
                Image(systemName: "house")
                    .font(AppFont.scaled(44, weight: .light))
                    .foregroundStyle(Color.smartAmber)
            }
            .frame(height: 110)
            .accessibilityHidden(true)
            VStack(spacing: AppSpacing.xs) {
                Text("est_create_first")
                    .font(AppFont.scaled(22, weight: .semibold))
                    .foregroundStyle(Color.smartTextPrimary)
                Text("est_create_first_caption")
                    .font(AppFont.footnote)
                    .foregroundStyle(Color.smartTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                HapticFeedback.impact(.light)
                createFlow.begin()
            } label: {
                Group {
                    if createFlow.isCreating {
                        ProgressView()
                            .tint(Color.smartInk)
                    } else {
                        Text("est_create_space")
                    }
                }
                .font(AppFont.scaled(15, weight: .semibold))
                .foregroundStyle(Color.smartInk)
                .padding(.horizontal, AppSpacing.xl)
                .padding(.vertical, AppSpacing.md)
                .background(Capsule(style: .continuous).fill(Color.smartCream))
            }
            .buttonStyle(SmartCardPressStyle())
            .disabled(createFlow.isCreating)
        }
        .frame(maxWidth: .infinity)
        // Half the space page's hero breath: pure scene above the invite.
        .padding(.top, SmartHomeTheme.spaceHeroBreath / 2)
    }

    // MARK: Data

    /// Zones dress the grid; elements feed the health dashboard behind the
    /// quick row. Plants load in MainTabView's world reload, IoT sensors
    /// self-load, and the smart-home list is computed — nothing else to ask.
    private func loadData() async {
        guard let pid = propertyService.primary?.id else { return }
        // Reload whenever the cached data belongs to another property, so a
        // property switch swaps this page's contents too.
        if zoneService.zones.first?.propertyId != pid {
            await zoneService.load(propertyId: pid)
        }
        if elementService.elements.first?.propertyId != pid {
            await elementService.load(propertyId: pid)
        }
    }
}

// MARK: - One grid card

/// A big 4:5 space card: the zone's photo filling the card (or its kind's
/// warm scene gradient + icon), the name floating over a bottom scrim, the
/// honest live subline, and the status dot (only when there is live sensor
/// truth to signal). The whole card is one button that pushes the space page.
private struct SpaceGridCard: View {
    let zone: PropertyZone
    let subline: Text?
    let status: SpaceStatus
    let onOpen: () -> Void

    /// Width/height of the card (taller than wide — the strip's cards are
    /// small chips; the tab's are the page's main event).
    private static let aspect: CGFloat = 4.0 / 5.0
    /// Photo decode target for the ~half-screen-wide card (points).
    private static let photoTargetSize: CGFloat = 360

    private var kind: SpaceKind { zone.resolvedSpaceKind }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SmartHomeTheme.widgetCardRadius,
                         style: .continuous)
    }

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            onOpen()
        } label: {
            ZStack(alignment: .bottomLeading) {
                backdrop
                caption
            }
            .aspectRatio(Self.aspect, contentMode: .fit)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(SmartHomeTheme.glassStrokeGradient, lineWidth: 1)
            }
            .shadow(color: .black.opacity(SmartHomeTheme.cardShadowOpacity),
                    radius: SmartHomeTheme.cardShadowRadius,
                    y: SmartHomeTheme.cardShadowY)
            .contentShape(shape)
        }
        .buttonStyle(SmartCardPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(status.dotColor != nil ? Text(status.titleKey) : Text(verbatim: ""))
        .accessibilityHint(Text("spaces_open_hint"))
    }

    /// The kind's scene gradient is also the photo's loading state.
    private var backdrop: some View {
        ZStack {
            kind.sceneGradient
            if let photo = zone.photoUrl, !photo.isEmpty {
                Color.clear
                    .overlay {
                        StorageImage(source: photo, targetSize: Self.photoTargetSize) { phase in
                            if case .success(let image) = phase {
                                image
                                    .resizable()
                                    .scaledToFill()
                            }
                        }
                    }
                    .clipped()
            } else {
                Image(systemName: kind.icon)
                    .font(AppFont.scaled(34, weight: .semibold))
                    .foregroundStyle(Color.smartAmber)
            }
        }
        .accessibilityHidden(true)
    }

    /// Name + honest subline over a legibility scrim (a gradient, not a card).
    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: AppSpacing.xs) {
                Text(verbatim: zone.name)
                    .font(AppFont.scaled(15, weight: .semibold))
                    .foregroundStyle(Color.smartTextPrimary)
                    .lineLimit(1)
                if let dot = status.dotColor {
                    Circle()
                        .fill(dot)
                        .frame(width: 6, height: 6)
                }
            }
            if let subline {
                subline
                    .font(AppFont.caption2)
                    .foregroundStyle(Color.smartTextSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LinearGradient(colors: [.clear, .black.opacity(0.55)],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}

// MARK: - The trailing "+" card (dashed ghost)

/// The grid's create-space entry: same footprint as a space card, drawn as
/// a warm dashed ghost — clearly an invitation, never mistakable for a
/// space that exists.
private struct AddSpaceGridCard: View {
    let isCreating: Bool
    let onCreate: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SmartHomeTheme.widgetCardRadius,
                         style: .continuous)
    }

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            onCreate()
        } label: {
            VStack(spacing: AppSpacing.sm) {
                if isCreating {
                    ProgressView()
                        .tint(Color.smartAmber)
                } else {
                    Image(systemName: "plus")
                        .font(AppFont.scaled(24, weight: .semibold))
                        .foregroundStyle(Color.smartAmber)
                }
                Text("est_create_space")
                    .font(AppFont.scaled(13, weight: .medium))
                    .foregroundStyle(Color.smartTextSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .background(shape.fill(Color.smartGlassFill))
            .overlay {
                shape.strokeBorder(Color.smartAmber.opacity(0.45),
                                   style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
            }
            .clipShape(shape)
            .contentShape(shape)
        }
        .buttonStyle(SmartCardPressStyle())
        .accessibilityLabel(Text("est_create_space"))
    }
}
