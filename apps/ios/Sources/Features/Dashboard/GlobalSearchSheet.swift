import SwiftUI

/// Lightweight server-side chat search hit (full Message model isn't needed).
struct ChatSearchHit: Decodable, Identifiable {
    let id: UUID
    let senderName: String?
    let body: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, body
        case senderName = "sender_name"
        case createdAt  = "created_at"
    }
}

struct GlobalSearchSheet: View {
    @Environment(TaskService.self) private var taskService
    @Environment(DocumentService.self) private var documentService
    @Environment(PlantService.self) private var plantService
    @Environment(DeliveryService.self) private var deliveryService
    @Environment(FamilyService.self) private var familyService
    @Environment(FinancialService.self) private var financialService
    @Environment(PropertyElementService.self) private var elementService
    @Environment(ApplianceService.self) private var applianceService
    @Environment(SupplyService.self) private var supplyService
    @Environment(InventoryService.self) private var inventoryService
    @Environment(ContractorService.self) private var contractorService
    @Environment(PropertyZoneService.self) private var zoneService
    @Environment(PaintColorService.self) private var paintColorService
    @Environment(PhotoJournalService.self) private var photoJournalService
    @Environment(PropertyService.self) private var propertyService
    @Environment(AuthService.self) private var auth
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @FocusState private var focused: Bool
    @AppStorage("prvio.aria.customName") private var assistantName: String = "ARIA"

    /// Chat search is server-side (messages aren't kept in memory app-wide),
    /// debounced per keystroke via .task(id:).
    @State private var chatHits: [ChatSearchHit] = []

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

    private var contractorResults: [ContractorModel] {
        guard active else { return [] }
        return contractorService.contractors.filter {
            $0.name.lowercased().contains(q) ||
            $0.category.lowercased().contains(q) ||
            ($0.phone?.contains(q) ?? false) ||
            ($0.email?.lowercased().contains(q) ?? false) ||
            ($0.notes?.lowercased().contains(q) ?? false)
        }
    }
    private var zoneResults: [PropertyZone] {
        guard active else { return [] }
        return zoneService.zones.filter {
            $0.name.lowercased().contains(q) ||
            ($0.notes?.lowercased().contains(q) ?? false)
        }
    }
    private var paintResults: [PaintColor] {
        guard active else { return [] }
        return paintColorService.colors.filter {
            $0.colorName.lowercased().contains(q) ||
            $0.roomName.lowercased().contains(q) ||
            ($0.brand?.lowercased().contains(q) ?? false) ||
            ($0.code?.lowercased().contains(q) ?? false)
        }
    }
    private var journalResults: [PhotoJournalEntry] {
        guard active else { return [] }
        return photoJournalService.entries.filter {
            $0.title.lowercased().contains(q) ||
            ($0.caption?.lowercased().contains(q) ?? false) ||
            ($0.tags?.contains { $0.lowercased().contains(q) } ?? false)
        }
    }

    /// The signed-in account when the query targets its PRVIO ID — the ID is
    /// a real lookup key, not decoration.
    private var accountIdMatch: UUID? {
        guard active, let uid = auth.session?.user.id,
              AccountID.matches(query, userId: uid) else { return nil }
        return uid
    }

