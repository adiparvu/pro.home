import SwiftUI
import Observation

struct ContractorModel: Identifiable, Codable {
    let id: UUID
    var name: String
    var category: String    // DB column: category
    var phone: String?
    var email: String?
    var notes: String?
    var rating: Int?
    var isPreferred: Bool
    var website: String?
    var address: String?

    enum CodingKeys: String, CodingKey {
        case id, name, category, phone, email, notes, rating, website, address
        case isPreferred = "is_preferred"
    }

    var specialty: String { category }  // backward-compat alias for UI

    var specialtyIcon: String {
        switch category.lowercased() {
        case let s where s.contains("electr"): return "bolt.fill"
        case let s where s.contains("plumb"): return "drop.fill"
        case let s where s.contains("paint"): return "paintbrush.fill"
        case let s where s.contains("roof"): return "house.fill"
        case let s where s.contains("hvac"), let s where s.contains("heat"): return "thermometer.medium"
        case let s where s.contains("clean"): return "sparkles"
        case let s where s.contains("garden"), let s where s.contains("landscape"): return "leaf.fill"
        default: return "wrench.and.screwdriver.fill"
        }
    }
}

@MainActor
@Observable
final class ContractorService {
    var contractors: [ContractorModel] = []
    var isLoading = false
    var error: String?

