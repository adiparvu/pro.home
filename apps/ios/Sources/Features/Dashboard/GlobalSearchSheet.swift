import SwiftUI

struct GlobalSearchSheet: View {
    @EnvironmentObject private var taskService: TaskService
    @EnvironmentObject private var documentService: DocumentService
    @EnvironmentObject private var plantService: PlantService
    @EnvironmentObject private var deliveryService: DeliveryService
    @EnvironmentObject private var familyService: FamilyService
    @EnvironmentObject private var financialService: FinancialService
    @EnvironmentObject private var elementService: PropertyElementService
    @EnvironmentObject private var applianceService: ApplianceService
    @EnvironmentObject private var supplyService: SupplyService
    @EnvironmentObject private var inventoryService: InventoryService
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @FocusState private var focused: Bool

    // Detail sheet selection state
    @State private var selectedMember: FamilyMember?
    @State private var selectedAppliance: Appliance?
    @State private var selectedElement: PropertyElement?
    @State private var selectedInventoryItem: InventoryItem?
    @State private var selectedPlant: Plant?
    @State private var selectedDelivery: Delivery?

    // MARK: - Search results

    private var q: String { query.lowercased() }
    private var active: Bool { query.count >= 2 }

    private var taskResults: [MaintenanceTask] {
        guard active else { return [] }
        return taskService.tasks.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }
    private var docResults: [DocumentModel] {
        guard active else { return [] }
        return documentService.documents.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
    private var plantResults: [Plant] {
        guard active else { return [] }
        return plantService.plants.filter {
            $0.name.lowercased().contains(q) ||
            ($0.species?.lowercased().contains(q) ?? false) ||
            ($0.location?.lowercased().contains(q) ?? false)
        }
    }
    private var deliveryResults: [Delivery] {
        guard active else { return [] }
        return deliveryService.deliveries.filter {
            $0.description.lowercased().contains(q) ||
            $0.carrier.lowercased().contains(q) ||
            $0.trackingNumber.lowercased().contains(q)
        }
    }
    private var peopleResults: [FamilyMember] {
        guard active else { return [] }
        return familyService.members.filter {
            $0.name.lowercased().contains(q) ||
            ($0.email?.lowercased().contains(q) ?? false) ||
            ($0.phone?.contains(q) ?? false) ||
            $0.roleLabel.lowercased().contains(q)
        }
    }
    private var financialResults: [FinancialRecord] {
        guard active else { return [] }
        return financialService.records.filter {
            $0.title.lowercased().contains(q) ||
            $0.category.lowercased().contains(q) ||
            ($0.description?.lowercased().contains(q) ?? false)
        }
    }
    private var elementResults: [PropertyElement] {
        guard active else { return [] }
        return elementService.elements.filter {
            $0.name.lowercased().contains(q) ||
            ($0.description?.lowercased().contains(q) ?? false) ||
            ($0.brand?.lowercased().contains(q) ?? false)
        }
    }
    private var applianceResults: [Appliance] {
        guard active else { return [] }
        return applianceService.appliances.filter {
            $0.name.lowercased().contains(q) ||
            ($0.brand?.lowercased().contains(q) ?? false) ||
            $0.category.rawValue.lowercased().contains(q)
        }
    }
    private var supplyResults: [SupplyItem] {
        guard active else { return [] }
        return supplyService.items.filter {
            $0.name.lowercased().contains(q) ||
            ($0.notes?.lowercased().contains(q) ?? false) ||
            $0.category.lowercased().contains(q)
        }
    }
    private var inventoryResults: [InventoryItem] {
        guard active else { return [] }
        return inventoryService.items.filter {
            $0.name.lowercased().contains(q) ||
            $0.brand.lowercased().contains(q) ||
            $0.category.lowercased().contains(q) ||
            $0.notes.lowercased().contains(q)
        }
    }

    private var hasResults: Bool {
        !taskResults.isEmpty || !docResults.isEmpty || !plantResults.isEmpty ||
        !deliveryResults.isEmpty || !peopleResults.isEmpty || !financialResults.isEmpty ||
        !elementResults.isEmpty || !applianceResults.isEmpty || !supplyResults.isEmpty ||
        !inventoryResults.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                Divider().opacity(0.3)
                Group {
                    if !active {
                        promptState
                    } else if !hasResults {
                        noResultsState
                    } else {
                        resultsView
                    }
                }
            }
            .background(appBackground.ignoresSafeArea())
            .navigationTitle("Global Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
        .onAppear { focused = true }
        .sheet(item: $selectedMember) { m in
            MemberProfileSheet(member: m)
                .environmentObject(familyService)
        }
        .sheet(item: $selectedAppliance) { a in
            ApplianceDetailSheet(appliance: a)
                .environmentObject(applianceService)
        }
        .sheet(item: $selectedElement) { e in
            PropertyElementDetailView(element: e)
                .environmentObject(elementService)
                .environmentObject(documentService)
        }
        .sheet(item: $selectedInventoryItem) { i in
            ItemDetailView(item: i, service: inventoryService)
        }
        .sheet(item: $selectedPlant) { p in
            PlantDetailSheet(plant: p)
                .environmentObject(plantService)
        }
        .sheet(item: $selectedDelivery) { d in
            DeliveryFormSheet(editingDelivery: d)
                .environmentObject(deliveryService)
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("People, tasks, documents, appliances…", text: $query)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .focused($focused)
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.primary.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - States

    private var promptState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(Color.primary.opacity(0.12))
            Text("Search across the entire app")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.5))
            Text("People · Tasks · Documents · Appliances · Finances · Plants · Supplies · Inventory · Deliveries")
                .font(.system(size: 12))
                .foregroundStyle(Color.primary.opacity(0.3))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "questionmark.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(Color.primary.opacity(0.12))
            Text("No results for")
                .font(.system(size: 15))
                .foregroundStyle(Color.primary.opacity(0.45))
            Text("\"\(query)\"")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.6))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results (split into sections to avoid type-checker timeout)

    private var resultsView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                peopleSectionView
                tasksSectionView
                documentsSectionView
                appliancesSectionView
                elementsSectionView
                financesSectionView
                inventorySectionView
                suppliesSectionView
                plantsSectionView
                deliveriesSectionView
                Spacer(minLength: 60)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }

    // MARK: - Individual section views

    @ViewBuilder private var peopleSectionView: some View {
        if !peopleResults.isEmpty {
            resultSection("People", icon: "person.2.fill", color: .purple) {
                ForEach(peopleResults.prefix(8)) { m in
                    resultRow(m.name, subtitle: m.roleLabel,
                              icon: "person.fill", color: .purple,
                              isLast: m.id == peopleResults.prefix(8).last?.id) {
                        selectedMember = m
                    }
                }
            }
        }
    }

    @ViewBuilder private var tasksSectionView: some View {
        if !taskResults.isEmpty {
            resultSection("Tasks", icon: "checklist", color: .blue) {
                ForEach(taskResults.prefix(8)) { t in
                    resultRow(t.title, subtitle: t.dueDateDisplay,
                              icon: "checklist", color: .blue,
                              isLast: t.id == taskResults.prefix(8).last?.id) {
                        navigateAway(to: .tasks) { r in r.deepLinkTaskId = t.id }
                    }
                }
            }
        }
    }

    @ViewBuilder private var documentsSectionView: some View {
        if !docResults.isEmpty {
            resultSection("Documents", icon: "doc.fill", color: .orange) {
                ForEach(docResults.prefix(8)) { d in
                    resultRow(d.name, subtitle: d.expiresDisplay ?? "No expiry",
                              icon: "doc.fill", color: .orange,
                              isLast: d.id == docResults.prefix(8).last?.id) {
                        navigateAway(to: .digitalTwin)
                    }
                }
            }
        }
    }

    @ViewBuilder private var appliancesSectionView: some View {
        if !applianceResults.isEmpty {
            resultSection("Appliances", icon: "washer.fill", color: .teal) {
                ForEach(applianceResults.prefix(8)) { a in
                    resultRow(a.name,
                              subtitle: applianceSubtitle(a),
                              icon: a.categoryIcon, color: a.categoryColor,
                              isLast: a.id == applianceResults.prefix(8).last?.id) {
                        selectedAppliance = a
                    }
                }
            }
        }
    }

    @ViewBuilder private var elementsSectionView: some View {
        if !elementResults.isEmpty {
            resultSection("Property Elements", icon: "house.fill", color: .indigo) {
                ForEach(elementResults.prefix(8)) { e in
                    resultRow(e.name,
                              subtitle: elementSubtitle(e),
                              icon: "square.grid.2x2.fill", color: .indigo,
                              isLast: e.id == elementResults.prefix(8).last?.id) {
                        selectedElement = e
                    }
                }
            }
        }
    }

    @ViewBuilder private var financesSectionView: some View {
        if !financialResults.isEmpty {
            let green = Color(red: 0.20, green: 0.78, blue: 0.35)
            resultSection("Finances", icon: "creditcard.fill", color: green) {
                ForEach(financialResults.prefix(8)) { f in
                    resultRow(f.title, subtitle: f.category,
                              icon: "creditcard.fill", color: green,
                              isLast: f.id == financialResults.prefix(8).last?.id) {
                        navigateAway(to: .home)
                    }
                }
            }
        }
    }

    @ViewBuilder private var inventorySectionView: some View {
        if !inventoryResults.isEmpty {
            resultSection("Inventory", icon: "archivebox.fill", color: .brown) {
                ForEach(inventoryResults.prefix(8)) { i in
                    resultRow(i.name,
                              subtitle: inventorySubtitle(i),
                              icon: i.categoryIcon, color: i.categoryColor,
                              isLast: i.id == inventoryResults.prefix(8).last?.id) {
                        selectedInventoryItem = i
                    }
                }
            }
        }
    }

    @ViewBuilder private var suppliesSectionView: some View {
        if !supplyResults.isEmpty {
            resultSection("Supplies", icon: "cart.fill", color: .cyan) {
                ForEach(supplyResults.prefix(8)) { s in
                    resultRow(s.name, subtitle: s.category,
                              icon: s.categoryIcon, color: s.categoryColor,
                              isLast: s.id == supplyResults.prefix(8).last?.id) {
                        navigateAway(to: .home) { r in r.showAddSupply = true }
                    }
                }
            }
        }
    }

    @ViewBuilder private var plantsSectionView: some View {
        if !plantResults.isEmpty {
            let plantGreen = Color(red: 0.15, green: 0.80, blue: 0.40)
            resultSection("Plants", icon: "leaf.fill", color: plantGreen) {
                ForEach(plantResults.prefix(8)) { p in
                    resultRow("\(p.emoji) \(p.name)",
                              subtitle: p.needsWatering ? "Needs watering" : p.wateringLabel,
                              icon: "leaf.fill", color: plantGreen,
                              isLast: p.id == plantResults.prefix(8).last?.id) {
                        selectedPlant = p
                    }
                }
            }
        }
    }

    @ViewBuilder private var deliveriesSectionView: some View {
        if !deliveryResults.isEmpty {
            resultSection("Deliveries", icon: "shippingbox.fill", color: .orange) {
                ForEach(deliveryResults.prefix(8)) { d in
                    resultRow(d.description, subtitle: "\(d.carrier) · \(d.statusLabel)",
                              icon: d.statusIcon, color: d.statusColor,
                              isLast: d.id == deliveryResults.prefix(8).last?.id) {
                        selectedDelivery = d
                    }
                }
            }
        }
    }

    // MARK: - Subtitle helpers (extracted to avoid type-checker timeout)

    private func applianceSubtitle(_ a: Appliance) -> String {
        let parts: [String?] = [a.brand, a.category.displayName]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    private func elementSubtitle(_ e: PropertyElement) -> String {
        let parts: [String?] = [e.brand, e.description]
        return parts.compactMap { $0 }.first ?? e.elementType.displayName
    }

    private func inventorySubtitle(_ i: InventoryItem) -> String {
        let brandPart: String? = i.brand.isEmpty ? nil : i.brand
        let parts: [String?] = [brandPart, i.category]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: - Navigation helper

    private func navigateAway(to tab: AppTab, action: ((AppRouter) -> Void)? = nil) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            router.selectedTab = tab
            action?(router)
        }
    }

    // MARK: - Helpers

    private func resultSection<C: View>(_ title: String, icon: String, color: Color,
                                         @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .tracking(0.5)
                .padding(.leading, 4)
            GlassCard(padding: 0) {
                VStack(spacing: 0) { content() }
            }
        }
    }

    private func resultRow(_ title: String, subtitle: String,
                           icon: String, color: Color, isLast: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(color.opacity(0.14))
                            .frame(width: 30, height: 30)
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(color)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.22))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                if !isLast {
                    Rectangle()
                        .fill(Color.primary.opacity(0.05))
                        .frame(height: 0.5)
                        .padding(.leading, 56)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