    private var hasResults: Bool {
        accountIdMatch != nil ||
        !shortcutResults.isEmpty || !taskResults.isEmpty || !docResults.isEmpty ||
        !plantResults.isEmpty || !deliveryResults.isEmpty || !peopleResults.isEmpty ||
        !financialResults.isEmpty || !elementResults.isEmpty || !applianceResults.isEmpty ||
        !supplyResults.isEmpty || !inventoryResults.isEmpty ||
        !contractorResults.isEmpty || !zoneResults.isEmpty || !paintResults.isEmpty ||
        !journalResults.isEmpty || !chatHits.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.sm)
                    .padding(.bottom, AppSpacing.md)
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
            .navigationTitle("Global Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                        .font(AppFont.subheadline)
                }
            }
        }
        .presentationBackground(.thinMaterial)
        .onAppear { focused = true }
        .task {
            // Search must cover EVERYTHING, not just the pages the user
            // happened to visit this session — hydrate every empty source
            // concurrently. Cheap no-ops when already loaded.
            guard let pid = propertyService.primary?.id else { return }
            await withTaskGroup(of: Void.self) { group in
                if contractorService.contractors.isEmpty { group.addTask { @MainActor in await contractorService.load() } }
                if zoneService.zones.isEmpty { group.addTask { @MainActor in await zoneService.load(propertyId: pid) } }
                if paintColorService.colors.isEmpty { group.addTask { @MainActor in await paintColorService.load(propertyId: pid) } }
                if photoJournalService.entries.isEmpty { group.addTask { @MainActor in await photoJournalService.load(propertyId: pid) } }
                if taskService.tasks.isEmpty { group.addTask { @MainActor in await taskService.load() } }
                if documentService.documents.isEmpty { group.addTask { @MainActor in await documentService.load() } }
                if financialService.records.isEmpty { group.addTask { @MainActor in await financialService.load() } }
                if familyService.members.isEmpty { group.addTask { @MainActor in await familyService.load() } }
                if plantService.plants.isEmpty { group.addTask { @MainActor in await plantService.load(propertyId: pid) } }
                if deliveryService.deliveries.isEmpty { group.addTask { @MainActor in await deliveryService.load(propertyId: pid) } }
                if elementService.elements.isEmpty { group.addTask { @MainActor in await elementService.load(propertyId: pid) } }
                if applianceService.appliances.isEmpty { group.addTask { @MainActor in await applianceService.load(propertyId: pid) } }
                if supplyService.items.isEmpty { group.addTask { @MainActor in await supplyService.load(propertyId: pid) } }
                if inventoryService.items.isEmpty { group.addTask { @MainActor in await inventoryService.load(propertyId: pid) } }
            }
        }
        .task(id: query) {
            // Server-side chat search, debounced.
            guard active, let pid = propertyService.primary?.id else { chatHits = []; return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let raw: [ChatSearchHit] = (try? await supabase
                .from("messages")
                .select("id, sender_name, body, created_at")
                .eq("property_id", value: pid.uuidString)
                .ilike("body", pattern: "%\(query)%")
                .order("created_at", ascending: false)
                .limit(8)
                .execute().value) ?? []
            // Structured bodies (shared contacts ride as JSON with a base64
            // avatar) match almost any substring — keep them only when the
            // query matches what the user actually sees: names, phones, emails.
            chatHits = raw.filter { hit in
                let contacts = SharedContactPayload.decode(hit.body)
                guard !contacts.isEmpty else { return true }
                return contacts.contains { c in
                    c.name.localizedCaseInsensitiveContains(query) ||
                    c.phones.contains { $0.localizedCaseInsensitiveContains(query) } ||
                    c.emails.contains { $0.localizedCaseInsensitiveContains(query) }
                }
            }
        }
        .sheet(item: $selectedMember) { m in
            MemberProfileSheet(member: m)
                .environment(familyService)
        }
        .sheet(item: $selectedAppliance) { a in
            ApplianceDetailSheet(appliance: a)
                .environment(applianceService)
        }
        .sheet(item: $selectedElement) { e in
            PropertyElementDetailView(element: e)
                .environment(elementService)
                .environment(documentService)
        }
        .sheet(item: $selectedInventoryItem) { i in
            ItemDetailView(item: i, service: inventoryService)
        }
        .sheet(item: $selectedPlant) { p in
            PlantDetailSheet(plant: p)
                .environment(plantService)
        }
        .sheet(item: $selectedDelivery) { d in
            DeliveryFormSheet(editingDelivery: d)
                .environment(deliveryService)
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(AppFont.subheadline)
                .foregroundStyle(.secondary)
            TextField("People, tasks, documents, appliances…", text: $query)
                .font(AppFont.scaled(16))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .focused($focused)
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppFont.scaled(16))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, 11)
        .background(Color.primary.opacity(AppOpacity.hairline),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - States

    private var promptState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(AppFont.scaled(48))
                .foregroundStyle(Color.primary.opacity(0.12))
            Text("Search the entire app")
                .font(AppFont.headline)
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            Text("Tasks · Chat · Settings · \(assistantName) · Map · Plants · Documents · Finances · Appliances · Inventory · Supplies · People · Deliveries · Contractors · Zones · Paint · Photos")
                .font(AppFont.scaled(12))
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
                .font(AppFont.scaled(48))
                .foregroundStyle(Color.primary.opacity(0.12))
            Text("No results for")
                .font(AppFont.scaled(15))
                .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
            Text("\"\(query)\"")
                .font(AppFont.headline)
                .foregroundStyle(Color.primary.opacity(0.6))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results (split into sections to avoid type-checker timeout)

    private var resultsView: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 20) {
                accountSectionView
                shortcutsSectionView
                peopleSectionView
                chatSectionView
                tasksSectionView
                documentsSectionView
                appliancesSectionView
                elementsSectionView
                financesSectionView
                inventorySectionView
                suppliesSectionView
                plantsSectionView
                deliveriesSectionView
                contractorsSectionView
                zonesSectionView
                paintSectionView
                journalSectionView
                Spacer(minLength: 60)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.lg)
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
        let route: AppRouter.AppRoute
    }

    // swiftlint:disable function_body_length
    private static let appSections: [AppShortcut] = {
        let green  = Color(red: 0.20, green: 0.78, blue: 0.35)
        let pGreen = Color(red: 0.15, green: 0.80, blue: 0.40)
        let purple = Color(red: 0.45, green: 0.30, blue: 0.95)
        let chart  = Color.brandSkyBlue
        let gray   = Color(.systemGray)
        return [
            // ── Main tabs ──────────────────────────────────────────────────────
            AppShortcut(name: "Tasks", subtitle: "All maintenance tasks",
                        synonyms: ["task", "tasks", "sarcini", "sarcina", "checklist", "maintenance", "mentenanta", "mentenanță"],
                        icon: "checklist", color: .blue, route: .tasks(id: nil)),
            AppShortcut(name: "Add Task", subtitle: "Create a new task",
                        synonyms: ["add task", "new task", "sarcina noua", "adauga sarcina"],
                        icon: "plus.circle.fill", color: .blue, route: .newTask),
            AppShortcut(name: "Chat", subtitle: "House chat",
                        synonyms: ["chat", "mesaje", "messages", "conversatie", "conversație", "house chat"],
                        icon: "bubble.left.and.bubble.right.fill", color: .blue, route: .chat),
            AppShortcut(name: "ARIA", subtitle: "AI assistant",
                        synonyms: ["aria", "chat ai", "ai", "assistant", "asistent", "gpt", "inteligenta artificiala"],
                        icon: "sparkles", color: purple, route: .aria),
            AppShortcut(name: "Digital Twin", subtitle: "Property map & zones",
                        synonyms: ["twin", "digital twin", "map", "harta", "hartă", "zone", "zones", "proprietate map"],
                        icon: "map.fill", color: .teal, route: .twin),
            // ── Home tab sections ──────────────────────────────────────────────
            AppShortcut(name: "Plants", subtitle: "Manage your plants",
                        synonyms: ["plant", "plants", "plante", "planta", "watering", "udare", "flori", "flower"],
                        icon: "leaf.fill", color: pGreen, route: .plants(id: nil)),
            AppShortcut(name: "Finances", subtitle: "Income, expenses & budget",
                        synonyms: ["finance", "finances", "finante", "finanțe", "budget", "buget", "cheltuieli", "venituri", "income", "expenses", "bani", "money"],
                        icon: "creditcard.fill", color: green, route: .home),
            AppShortcut(name: "Budget", subtitle: "Budget planner",
                        synonyms: ["budget", "buget", "planner", "planificare"],
                        icon: "chart.pie.fill", color: green, route: .home),
            AppShortcut(name: "Mortgage", subtitle: "Mortgage calculator",
                        synonyms: ["mortgage", "ipoteca", "ipotecă", "credit", "loan", "imprumut", "împrumut"],
                        icon: "building.columns.fill", color: green, route: .home),
            AppShortcut(name: "Supplies", subtitle: "Shopping & supply lists",
                        synonyms: ["supply", "supplies", "shopping", "lista", "cumparaturi", "cumpărături", "cart", "cos"],
                        icon: "cart.fill", color: .cyan, route: .addSupply),
            AppShortcut(name: "Inventory", subtitle: "Home inventory",
                        synonyms: ["inventory", "inventar", "items", "obiecte", "stoc", "lucruri"],
                        icon: "archivebox.fill", color: .brown, route: .home),
            AppShortcut(name: "Deliveries", subtitle: "Package tracking",
                        synonyms: ["delivery", "deliveries", "livrare", "livrari", "parcel", "package", "tracking", "colet", "pachet"],
                        icon: "shippingbox.fill", color: .orange, route: .home),
            AppShortcut(name: "Analytics", subtitle: "Stats & property insights",
                        synonyms: ["analytics", "analiza", "analiză", "stats", "statistics", "raport", "report", "insights", "grafice"],
                        icon: "chart.bar.fill", color: chart, route: .home),
            AppShortcut(name: "Photo Journal", subtitle: "Property photo diary",
                        synonyms: ["photo", "journal", "jurnal", "foto", "poza", "poze", "picture", "diary"],
                        icon: "photo.fill", color: .pink, route: .home),
            AppShortcut(name: "Paint Colors", subtitle: "Saved paint colors",
                        synonyms: ["paint", "color", "culoare", "vopsea", "culori", "paint colors"],
                        icon: "paintpalette.fill", color: .pink, route: .home),
            AppShortcut(name: "Property Value", subtitle: "Property valuation",
                        synonyms: ["value", "valoare", "valuation", "price", "pret", "preț", "market", "piata"],
                        icon: "house.fill", color: .indigo, route: .home),
            // ── Digital Twin tab sections ──────────────────────────────────────
            AppShortcut(name: "Documents", subtitle: "All your documents",
                        synonyms: ["document", "documents", "documente", "pdf", "file", "fisier", "fișier", "contract", "act"],
                        icon: "doc.fill", color: .orange, route: .twin),
            AppShortcut(name: "Appliances", subtitle: "Household appliances",
                        synonyms: ["appliance", "appliances", "electrocasnice", "washer", "fridge", "frigider", "masina spalat"],
                        icon: "washer.fill", color: .teal, route: .twin),
            AppShortcut(name: "Blueprints", subtitle: "Floor plans & 3D scans",
                        synonyms: ["blueprint", "blueprints", "plan", "floor plan", "scan", "lidar", "3d", "room scan", "planuri"],
                        icon: "square.3.layers.3d", color: .indigo, route: .twin),
            AppShortcut(name: "Utilities", subtitle: "Bills & utility readings",
                        synonyms: ["utility", "utilities", "utilitati", "utilități", "bill", "bills", "factura", "facturi", "apa", "gaz", "curent", "electric", "water", "gas"],
                        icon: "bolt.fill", color: Color(red: 1.0, green: 0.65, blue: 0.15), route: .twin),
            AppShortcut(name: "Contractors", subtitle: "Service providers",
                        synonyms: ["contractor", "contractors", "service", "meserias", "meșteșugar", "instalator", "electrician", "provider"],
                        icon: "wrench.and.screwdriver.fill", color: .orange, route: .twin),
            AppShortcut(name: "Property Zones", subtitle: "Rooms & outdoor zones",
                        synonyms: ["zone", "zones", "room", "camera", "camere", "baie", "bucatarie", "living", "gradina", "curte", "outdoor"],
                        icon: "square.grid.2x2.fill", color: .teal, route: .twin),
            AppShortcut(name: "Property Elements", subtitle: "Doors, windows, structures",
                        synonyms: ["element", "elements", "door", "window", "usa", "fereastra", "structura", "perete"],
                        icon: "house.fill", color: .indigo, route: .twin),
            // ── Settings tab ───────────────────────────────────────────────────
            AppShortcut(name: "Settings", subtitle: "All app preferences",
                        synonyms: ["settings", "setari", "setări", "preferences", "config", "configurare", "optiuni", "opțiuni"],
                        icon: "gearshape.fill", color: gray, route: .settings),
            AppShortcut(name: "Language", subtitle: "Change app language",
                        synonyms: ["language", "limba", "limbă", "english", "romana", "română", "french", "dutch", "franceza", "olandeza", "traducere"],
                        icon: "globe", color: .blue, route: .settings),
            AppShortcut(name: "Appearance", subtitle: "Theme, dark mode & accent color",
                        synonyms: ["appearance", "aspect", "theme", "tema", "dark mode", "mod intunecat", "culoare", "accent", "icon", "light mode"],
                        icon: "paintbrush.fill", color: .pink, route: .settings),
            AppShortcut(name: "Notifications", subtitle: "Push notification settings",
                        synonyms: ["notification", "notifications", "notificari", "notificări", "push", "alert", "alerte", "remind"],
                        icon: "bell.fill", color: .red, route: .settings),
            AppShortcut(name: "Floating Buttons", subtitle: "Customize quick-action buttons",
                        synonyms: ["floating", "button", "buttons", "butoane", "flotante", "speed dial", "quick action", "fab"],
                        icon: "circle.grid.2x2.fill", color: .purple, route: .settings),
            AppShortcut(name: "Integrations", subtitle: "Google Calendar & more",
                        synonyms: ["integration", "integrations", "integrari", "integrări", "google", "calendar", "sync", "connect"],
                        icon: "link", color: .blue, route: .settings),
            AppShortcut(name: "Members", subtitle: "Family, invitations & supervision",
                        synonyms: ["family", "familie", "member", "members", "membri", "housemate", "colocatar", "persoane", "invitation", "invitatie", "invitație", "supraveghere", "supervision"],
                        icon: "person.2.fill", color: .purple, route: .settings),
            AppShortcut(name: "Custom Integrations", subtitle: "Connect anything with its own key",
                        synonyms: ["custom integration", "integrari personalizate", "webhook", "token", "cheie", "connect anything", "conecteaza orice"],
                        icon: "sparkles", color: .purple, route: .settings),
            AppShortcut(name: "Cross-app Messaging", subtitle: "Messages from other apps into chat",
                        synonyms: ["cross-app", "cross app", "mesaje externe", "external", "gateway", "shortcuts automation", "zapier chat"],
                        icon: "arrow.left.arrow.right", color: .blue, route: .settings),
            AppShortcut(name: "App Icon", subtitle: "Choose your app icon",
                        synonyms: ["app icon", "icon", "iconita", "iconiță", "pictograma", "logo"],
                        icon: "app.fill", color: .purple, route: .settings),
            AppShortcut(name: "Live Activities", subtitle: "Lock Screen & Dynamic Island",
                        synonyms: ["live activity", "live activities", "dynamic island", "lock screen", "ecran blocare", "activitati live", "activități live"],
                        icon: "bolt.badge.clock.fill", color: .blue, route: .settings),
            AppShortcut(name: "Widgets", subtitle: "Home & Lock Screen widgets",
                        synonyms: ["widget", "widgets", "widgeturi", "home screen", "control center"],
                        icon: "square.grid.2x2", color: .teal, route: .settings),
            AppShortcut(name: "Trusted Contacts", subtitle: "Trusted people for property",
                        synonyms: ["trusted", "contact", "contacts", "incredere", "încredere", "persoane de contact"],
                        icon: "person.badge.shield.checkmark.fill", color: .purple, route: .settings),
            AppShortcut(name: "Emergency Contacts", subtitle: "Emergency contact list",
                        synonyms: ["emergency", "urgenta", "urgență", "sos", "ajutor", "help", "ambulanta", "pompieri", "politie"],
                        icon: "phone.fill", color: .red, route: .settings),
            AppShortcut(name: "Security & Privacy", subtitle: "Face ID, app lock, password",
                        synonyms: ["security", "privacy", "securitate", "confidentialitate", "face id", "touch id", "lock", "parola", "password", "pin"],
                        icon: "lock.shield.fill", color: .green, route: .settings),
            AppShortcut(name: "Profile", subtitle: "Edit your profile",
                        synonyms: ["profile", "profil", "name", "nume", "avatar", "photo", "foto", "edit profile"],
                        icon: "person.circle.fill", color: .blue, route: .settings),
            AppShortcut(name: "My Property", subtitle: "Property details & info",
                        synonyms: ["property", "proprietate", "house", "casa", "home", "acasa", "my home", "adresa", "address"],
                        icon: "house.fill", color: .indigo, route: .settings),
            AppShortcut(name: "Help & FAQ", subtitle: "Help center and FAQ",
                        synonyms: ["help", "faq", "ajutor", "intrebare", "întrebare", "support", "suport", "problem", "problema"],
                        icon: "questionmark.circle.fill", color: gray, route: .settings),
            AppShortcut(name: "Sign Out", subtitle: "Log out of your account",
                        synonyms: ["sign out", "logout", "log out", "iesire", "ieșire", "deconecteaza", "deconectează"],
                        icon: "rectangle.portrait.and.arrow.right", color: .red, route: .settings),
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
                        navigateAway(route: s.route)
                    }
                }
            }
        }
    }

    // MARK: - Individual section views

    @ViewBuilder private var accountSectionView: some View {
        if let uid = accountIdMatch {
            resultSection("search_sec_account", icon: "person.text.rectangle.fill", color: .indigo) {
                resultRow(AccountID.display(for: uid),
                          subtitle: String(localized: "account_id_open_profile"),
                          icon: "person.crop.circle.fill", color: .indigo,
                          isLast: true) {
                    navigateAway(route: .profile)
                }
            }
        }
    }

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
                        navigateAway(route: .tasks(id: t.id))
                    }
                }
            }
        }
    }

    @ViewBuilder private var documentsSectionView: some View {
        if !docResults.isEmpty {
            resultSection("Documents", icon: "doc.fill", color: .orange) {
                ForEach(docResults.prefix(8)) { d in
                    resultRow(d.name, subtitle: d.expiresDisplay ?? String(localized: "No expiry"),
                              icon: "doc.fill", color: .orange,
                              isLast: d.id == docResults.prefix(8).last?.id) {
                        navigateAway(route: .documents(id: nil))
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
                        navigateAway(route: .finances)
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
                        navigateAway(route: .supplies)
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
                              subtitle: p.needsWatering ? String(localized: "Needs watering") : p.wateringLabel,
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

    @ViewBuilder private var chatSectionView: some View {
        if !chatHits.isEmpty {
            resultSection("Chat", icon: "bubble.left.and.bubble.right.fill", color: .blue) {
                ForEach(chatHits) { hit in
                    let contacts = SharedContactPayload.decode(hit.body)
                    resultRow(chatDisplayText(hit.body, contacts: contacts),
                              subtitle: hit.senderName ?? "",
                              icon: contacts.isEmpty ? "bubble.left.fill" : "person.crop.circle.fill",
                              color: .blue,
                              isLast: hit.id == chatHits.last?.id) {
                        navigateAway(route: .chat)
                    }
                }
            }
        }
    }

    @ViewBuilder private var contractorsSectionView: some View {
        if !contractorResults.isEmpty {
            resultSection("Contractors", icon: "wrench.and.screwdriver.fill", color: .orange) {
                ForEach(contractorResults.prefix(8)) { c in
                    resultRow(c.name, subtitle: c.category,
                              icon: "wrench.and.screwdriver.fill", color: .orange,
                              isLast: c.id == contractorResults.prefix(8).last?.id) {
                        navigateAway(route: .contractors)
                    }
                }
            }
        }
    }

    @ViewBuilder private var zonesSectionView: some View {
        if !zoneResults.isEmpty {
            resultSection("Property Zones", icon: "square.grid.2x2.fill", color: .teal) {
                ForEach(zoneResults.prefix(8)) { z in
                    resultRow(z.name, subtitle: z.notes ?? "",
                              icon: z.icon, color: Color(hex: z.colorHex) ?? .teal,
                              isLast: z.id == zoneResults.prefix(8).last?.id) {
                        navigateAway(route: .twin)
                    }
                }
            }
        }
    }

    @ViewBuilder private var paintSectionView: some View {
        if !paintResults.isEmpty {
            resultSection("Paint Colors", icon: "paintpalette.fill", color: .pink) {
                ForEach(paintResults.prefix(8)) { p in
                    resultRow(p.colorName, subtitle: paintSubtitle(p),
                              icon: "paintpalette.fill",
                              color: Color(hex: p.hexColor ?? "") ?? .pink,
                              isLast: p.id == paintResults.prefix(8).last?.id) {
                        navigateAway(route: .paintColors)
                    }
                }
            }
        }
    }

    @ViewBuilder private var journalSectionView: some View {
        if !journalResults.isEmpty {
            resultSection("Photo Journal", icon: "photo.fill", color: .pink) {
                ForEach(journalResults.prefix(8)) { e in
                    resultRow(e.title, subtitle: e.caption ?? "",
                              icon: "photo.fill", color: .pink,
                              isLast: e.id == journalResults.prefix(8).last?.id) {
                        navigateAway(route: .photoJournal)
                    }
                }
            }
        }
    }

    /// A chat body must always read like a message in results — structured
    /// payloads (shared contacts) render as their human meaning, never as
    /// wire-format JSON.
    private func chatDisplayText(_ body: String?, contacts: [SharedContactPayload]) -> String {
        guard !contacts.isEmpty else { return body ?? "" }
        let names = contacts.map(\.name).joined(separator: ", ")
        return String(format: String(localized: "search_shared_contact"), names)
    }

    // MARK: - Subtitle helpers (extracted to avoid type-checker timeout)

    private func paintSubtitle(_ p: PaintColor) -> String {
        let parts: [String?] = [p.roomName, p.brand, p.code]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

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

    private func navigateAway(route: AppRouter.AppRoute) {
        // Capture the router strongly BEFORE dismiss — the environment becomes
        // inaccessible once the view is torn down. The route is parked in
        // pendingRoute; the presenting sheet's onDismiss drains it once the
        // dismissal really ends — event-driven, no timers, no dropped sheets.
        let r = router
        r.pendingRoute = route
        dismiss()
    }

    // MARK: - Helpers

    private func resultSection<C: View>(_ title: String, icon: String, color: Color,
                                         @ViewBuilder content: () -> C) -> some View {
        let body = content()
        return VStack(alignment: .leading, spacing: 8) {
            Label(LocalizedStringKey(title), systemImage: icon)
                .font(AppFont.label)
                .foregroundStyle(color)
                .tracking(0.5)
                .padding(.leading, AppSpacing.xxs)
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
                    Image(systemName: icon)
                        .font(AppFont.captionStrong)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(color)
                        .frame(width: 30, height: 30)
                        .glassRoundedRect(AppRadius.sm)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(AppFont.footnote)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if !subtitle.isEmpty {
                            Text(LocalizedStringKey(subtitle))
                                .font(AppFont.scaled(12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(Color.primary.opacity(0.22))
                }
                .padding(.horizontal, AppSpacing.base)
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