    func load() async {
        let pid = PropertyService.activePropertyId
        // Paint the last known state instantly; the network refresh follows.
        if contractors.isEmpty, let cached = ServiceCache.load([ContractorModel].self, entity: "contractors", propertyId: pid) {
            contractors = cached
        }
        isLoading = true
        defer { isLoading = false }
        do {
            // RLS scopes this to the caller's household; the property filter
            // narrows it to the selected home and the cap just prevents an
            // unbounded select as the table grows over the years.
            contractors = try await PropertyRepo.fetch(table: "contractors", propertyId: pid,
                                                       order: "name", ascending: true, limit: 500)
            ServiceCache.save(contractors, entity: "contractors", propertyId: pid)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func add(_ c: NewContractor) async throws {
        let result: ContractorModel = try await supabase
            .from("contractors").insert(c).select().single().execute().value
        contractors.append(result)
        contractors.sort { $0.name < $1.name }
    }

    func update(_ c: ContractorModel) async {
        do {
            let result: ContractorModel = try await supabase
                .from("contractors")
                .update([
                    "name": c.name,
                    "category": c.category,
                    "phone": c.phone ?? "",
                    "email": c.email ?? "",
                    "notes": c.notes ?? "",
                    "rating": String(c.rating ?? 0),
                    "is_preferred": c.isPreferred ? "true" : "false",
                ])
                .eq("id", value: c.id.uuidString)
                .select()
                .single()
                .execute()
                .value
            if let i = contractors.firstIndex(where: { $0.id == c.id }) {
                contractors[i] = result
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func delete(_ c: ContractorModel) async {
        do {
            try await supabase.from("contractors").delete().eq("id", value: c.id.uuidString).execute()
            contractors.removeAll { $0.id == c.id }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct NewContractor: Encodable {
    let propertyId: UUID
    let createdBy: UUID?
    let name: String
    let category: String
    let phone: String?
    let email: String?
    let notes: String?
    let isPreferred: Bool
    enum CodingKeys: String, CodingKey {
        case name, category, phone, email, notes
        case propertyId  = "property_id"
        case createdBy   = "created_by"
        case isPreferred = "is_preferred"
    }
}

// Per-device contractor favorites (like starred documents).
enum ContractorFavoritesStore {
    private static let key = "prvio.contractor.favorites"
    static func ids() -> Set<String> { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
    static func isFavorite(_ id: UUID) -> Bool { ids().contains(id.uuidString) }
    @discardableResult
    static func toggle(_ id: UUID) -> Bool {
        var s = ids()
        let now: Bool
        if s.contains(id.uuidString) { s.remove(id.uuidString); now = false }
        else { s.insert(id.uuidString); now = true }
        UserDefaults.standard.set(Array(s), forKey: key)
        return now
    }
}

struct ContractorsView: View {
    @Environment(ContractorService.self) private var service
    @Environment(AuthService.self) private var auth
    @Environment(PropertyService.self) private var propertyService
    @State private var showAdd = false
    @State private var selectedContractor: ContractorModel? = nil
    @State private var editContractor: ContractorModel? = nil
    @State private var search = ""
    @State private var showSearch = false
    @State private var favoritesOnly = false
    @State private var favRefresh = 0

    var filtered: [ContractorModel] {
        _ = favRefresh
        var list = service.contractors
        if favoritesOnly {
            let favs = ContractorFavoritesStore.ids()
            list = list.filter { favs.contains($0.id.uuidString) }
        }
        guard !search.isEmpty else { return list }
        return list.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.specialty.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                if service.isLoading {
                    Spacer(); ProgressView().tint(.white); Spacer()
                } else if filtered.isEmpty {
                    VStack(spacing: 14) {
                        Spacer()
                        Image(systemName: "person.badge.key.fill").font(.system(size: 44)).foregroundStyle(Color.primary.opacity(0.18))
                        Text(LocalizedStringKey(service.contractors.isEmpty ? "No contractors yet" : "No results")).font(.system(size: 17)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        if service.contractors.isEmpty {
                            Button("Add your first contractor") { showAdd = true }.font(.system(size: 14)).foregroundStyle(Color.accentColor)
                        }
                        Spacer()
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(filtered) { c in
                                ContractorRow(contractor: c,
                                              isFavorite: ContractorFavoritesStore.isFavorite(c.id))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        HapticFeedback.selection()
                                        selectedContractor = c
                                    }
                                    .contextMenu {
                                        if let phone = c.phone, !phone.isEmpty {
                                            Button { call(phone) } label: { Label("Call", systemImage: "phone.fill") }
                                        }
                                        Button { editContractor = c } label: { Label("Edit", systemImage: "pencil") }
                                        Button {
                                            HapticFeedback.selection()
                                            ContractorFavoritesStore.toggle(c.id); favRefresh += 1
                                        } label: {
                                            Label(ContractorFavoritesStore.isFavorite(c.id) ? "Remove from favorites" : "Add to favorites",
                                                  systemImage: ContractorFavoritesStore.isFavorite(c.id) ? "star.slash" : "star")
                                        }
                                        Divider()
                                        Button(role: .destructive) {
                                            HapticFeedback.warning(); Task { await service.delete(c) }
                                        } label: { Label("Delete", systemImage: "trash") }
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            HapticFeedback.warning()
                                            Task { await service.delete(c) }
                                        } label: { Label("Delete", systemImage: "trash") }
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            HapticFeedback.selection()
                                            ContractorFavoritesStore.toggle(c.id); favRefresh += 1
                                        } label: {
                                            Label("Favorite", systemImage: "star")
                                        }.tint(.yellow)
                                    }
                            }
                        }
                        .padding(.horizontal, AppSpacing.xl).padding(.bottom, 110)
                    }
                    .refreshable { await service.load() }
                }
            }
        }
        .onChange(of: showSearch) { _, on in
            if !on { search = "" }
        }
        .task { await service.load() }
        .sheet(isPresented: $showAdd) {
            AddContractorSheet(service: service, propertyId: propertyService.primary?.id, userId: auth.session?.user.id)
        }
        .sheet(item: $selectedContractor) { c in
            ContractorDetailSheet(contractor: c, service: service)
        }
        .sheet(item: $editContractor) { c in
            EditContractorSheet(contractor: c, service: service)
        }
        .alert("Error", isPresented: Binding(
            get: { service.error != nil },
            set: { if !$0 { service.error = nil } }
        )) {
            Button("OK") { service.error = nil }
        } message: {
            Text(service.error ?? "")
        }
        .navigationTitle("Contractors")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $search, isPresented: $showSearch,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: Text("Search…"))
        .floatingSpeedDial(.contractors)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    SearchIconButton(isActive: $showSearch)
                    Button {
                        withAnimation(.snappy) { favoritesOnly.toggle() }
                        HapticFeedback.selection()
                    } label: {
                        Image(systemName: favoritesOnly ? "star.fill" : "star")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(favoritesOnly ? .yellow : .primary)
                            .frame(width: 34, height: 32)
                    }
                    .accessibilityLabel(favoritesOnly ? "Show all contractors" : "Show favorites")
                    Button { showAdd = true; HapticFeedback.impact(.medium) } label: {
                        Image(systemName: "plus").font(.system(size: 17, weight: .semibold)).foregroundStyle(.primary)
                            .frame(width: 34, height: 32)
                    }
                    .accessibilityLabel("Add contractor")
                }
            }
        }
    }

