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
            ($0.carrier?.lowercased().contains(q) ?? false) ||
            ($0.trackingNumber?.lowercased().contains(q) ?? false)
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
        !shortcutResults.isEmpty || !taskResults.isEmpty || !docResults.isEmpty ||
        !plantResults.isEmpty || !deliveryResults.isEmpty || !peopleResults.isEmpty ||
        !financialResults.isEmpty || !elementResults.isEmpty || !applianceResults.isEmpty ||
        !supplyResults.isEmpty || !inventoryResults.isEmpty
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
            Text("Search the entire app")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.5))
            Text("Tasks · Settings · ARIA · Map · Plants · Documents · Finances · Appliances · Inventory · Supplies · People · Deliveries")
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
                shortcutsSectionView
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

    // MARK: - Navigation shortcuts

    private struct AppShortcut: Identifiable {
        let id = UUID()
        let name: String
        let subtitle: String
        let synonyms: [String]
        let icon: String
        let color: Color
        let tab: AppTab
        let extra: ((AppRouter) -> Void)?
    }

    // swiftlint:disable function_body_length
    private static let appSections: [AppShortcut] = {
        let green  = Color(red: 0.20, green: 0.78, blue: 0.35)
        let pGreen = Color(red: 0.15, green: 0.80, blue: 0.40)
        let purple = Color(red: 0.45, green: 0.30, blue: 0.95)
        let chart  = Color(red: 0.40, green: 0.60, blue: 1.0)
        let gray   = Color(.systemGray)
        return [
            // ── Main tabs ──────────────────────────────────────────────────────
            AppShortcut(name: "Tasks", subtitle: "All maintenance tasks",
                        synonyms: ["task", "tasks", "sarcini", "sarcina", "checklist", "maintenance", "mentenanta", "mentenanță"],
                        icon: "checklist", color: .blue, tab: .tasks, extra: nil),
            AppShortcut(name: "Add Task", subtitle: "Create a new task",
                        synonyms: ["add task", "new task", "sarcina noua", "adauga sarcina"],
                        icon: "plus.circle.fill", color: .blue, tab: .tasks, extra: { r in r.showAddTask = true }),
            AppShortcut(name: "ARIA Chat", subtitle: "AI assistant",
                        synonyms: ["aria", "chat ai", "ai", "assistant", "asistent", "gpt", "inteligenta artificiala"],
                        icon: "sparkles", color: purple, tab: .chat, extra: nil),
            AppShortcut(name: "Digital Twin", subtitle: "Property map & zones",
                        synonyms: ["twin", "digital twin", "map", "harta", "hartă", "zone", "zones", "proprietate map"],
                        icon: "map.fill", color: .teal, tab: .digitalTwin, extra: nil),
            // ── Home tab sections ──────────────────────────────────────────────
            AppShortcut(name: "Plants", subtitle: "Manage your plants",
                        synonyms: ["plant", "plants", "plante", "planta", "watering", "udare", "flori", "flower"],
                        icon: "leaf.fill", color: pGreen, tab: .home, extra: { r in r.showWaterPlant = true }),
            AppShortcut(name: "Finances", subtitle: "Income, expenses & budget",
                        synonyms: ["finance", "finances", "finante", "finanțe", "budget", "buget", "cheltuieli", "venituri", "income", "expenses", "bani", "money"],
                        icon: "creditcard.fill", color: green, tab: .home, extra: nil),
            AppShortcut(name: "Budget", subtitle: "Budget planner",
                        synonyms: ["budget", "buget", "planner", "planificare"],
                        icon: "chart.pie.fill", color: green, tab: .home, extra: nil),
            AppShortcut(name: "Mortgage", subtitle: "Mortgage calculator",
                        synonyms: ["mortgage", "ipoteca", "ipotecă", "credit", "loan", "imprumut", "împrumut"],
                        icon: "building.columns.fill", color: green, tab: .home, extra: nil),
            AppShortcut(name: "Supplies", subtitle: "Shopping & supply lists",
                        synonyms: ["supply", "supplies", "shopping", "lista", "cumparaturi", "cumpărături", "cart", "cos"],
                        icon: "cart.fill", color: .cyan, tab: .home, extra: { r in r.showAddSupply = true }),
            AppShortcut(name: "Inventory", subtitle: "Home inventory",
                        synonyms: ["inventory", "inventar", "items", "obiecte", "stoc", "lucruri"],
                        icon: "archivebox.fill", color: .brown, tab: .home, extra: nil),
            AppShortcut(name: "Deliveries", subtitle: "Package tracking",
                        synonyms: ["delivery", "deliveries", "livrare", "livrari", "parcel", "package", "tracking", "colet", "pachet"],
                        icon: "shippingbox.fill", color: .orange, tab: .home, extra: nil),
            AppShortcut(name: "Analytics", subtitle: "Stats & property insights",
                        synonyms: ["analytics", "analiza", "analiză", "stats", "statistics", "raport", "report", "insights", "grafice"],
                        icon: "chart.bar.fill", color: chart, tab: .home, extra: nil),
            AppShortcut(name: "Photo Journal", subtitle: "Property photo diary",
                        synonyms: ["photo", "journal", "jurnal", "foto", "poza", "poze", "picture", "diary"],
                        icon: "photo.fill", color: .pink, tab: .home, extra: nil),
            AppShortcut(name: "Paint Colors", subtitle: "Saved paint colors",
                        synonyms: ["paint", "color", "culoare", "vopsea", "culori", "paint colors"],
                        icon: "paintpalette.fill", color: .pink, tab: .home, extra: nil),
            AppShortcut(name: "Property Value", subtitle: "Property valuation",
                        synonyms: ["value", "valoare", "valuation", "price", "pret", "preț", "market", "piata"],
                        icon: "house.fill", color: .indigo, tab: .home, extra: nil),
            // ── Digital Twin tab sections ──────────────────────────────────────
            AppShortcut(name: "Documents", subtitle: "All your documents",
                        synonyms: ["document", "documents", "documente", "pdf", "file", "fisier", "fișier", "contract", "act"],
                        icon: "doc.fill", color: .orange, tab: .digitalTwin, extra: nil),
            AppShortcut(name: "Appliances", subtitle: "Household appliances",
                        synonyms: ["appliance", "appliances", "electrocasnice", "washer", "fridge", "frigider", "masina spalat"],
                        icon: "washer.fill", color: .teal, tab: .digitalTwin, extra: nil),
            AppShortcut(name: "Blueprints", subtitle: "Floor plans & 3D scans",
                        synonyms: ["blueprint", "blueprints", "plan", "floor plan", "scan", "lidar", "3d", "room scan", "planuri"],
                        icon: "square.3.layers.3d", color: .indigo, tab: .digitalTwin, extra: nil),
            AppShortcut(name: "Utilities", subtitle: "Bills & utility readings",
                        synonyms: ["utility", "utilities", "utilitati", "utilități", "bill", "bills", "factura", "facturi", "apa", "gaz", "curent", "electric", "water", "gas"],
                        icon: "bolt.fill", color: Color(red: 1.0, green: 0.65, blue: 0.15), tab: .digitalTwin, extra: nil),
            AppShortcut(name: "Contractors", subtitle: "Service providers",
                        synonyms: ["contractor", "contractors", "service", "meserias", "meșteșugar", "instalator", "electrician", "provider"],
                        icon: "wrench.and.screwdriver.fill", color: .orange, tab: .digitalTwin, extra: nil),
            AppShortcut(name: "Property Zones", subtitle: "Rooms & outdoor zones",
                        synonyms: ["zone", "zones", "room", "camera", "camere", "baie", "bucatarie", "living", "gradina", "curte", "outdoor"],
                        icon: "square.grid.2x2.fill", color: .teal, tab: .digitalTwin, extra: nil),
            AppShortcut(name: "Property Elements", subtitle: "Doors, windows, structures",
                        synonyms: ["element", "elements", "door", "window", "usa", "fereastra", "structura", "perete"],
                        icon: "house.fill", color: .indigo, tab: .digitalTwin, extra: nil),
            // ── Settings tab ───────────────────────────────────────────────────
            AppShortcut(name: "Settings", subtitle: "All app preferences",
                        synonyms: ["settings", "setari", "setări", "preferences", "config", "configurare", "optiuni", "opțiuni"],
                        icon: "gearshape.fill", color: gray, tab: .settings, extra: nil),
            AppShortcut(name: "Language", subtitle: "Change app language",
                        synonyms: ["language", "limba", "limbă", "english", "romana", "română", "french", "dutch", "franceza", "olandeza", "traducere"],
                        icon: "globe", color: .blue, tab: .settings, extra: nil),
            AppShortcut(name: "Appearance", subtitle: "Theme, dark mode & accent color",
                        synonyms: ["appearance", "aspect", "theme", "tema", "dark mode", "mod intunecat", "culoare", "accent", "icon", "light mode"],
                        icon: "paintbrush.fill", color: .pink, tab: .settings, extra: nil),
            AppShortcut(name: "Notifications", subtitle: "Push notification settings",
                        synonyms: ["notification", "notifications", "notificari", "notificări", "push", "alert", "alerte", "remind"],
                        icon: "bell.fill", color: .red, tab: .settings, extra: nil),
            AppShortcut(name: "Floating Buttons", subtitle: "Customize quick-action buttons",
                        synonyms: ["floating", "button", "buttons", "butoane", "flotante", "speed dial", "quick action", "fab"],
                        icon: "circle.grid.2x2.fill", color: .purple, tab: .settings, extra: nil),
            AppShortcut(name: "Integrations", subtitle: "Google Calendar & more",
                        synonyms: ["integration", "integrations", "integrari", "integrări", "google", "calendar", "sync", "connect"],
                        icon: "link", color: .blue, tab: .settings, extra: nil),
            AppShortcut(name: "Family Members", subtitle: "Manage family & housemates",
                        synonyms: ["family", "familie", "member", "members", "housemate", "colocatar", "persoane"],
                        icon: "person.2.fill", color: .purple, tab: .settings, extra: nil),
            AppShortcut(name: "Trusted Contacts", subtitle: "Trusted people for property",
                        synonyms: ["trusted", "contact", "contacts", "incredere", "încredere", "persoane de contact"],
                        icon: "person.badge.shield.checkmark.fill", color: .purple, tab: .settings, extra: nil),
            AppShortcut(name: "Emergency Contacts", subtitle: "Emergency contact list",
                        synonyms: ["emergency", "urgenta", "urgență", "sos", "ajutor", "help", "ambulanta", "pompieri", "politie"],
                        icon: "phone.fill", color: .red, tab: .settings, extra: nil),
            AppShortcut(name: "Security & Privacy", subtitle: "Face ID, app lock, password",
                        synonyms: ["security", "privacy", "securitate", "confidentialitate", "face id", "touch id", "lock", "parola", "password", "pin"],
                        icon: "lock.shield.fill", color: .green, tab: .settings, extra: nil),
            AppShortcut(name: "Profile", subtitle: "Edit your profile",
                        synonyms: ["profile", "profil", "name", "nume", "avatar", "photo", "foto", "edit profile"],
                        icon: "person.circle.fill", color: .blue, tab: .settings, extra: nil),
            AppShortcut(name: "My Property", subtitle: "Property details & info",
                        synonyms: ["property", "proprietate", "house", "casa", "home", "acasa", "my home", "adresa", "address"],
                        icon: "house.fill", color: .indigo, tab: .settings, extra: nil),
            AppShortcut(name: "Help & FAQ", subtitle: "Help center and FAQ",
                        synonyms: ["help", "faq", "ajutor", "intrebare", "întrebare", "support", "suport", "problem", "problema"],
                        icon: "questionmark.circle.fill", color: gray, tab: .settings, extra: nil),
            AppShortcut(name: "Sign Out", subtitle: "Log out of your account",
                        synonyms: ["sign out", "logout", "log out", "iesire", "ieșire", "deconecteaza", "deconectează"],
                        icon: "rectangle.portrait.and.arrow.right", color: .red, tab: .settings, extra: nil),
        ]
    }()
    // swiftlint:enable function_body_length

    private var shortcutResults: [AppShortcut] {
        guard active else { return [] }
        return Self.appSections.filter { s in
            s.name.lowercased().contains(q) ||
            s.synonyms.contains { $0.contains(q) }
        }
    }

    @ViewBuilder private var shortcutsSectionView: some View {
        if !shortcutResults.isEmpty {
            resultSection("Navigate to", icon: "arrow.right.circle.fill", color: .accentColor) {
                ForEach(Array(shortcutResults.enumerated()), id: \.element.id) { idx, s in
                    resultRow(s.name, subtitle: s.subtitle,
                              icon: s.icon, color: s.color,
                              isLast: idx == shortcutResults.count - 1) {
                        navigateAway(to: s.tab, action: s.extra)
                    }
                }
            }
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
                    resultRow(d.description, subtitle: "\(d.carrier ?? "") · \(d.statusLabel)",
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
        // Capture router strongly BEFORE dismiss — EnvironmentObject becomes inaccessible once the view is torn down
        let r = router
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            r.selectedTab = tab
            action?(r)
        }
    }

    // MARK: - Helpers

    private func resultSection<C: View>(_ title: String, icon: String, color: Color,
                                         @ViewBuilder content: () -> C) -> some View {
        let body = content()
        return VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .tracking(0.5)
                .padding(.leading, 4)
            GlassCard(padding: 0) {
                VStack(spacing: 0) { body }
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
