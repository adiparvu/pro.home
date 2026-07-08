import SwiftUI

// MARK: - Zones List — matches dark mockup (filter chips + zone rows)

struct ZonesListView: View {
    @Environment(PropertyZoneService.self) var zoneService
    @Environment(PropertyElementService.self) var elementService
    @Environment(PropertyService.self) var propertyService
    @Environment(CurrencyService.self) var currencyService
    @Environment(AppSettings.self) var appSettings
    @Environment(DocumentService.self) var documentService
    @Environment(TaskService.self) var taskService
    @Environment(AppRouter.self) var router
    @Environment(TabBarVisibility.self) private var tabBarVis

    @State private var filter: ZoneFilter = .all

    enum ZoneFilter: String, CaseIterable {
        case all       = "All"
        case general   = "General"
        case buildings = "Buildings"
        case utilities = "Utilities"

        var layer: PropertyLayer? {
            switch self {
            case .all:       return nil
            case .general:   return .property
            case .buildings: return .maintenance
            case .utilities: return .utility
            }
        }
    }

    private var filteredZones: [PropertyZone] {
        guard let layer = filter.layer else { return zoneService.zones }
        return zoneService.zones.filter { $0.layer == layer }
    }

    private func elementCount(in zone: PropertyZone) -> Int {
        elementService.elements.filter { el in
            let x = (el.positionX == 0 && el.positionY == 0) ? 0.5 : el.positionX
            let y = (el.positionX == 0 && el.positionY == 0) ? 0.5 : el.positionY
            return zone.containsImage(x: x, y: y) || el.zoneId == zone.id
        }.count
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                filterChipsRow
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.base)

                if filteredZones.isEmpty {
                    emptyState
                        .padding(.top, 60)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredZones) { zone in
                            NavigationLink {
                                ZoneDetailView(zone: zone)
                                    .environment(elementService)
                                    .environment(taskService)
                                    .environment(currencyService)
                                    .environment(appSettings)
                                    .environment(documentService)
                                    .environment(router)
                                    .environment(zoneService)
                            } label: {
                                ZoneListRow(
                                    zone: zone,
                                    elementCount: elementCount(in: zone)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                }

                Spacer(minLength: 120)
            }
            .padding(.top, AppSpacing.sm)
            .trackTabScroll()
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Zones")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 10) {
                    Text("\(filteredZones.count)")
                        .font(AppFont.captionEmphasis)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.regularMaterial, in: Capsule())

                    Button {
                        HapticFeedback.impact(.light)
                        router.selectedTab = .digitalTwin
                    } label: {
                        Image(systemName: "map.fill")
                            .font(AppFont.subheadline)
                            .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .glassCircle()
                    .accessibilityLabel("Open Digital Twin")
                }
            }
        }
    }

    // MARK: - Filter chips

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ZoneFilter.allCases, id: \.self) { f in
                    CategoryFilterChip(label: LocalizedStringKey(f.rawValue), isActive: filter == f) {
                        withAnimation(.spring(response: 0.3)) { filter = f }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        EmptyStateView(
            icon: "square.stack.3d.up.slash",
            title: "No zones",
            message: "Open the Digital Twin to draw your first zone"
        )
    }
}

// MARK: - Zone List Row

struct ZoneListRow: View {
    let zone: PropertyZone
    let elementCount: Int

    private var healthLabel: String {
        switch zone.healthScore {
        case 90...100: return String(localized: "Excellent")
        case 70..<90:  return String(localized: "Good")
        case 50..<70:  return String(localized: "Fair")
        default:       return String(localized: "Poor")
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            // Icon circle
            ZStack {
                Circle()
                    .fill(zone.tint.opacity(0.18))
                    .frame(width: 46, height: 46)
                Image(systemName: zone.icon)
                    .font(AppFont.scaled(19, weight: .semibold))
                    .foregroundStyle(zone.tint)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(zone.name)
                    .font(AppFont.subheadline)
                    .foregroundStyle(.primary)
                Text(elementCount == 1 ? "1 item" : "\(elementCount) items")
                    .font(AppFont.scaled(12))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
            }

            Spacer()

            // Health badge
            Text(LocalizedStringKey(healthLabel))
                .font(AppFont.label)
                .foregroundStyle(zone.healthColor)
                .padding(.horizontal, 9)
                .padding(.vertical, AppSpacing.xxs)
                .background(zone.healthColor.opacity(0.15), in: Capsule())

            Image(systemName: "chevron.right")
                .font(AppFont.label)
                .foregroundStyle(Color.primary.opacity(0.25))
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, 13)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }
}
