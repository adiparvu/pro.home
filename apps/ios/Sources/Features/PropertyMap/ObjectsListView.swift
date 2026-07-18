// Unreferenced since tab 2 became Spațiile casei (user decision) — safe to delete in a cleanup pass.
import SwiftUI

// MARK: - Objects List — matches dark mockup (filter chips + object rows)

struct ObjectsListView: View {
    @Environment(PropertyElementService.self) var elementService
    @Environment(PropertyZoneService.self) var zoneService
    @Environment(CurrencyService.self) var currencyService
    @Environment(AppSettings.self) var appSettings
    @Environment(DocumentService.self) var documentService
    @Environment(TaskService.self) var taskService
    @Environment(PropertyService.self) var propertyService

    @State private var filter: ObjectFilter = .all
    @State private var favoritesOnly = false
    @State private var selectedElement: PropertyElement?
    @State private var filterMode: FilterMode = .categories
    @State private var categoryFilter: ElementCategory? = nil
    @State private var searchText = ""

    enum FilterMode: String, CaseIterable { case categories, layers }

    enum ObjectFilter: String, CaseIterable {
        case all       = "All"
        case garden    = "Garden"
        case structure = "Buildings"
        case utilities = "Utilities"
        case smartHome = "Smart Home"

        var layer: PropertyLayer? {
            switch self {
            case .all:       return nil
            case .garden:    return .property
            case .structure: return .maintenance
            case .utilities: return .utility
            case .smartHome: return .smartHome
            }
        }
    }

    private var filteredElements: [PropertyElement] {
        var items = elementService.elements
        if favoritesOnly { items = items.filter { $0.isFavorite } }
        switch filterMode {
        case .layers:
            if let layer = filter.layer { items = items.filter { $0.layer == layer } }
        case .categories:
            if let cat = categoryFilter { items = items.filter { $0.elementType.category == cat } }
        }
        let q = searchText.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            items = items.filter { el in
                let fields = [el.name, el.brand, el.model, el.serialNumber, el.notes,
                              el.elementType.displayName, zoneName(for: el),
                              String(el.healthScore)]
                    .compactMap { $0 } + el.tags
                return fields.contains { $0.matchesSearch(q) }
            }
        }
        return items
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // The scrolling chip row (favorites + mode toggle + per-mode
                // chips) folded into ONE aggregated glass filter (IMG_8540),
                // trailing where the row used to sit.
                HStack {
                    Spacer(minLength: 0)
                    filterButton
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.base)

                if filteredElements.isEmpty {
                    emptyState
                        .padding(.top, 60)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredElements) { element in
                            ObjectListRow(
                                element: element,
                                zoneName: zoneName(for: element),
                                onToggleFavorite: {
                                    Task { await elementService.toggleFavorite(elementId: element.id) }
                                    HapticFeedback.selection()
                                }
                            )
                            .onTapGesture {
                                HapticFeedback.impact(.light)
                                selectedElement = element
                            }
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                }

