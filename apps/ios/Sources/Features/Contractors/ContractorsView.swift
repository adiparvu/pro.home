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
    @Environment(FamilyService.self) private var familyService
    @Environment(FinancialService.self) private var financialService
    @Environment(TaskService.self) private var taskService
    @Environment(ProfileService.self) private var profileService
    @Environment(DirectMessageService.self) private var directMessageService
    @State private var showAdd = false
    @State private var selectedContractor: ContractorModel? = nil
    @State private var editContractor: ContractorModel? = nil
    @State private var deleteCandidate: ContractorModel? = nil
    /// Matched member whose in-app DM thread is being opened from a row.
    @State private var dmMember: FamilyMember? = nil
    /// Matched member for the chat surface's own call affordance (the same
    /// CallPickerSheet DirectMessageView presents from its header).
    @State private var callMember: FamilyMember? = nil
    @State private var search = ""
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

    /// Contractor id → property member with a PRVIO account, rebuilt from the
    /// already-loaded in-memory lists (O(n + m), no network).
    private var accountMatches: [UUID: FamilyMember] {
        ContractorAccountMatch.matches(contractors: service.contractors,
                                       members: familyService.members)
    }

    /// Compact "history on this property" figure for the peek card: how many
    /// already-loaded financial records and tasks mention the contractor by
    /// name. Pure in-memory sweep, evaluated only when a preview is presented.
    private func historyCount(for contractor: ContractorModel) -> Int {
        let name = contractor.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count >= 3 else { return 0 }
        let financial = financialService.records.filter {
            $0.title.localizedCaseInsensitiveContains(name) ||
            ($0.description?.localizedCaseInsensitiveContains(name) ?? false)
        }.count
        let tasks = taskService.tasks.filter {
            $0.title.localizedCaseInsensitiveContains(name) ||
            ($0.notes?.localizedCaseInsensitiveContains(name) ?? false)
        }.count
        return financial + tasks
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
                        LazyVStack(spacing: 10) {
                            // Hoisted: one O(n + m) index build per render,
                            // not one per row.
                            let matches = accountMatches
                            ForEach(filtered) { c in
                                let matched = matches[c.id]
                                ContractorRow(contractor: c,
                                              isFavorite: ContractorFavoritesStore.isFavorite(c.id),
                                              matchedMember: matched,
                                              onOpenDM: { dmMember = $0 },
                                              onOpenCallPicker: { callMember = $0 })
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        HapticFeedback.selection()
                                        selectedContractor = c
                                    }
                                    .contextMenu {
                                        if let phone = c.phone, !phone.isEmpty {
                                            Button { call(phone) } label: { Label("Call", systemImage: "phone.fill") }
                                        }
                                        if matched != nil || c.phone?.isEmpty == false {
                                            Button {
                                                if let matched {
                                                    HapticFeedback.selection()
                                                    dmMember = matched
                                                } else if let phone = c.phone {
                                                    openContactURL("sms://\(contactURLDigits(phone))")
                                                }
                                            } label: { Label("Message", systemImage: "message.fill") }
                                        }
                                        if let phone = c.phone, !phone.isEmpty {
                                            Button {
                                                openContactURL("facetime://\(contactURLDigits(phone))")
                                            } label: { Label("FaceTime", systemImage: "video.fill") }
                                        }
                                        if let email = c.email, !email.isEmpty {
                                            Button {
                                                openContactURL("mailto:\(email)")
                                            } label: { Label("Email", systemImage: "envelope.fill") }
                                        }
                                        Button {
                                            HapticFeedback.selection()
                                            ContractorFavoritesStore.toggle(c.id); favRefresh += 1
                                        } label: {
                                            Label(ContractorFavoritesStore.isFavorite(c.id) ? "Remove from favorites" : "Add to favorites",
                                                  systemImage: ContractorFavoritesStore.isFavorite(c.id) ? "star.slash" : "star")
                                        }
                                        Button { editContractor = c } label: { Label("Edit", systemImage: "pencil") }
                                        Divider()
                                        Button(role: .destructive) {
                                            deleteCandidate = c
                                        } label: { Label("Delete", systemImage: "trash") }
                                    } preview: {
                                        ContractorPeekCard(contractor: c,
                                                           member: matched,
                                                           historyCount: historyCount(for: c))
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            deleteCandidate = c
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
        .task {
            // Members power the PRVIO-account matching; they are loaded at
            // startup, so this only refetches after a cold cache.
            async let contractorsLoad: Void = service.load()
            if familyService.members.isEmpty { await familyService.load() }
            await contractorsLoad
        }
        .sheet(isPresented: $showAdd) {
            AddContractorSheet(service: service, propertyId: propertyService.primary?.id, userId: auth.session?.user.id)
        }
        .sheet(item: $selectedContractor) { c in
            ContractorDetailSheet(contractor: c, service: service)
        }
        .sheet(item: $editContractor) { c in
            EditContractorSheet(contractor: c, service: service)
        }
        // Full-height in-app DM with the matched member — the same
        // construction ConversationsView uses (DirectMessageView reads
        // everything else, including myName, from the environment). The task
        // mirrors ConversationsView's bootstrap so the thread has history and
        // realtime even when the chat tab was never visited this session.
        .sheet(item: $dmMember) { member in
            NavigationStack {
                DirectMessageView(member: member)
            }
            .task {
                guard let pid = propertyService.primary?.id else { return }
                let myName = profileService.profile?.preferredName
                    ?? profileService.profile?.fullName ?? "Me"
                directMessageService.myName = myName
                await directMessageService.load(propertyId: pid, myName: myName)
                await directMessageService.subscribeRealtime(propertyId: pid, myName: myName)
            }
        }
        // Mirrors DirectMessageView's own header call affordance.
        .sheet(item: $callMember) { member in
            CallPickerSheet(members: [member], isVideo: false)
        }
        .confirmationDialog(
            Text("Delete \(deleteCandidate?.name ?? "")?"),
            isPresented: Binding(
                get: { deleteCandidate != nil },
                set: { if !$0 { deleteCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Contractor", role: .destructive) {
                guard let c = deleteCandidate else { return }
                deleteCandidate = nil
                HapticFeedback.warning()
                Task { await service.delete(c) }
            }
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
        .searchable(text: $search,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: Text("Search…"))
        .floatingSpeedDial(.contractors)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
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
    /// Property member with a PRVIO account matching this contractor, if any.
    var matchedMember: FamilyMember? = nil
    /// Opens the in-app 1:1 DM with the matched member (default tap on the
    /// message icon when matched).
    var onOpenDM: (FamilyMember) -> Void = { _ in }
    /// Presents the chat surface's call affordance for the matched member
    /// (default tap on the call icon when matched).
    var onOpenCallPicker: (FamilyMember) -> Void = { _ in }

    /// Channel data: the contractor's own fields, falling back to the matched
    /// member's profile so a linked account stays reachable either way.
    private var channelPhone: String? {
        nonEmpty(contractor.phone) ?? nonEmpty(matchedMember?.phone)
    }
    private var channelEmail: String? {
        nonEmpty(contractor.email) ?? nonEmpty(matchedMember?.email)
    }
    private var hasChannels: Bool { channelPhone != nil || channelEmail != nil }

    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                ColoredIconBadge(icon: contractor.specialtyIcon, color: .blue, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(contractor.name).font(AppFont.subheadline).foregroundStyle(.primary).lineLimit(1)
                        if matchedMember != nil {
                            PRVIOAccountBadge()
                        }
                        if isFavorite {
                            Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(.yellow)
                        }
                    }
                    Text(LocalizedStringKey(contractor.specialty.capitalized)).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                }
                Spacer()
                // Two-layer quick actions: default tap = the primary channel
                // (in-app when the contractor has a PRVIO account), long-press
                // = a native menu of every other way to reach them.
                if matchedMember != nil || channelPhone != nil {
                    quickAction("message.fill", accessibility: "Message contractor") {
                        if let member = matchedMember {
                            onOpenDM(member)
                        } else if let phone = channelPhone {
                            openContactURL("sms://\(contactURLDigits(phone))")
                        }
                    }
                    quickAction("phone.fill", accessibility: "Call contractor") {
                        if let member = matchedMember {
                            onOpenCallPicker(member)
                        } else if let phone = channelPhone {
                            openContactURL("tel://\(contactURLDigits(phone))")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func quickAction(_ icon: String,
                             accessibility: LocalizedStringKey,
                             primary: @escaping () -> Void) -> some View {
        Group {
            if hasChannels {
                Menu {
                    ContractorChannelMenu(phone: channelPhone, email: channelEmail)
                } label: {
                    quickActionIcon(icon)
                } primaryAction: {
                    HapticFeedback.impact(.light)
                    primary()
                }
            } else {
                Button {
                    HapticFeedback.impact(.light)
                    primary()
                } label: {
                    quickActionIcon(icon)
                }
            }
        }
        .glassCircle()
        .accessibilityLabel(accessibility)
    }

    private func quickActionIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 16))
            .foregroundStyle(.primary)
            .frame(width: 38, height: 38)
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

// MARK: - Contact plumbing (shared by row + context menu)

/// Digits (plus leading "+") suitable for tel:/sms:/facetime: URLs.
private func contactURLDigits(_ phone: String) -> String {
    phone.filter { $0.isNumber || $0 == "+" }
}

private func openContactURL(_ raw: String) {
    HapticFeedback.impact(.light)
    guard let url = URL(string: raw) else { return }
    UIApplication.shared.open(url)
}

/// Long-press menu on the row's quick-action icons: every other channel for
/// reaching the contractor, built only from data that actually exists.
private struct ContractorChannelMenu: View {
    let phone: String?
    let email: String?

    var body: some View {
        Section("Alege cum contactezi") {
            if let phone, !phone.isEmpty {
                let urlDigits = contactURLDigits(phone)
                let bareDigits = phone.filter(\.isNumber)
                Button {
                    openContactURL("facetime://\(urlDigits)")
                } label: { Label("FaceTime", systemImage: "video.fill") }
                Button {
                    openContactURL("facetime-audio://\(urlDigits)")
                } label: { Label("FaceTime Audio", systemImage: "phone.and.waveform.fill") }
                Button {
                    openContactURL("https://wa.me/\(bareDigits)")
                } label: { Label("WhatsApp", systemImage: "message.fill") }
                Button {
                    openContactURL("tg://resolve?phone=\(bareDigits)")
                } label: { Label("Telegram", systemImage: "paperplane.fill") }
                Button {
                    openContactURL("sms://\(urlDigits)")
                } label: { Label("Mesaj SMS", systemImage: "bubble.left.fill") }
                Button {
                    openContactURL("tel://\(urlDigits)")
                } label: { Label("Sună clasic", systemImage: "phone.fill") }
            } else if let email, !email.isEmpty {
                // No phone on file: FaceTime still works against the account
                // email; every phone-bound channel is deliberately absent.
                Button {
                    openContactURL("facetime://\(email)")
                } label: { Label("FaceTime", systemImage: "video.fill") }
                Button {
                    openContactURL("facetime-audio://\(email)")
                } label: { Label("FaceTime Audio", systemImage: "phone.and.waveform.fill") }
            }
        }
    }
}

// MARK: - PRVIO account badge

/// Small monochrome glass capsule marking contractors who also have a PRVIO
/// account on this property.
struct PRVIOAccountBadge: View {
    var body: some View {
        Text(verbatim: "PRVIO")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .glassCapsule()
            .accessibilityLabel(Text("Are cont PRVIO"))
    }
}

// MARK: - Long-press peek card

/// Rich `.contextMenu` preview for a contractor row: avatar (member photo when
/// the contractor has a PRVIO account, monochrome initials on glass
/// otherwise), name + trade, contact rows, and a compact history line
/// computed from data already in memory.
struct ContractorPeekCard: View {
    let contractor: ContractorModel
    let member: FamilyMember?
    let historyCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            HStack(spacing: 14) {
                avatar
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(contractor.name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if member != nil {
                            PRVIOAccountBadge()
                        }
                    }
                    Text(LocalizedStringKey(contractor.specialty.capitalized))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                }
                Spacer(minLength: 0)
            }
            if contractor.phone?.isEmpty == false || contractor.email?.isEmpty == false {
                VStack(alignment: .leading, spacing: 10) {
                    if let phone = contractor.phone, !phone.isEmpty {
                        contactLine("phone.fill", phone)
                    }
                    if let email = contractor.email, !email.isEmpty {
                        contactLine("envelope.fill", email)
                    }
                }
            }
            if historyCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                    Text("Activitate pe proprietate: \(historyCount)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                }
            }
        }
        .padding(AppSpacing.xl)
        .frame(width: 340, alignment: .leading)
        .background(.regularMaterial)
    }

    @ViewBuilder private var avatar: some View {
        if let member {
            MemberAvatar(member: member, size: 56)
        } else {
            ZStack {
                Circle().fill(.ultraThinMaterial)
                Circle().strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 1)
                Text(initials)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
            }
            .frame(width: 56, height: 56)
        }
    }

    private var initials: String {
        let parts = contractor.name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(contractor.name.prefix(2)).uppercased()
    }

    private func contactLine(_ icon: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                .frame(width: 20)
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .lineLimit(1)
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
