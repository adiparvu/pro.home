import SwiftUI

// MARK: - Objects List — matches dark mockup (filter chips + object rows)

struct ObjectsListView: View {
    @Environment(PropertyElementService.self) var elementService
    @Environment(PropertyZoneService.self) var zoneService
    @Environment(CurrencyService.self) var currencyService
    @Environment(AppSettings.self) var appSettings
    @Environment(DocumentService.self) var documentService
    @Environment(TaskService.self) var taskService
    @Environment(TabBarVisibility.self) private var tabBarVis

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
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            items = items.filter { el in
                let fields = [el.name, el.brand, el.model, el.serialNumber, el.notes, el.elementType.displayName]
                    .compactMap { $0 } + el.tags
                return fields.contains { $0.lowercased().contains(q) }
            }
        }
        return items
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                filterChipsRow
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
            .trackTabScroll()
        }
        .navigationTitle("Objects")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search name, brand, serial…")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("\(filteredElements.count)")
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(.secondary)
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
    }

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.3)) { favoritesOnly.toggle() }
                    HapticFeedback.selection()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: favoritesOnly ? "star.fill" : "star")
                            .font(AppFont.label)
                        Text("Favorites").font(AppFont.captionEmphasis)
                    }
                    .foregroundStyle(favoritesOnly ? Color.black : Color.yellow)
                    .padding(.horizontal, AppSpacing.md).padding(.vertical, AppSpacing.sm)
                    .background(favoritesOnly ? Color.yellow : Color.primary.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)

                // Mode toggle: Categories <-> Layers
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        filterMode = filterMode == .categories ? .layers : .categories
                        categoryFilter = nil; filter = .all
                    }
                    HapticFeedback.selection()
                } label: {
                    Image(systemName: filterMode == .categories ? "square.grid.2x2.fill" : "square.3.layers.3d")
                        .font(AppFont.captionStrong)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 11).padding(.vertical, AppSpacing.sm)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)

                if filterMode == .layers {
                    ForEach(ObjectFilter.allCases, id: \.self) { f in
                        CategoryFilterChip(label: LocalizedStringKey(f.rawValue), isActive: filter == f) {
                            withAnimation(.spring(response: 0.3)) { filter = f }
                        }
                    }
                } else {
                    CategoryFilterChip(label: "All", isActive: categoryFilter == nil) {
                        withAnimation(.spring(response: 0.3)) { categoryFilter = nil }
                    }
                    ForEach(ElementCategory.allCases) { cat in
                        CategoryFilterChip(label: LocalizedStringKey(cat.displayName), isActive: categoryFilter == cat) {
                            withAnimation(.spring(response: 0.3)) { categoryFilter = cat }
                        }
                    }
                }
            }
            .padding(.vertical, 2)
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
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(element.layer.color.opacity(0.18))
                    .frame(width: 46, height: 46)
                Image(systemName: element.elementType.icon)
                    .font(AppFont.scaled(19, weight: .semibold))
                    .foregroundStyle(element.layer.color)
            }

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
                .background(element.healthColor.opacity(0.15), in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))

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