                Spacer(minLength: 120)
            }
            .padding(.top, AppSpacing.sm)
        }
        // Smart-home warm skin: the blurred cover-photo backdrop with the
        // content resolving in the dark scheme, like every twin surface.
        .environment(\.colorScheme, .dark)
        .background { SmartHomeBackdrop(photoSource: propertyService.primary?.photoUrl) }
        .navigationTitle("Objects")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search name, brand, serial…")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("\(filteredElements.count)")
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(Color.smartTextSecondary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .sheet(item: $selectedElement) { element in
            PropertyElementDetailView(element: element)
                .environment(elementService)
                .environment(currencyService)
                .environment(appSettings)
                .environment(documentService)
                .environment(taskService)
        }
        .presentationBackground(.thinMaterial)
        // Switching vocabulary clears the other mode's narrowing (as the old
        // toggle did), so no hidden filter keeps constraining the list.
        .onChange(of: filterMode) {
            filter = .all
            categoryFilter = nil
        }
    }

    // MARK: - Aggregated filter (one glass circle, IMG_8540)

    /// Any hosted filter away from its default — favorites, or the current
    /// mode's narrowing. The other mode's state is always default (reset on
    /// every mode switch), so it can't secretly light the dot.
    private var hasActiveFilter: Bool {
        favoritesOnly || (filterMode == .categories ? categoryFilter != nil : filter != .all)
    }

    private var filterButton: some View {
        GlassFilterButton(isActive: hasActiveFilter) {
            GlassFilterToggleRow(icon: "star",
                                 title: String(localized: "Favorites"),
                                 isOn: $favoritesOnly)
            GlassFilterSectionDivider()
            GlassFilterSection(
                title: "Filter by",
                options: [
                    GlassPickerOption(value: FilterMode.categories,
                                      icon: "square.grid.2x2.fill",
                                      title: String(localized: "Categories")),
                    GlassPickerOption(value: FilterMode.layers,
                                      icon: "square.3.layers.3d",
                                      title: String(localized: "Layers"))
                ],
                selection: $filterMode)
            GlassFilterSectionDivider()
            // The popover content is a ViewBuilder, so only the current
            // mode's vocabulary renders — mirroring the old chip row.
            if filterMode == .categories {
                GlassFilterSection(title: "Category",
                                   options: categoryOptions,
                                   selection: $categoryFilter)
            } else {
                GlassFilterSection(title: "Layer",
                                   options: layerOptions,
                                   selection: $filter)
            }
        }
    }

    /// "All" + the nine type groups; the Optional value keeps "no category
    /// narrowing" a real, selectable state.
    private var categoryOptions: [GlassPickerOption<ElementCategory?>] {
        [GlassPickerOption<ElementCategory?>(value: nil, icon: "square.grid.2x2",
                                             title: String(localized: "All"))]
            + ElementCategory.allCases.map {
                GlassPickerOption<ElementCategory?>(value: $0, icon: $0.icon,
                                                    title: $0.displayName)
            }
    }

    private var layerOptions: [GlassPickerOption<ObjectFilter>] {
        ObjectFilter.allCases.map {
            GlassPickerOption(value: $0,
                              icon: $0.layer?.icon ?? "square.grid.2x2",
                              title: String(localized: String.LocalizationValue($0.rawValue)))
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "cube.box",
            title: "No objects",
            message: "Add objects to your property zones from the Digital Twin"
        )
    }

    private func zoneName(for element: PropertyElement) -> String? {
        guard let zoneId = element.zoneId else { return nil }
        return zoneService.zones.first { $0.id == zoneId }?.name
    }
}

// MARK: - Object List Row

struct ObjectListRow: View {
    let element: PropertyElement
    let zoneName: String?
    var onToggleFavorite: () -> Void = {}

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: element.elementType.icon)
                .font(AppFont.scaled(19, weight: .semibold))
                .foregroundStyle(element.layer.color)
                .frame(width: 46, height: 46)
                .glassRoundedRect(AppRadius.md)

            VStack(alignment: .leading, spacing: 3) {
                Text(element.name)
                    .font(AppFont.subheadline)
                    .foregroundStyle(.primary)
                if let zone = zoneName {
                    Text(zone)
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                } else {
                    Text(element.elementType.displayName)
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                }
            }

            Spacer()

            Button { onToggleFavorite() } label: {
                Image(systemName: element.isFavorite ? "star.fill" : "star")
                    .font(AppFont.subheadline)
                    .foregroundStyle(element.isFavorite ? .yellow : Color.primary.opacity(0.3))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)

            // Health score badge
            Text("\(element.healthScore)")
                .font(AppFont.scaled(13, weight: .bold))
                .foregroundStyle(element.healthColor)
                .frame(width: 36, height: 28)
                .background(element.healthColor.opacity(AppOpacity.tintedFill), in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))

            Image(systemName: "chevron.right")
                .font(AppFont.label)
                .foregroundStyle(Color.primary.opacity(0.25))
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, 13)
        .background {
            // Opaque surface instead of a per-row material: blur + a soft
            // shadow on every row is pure compositor cost in a long list,
            // and the rows sit on an opaque screen background anyway.
            // Adaptive on purpose — this row also serves ZoneDetailView; on
            // the warm Objects sheet the scoped dark scheme darkens it.
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        }
    }
}

