import SwiftUI

// MARK: - Objects List — matches dark mockup (filter chips + object rows)

struct ObjectsListView: View {
    @EnvironmentObject var elementService: PropertyElementService
    @EnvironmentObject var zoneService: PropertyZoneService
    @EnvironmentObject var currencyService: CurrencyService
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var documentService: DocumentService
    @EnvironmentObject var taskService: TaskService
    @EnvironmentObject private var tabBarVis: TabBarVisibility

    @State private var filter: ObjectFilter = .all
    @State private var favoritesOnly = false
    @State private var selectedElement: PropertyElement?
    @State private var filterMode: FilterMode = .categories
    @State private var categoryFilter: ElementCategory? = nil

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
        return items
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                filterChipsRow
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)

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
                    .padding(.horizontal, 16)
                }

                Spacer(minLength: 120)
            }
            .padding(.top, 8)
            .trackTabScroll()
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Objects")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("\(filteredElements.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .sheet(item: $selectedElement) { element in
            PropertyElementDetailView(element: element)
                .environmentObject(elementService)
                .environmentObject(currencyService)
                .environmentObject(appSettings)
                .environmentObject(documentService)
                .environmentObject(taskService)
        }
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
                            .font(.system(size: 11, weight: .semibold))
                        Text("Favorites").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(favoritesOnly ? Color.black : Color.yellow)
                    .padding(.horizontal, 12).padding(.vertical, 8)
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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 11).padding(.vertical, 8)
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
        VStack(spacing: 14) {
            Image(systemName: "cube.box")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Color.primary.opacity(0.2))
            Text("No objects")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.45))
            Text("Add objects to your property zones from the Digital Twin")
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(0.3))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
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
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(element.layer.color.opacity(0.18))
                    .frame(width: 46, height: 46)
                Image(systemName: element.elementType.icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(element.layer.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(element.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                if let zone = zoneName {
                    Text(zone)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.primary.opacity(0.45))
                } else {
                    Text(element.elementType.displayName)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.primary.opacity(0.35))
                }
            }

            Spacer()

            Button { onToggleFavorite() } label: {
                Image(systemName: element.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(element.isFavorite ? .yellow : Color.primary.opacity(0.3))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)

            // Health score badge
            Text("\(element.healthScore)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(element.healthColor)
                .frame(width: 36, height: 28)
                .background(element.healthColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.25))
        }
        .padding(.horizontal, 14)
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