    private func call(_ phone: String) {
        HapticFeedback.impact(.light)
        if let url = URL(string: "tel://\(phone.filter { $0.isNumber })") {
            UIApplication.shared.open(url)
        }
    }
}

private struct ContractorRow: View {
    let contractor: ContractorModel
    var isFavorite: Bool = false
    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                ColoredIconBadge(icon: contractor.specialtyIcon, color: .blue, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(contractor.name).font(AppFont.subheadline).foregroundStyle(.primary)
                        if isFavorite {
                            Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(.yellow)
                        }
                    }
                    Text(LocalizedStringKey(contractor.specialty.capitalized)).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                }
                Spacer()
                if let phone = contractor.phone, !phone.isEmpty {
                    Button {
                        HapticFeedback.impact(.light)
                        if let url = URL(string: "tel://\(phone.filter { $0.isNumber })") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)
                            .frame(width: 38, height: 38)
                    }
                    .glassCircle()
                    .accessibilityLabel("Call contractor")
                }
            }
        }
    }
}

private struct AddContractorSheet: View {
    var service: ContractorService
    let propertyId: UUID?
    let userId: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var category = ""; @State private var phone = ""
    @State private var email = ""; @State private var notes = ""; @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Group {
                            fieldRow("person.fill", "Name", $name)
                            divider
                            fieldRow("wrench.fill", "Specialty (e.g. Plumber)", $category)
                            divider
                            fieldRow("phone.fill", "Phone", $phone, keyboard: .phonePad)
                            divider
                            fieldRow("envelope.fill", "Email (optional)", $email, keyboard: .emailAddress)
                            divider
                            fieldRow("note.text", "Notes (optional)", $notes)
                        }
                    }
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
                    .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.sm)
                }
            }
            .navigationTitle("Add Contractor").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(AppOpacity.emphasis)) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .font(AppFont.subheadline).foregroundStyle(Color.accentColor)
                        .disabled(name.isEmpty || category.isEmpty || isSaving)
                }
            }
        }
    }

    private func fieldRow(_ icon: String, _ placeholder: LocalizedStringKey, _ binding: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Color.accentColor).frame(width: 28)
            TextField(placeholder, text: binding).font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor).keyboardType(keyboard)
        }.padding(.horizontal, AppSpacing.lg).padding(.vertical, 13)
    }
    private var divider: some View { Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52) }

    private func save() async {
        guard let pid = propertyId else { dismiss(); return }
        isSaving = true
        defer { isSaving = false }
        let c = NewContractor(
            propertyId: pid,
            createdBy: userId,
            name: name,
            category: category,
            phone: phone.isEmpty ? nil : phone,
            email: email.isEmpty ? nil : email,
            notes: notes.isEmpty ? nil : notes,
            isPreferred: false
        )
        try? await service.add(c)
        HapticFeedback.success()
        dismiss()
    }
}
