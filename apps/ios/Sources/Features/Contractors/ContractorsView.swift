import SwiftUI

struct ContractorModel: Identifiable, Codable {
    let id: UUID
    var name: String
    var specialty: String
    var phone: String
    var email: String?
    var notes: String?
    var rating: Int?
    let createdAt: String
    enum CodingKeys: String, CodingKey {
        case id, name, specialty, phone, email, notes, rating
        case createdAt = "created_at"
    }
    var specialtyIcon: String {
        switch specialty.lowercased() {
        case let s where s.contains("electr"): return "bolt.fill"
        case let s where s.contains("plumb"): return "drop.fill"
        case let s where s.contains("paint"): return "paintbrush.fill"
        case let s where s.contains("roof"): return "house.fill"
        case let s where s.contains("hvac"), let s where s.contains("heat"): return "thermometer.medium"
        case let s where s.contains("clean"): return "sparkles"
        default: return "wrench.and.screwdriver.fill"
        }
    }
}

@MainActor
final class ContractorService: ObservableObject {
    @Published var contractors: [ContractorModel] = []
    @Published var isLoading = false
    @Published var error: String?

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            contractors = try await supabase
                .from("contractors")
                .select()
                .order("name")
                .execute()
                .value
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
    let userId: UUID?
    let name: String
    let specialty: String
    let phone: String
    let email: String?
    let notes: String?
    let createdAt: String
    enum CodingKeys: String, CodingKey {
        case name, specialty, phone, email, notes
        case userId = "user_id"
        case createdAt = "created_at"
    }
}

struct ContractorsView: View {
    @StateObject private var service = ContractorService()
    @EnvironmentObject private var auth: AuthService
    @State private var showAdd = false
    @State private var search = ""

    var filtered: [ContractorModel] {
        guard !search.isEmpty else { return service.contractors }
        return service.contractors.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.specialty.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                if !service.contractors.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.4))
                        TextField("Search…", text: $search).font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 20).padding(.bottom, 12)
                }

                if service.isLoading {
                    Spacer(); ProgressView().tint(.white); Spacer()
                } else if filtered.isEmpty {
                    VStack(spacing: 14) {
                        Spacer()
                        Image(systemName: "person.badge.key.fill").font(.system(size: 44)).foregroundStyle(Color.primary.opacity(0.18))
                        Text(service.contractors.isEmpty ? "No contractors yet" : "No results").font(.system(size: 17)).foregroundStyle(Color.primary.opacity(0.5))
                        if service.contractors.isEmpty {
                            Button("Add your first contractor") { showAdd = true }.font(.system(size: 14)).foregroundStyle(.accentColor)
                        }
                        Spacer()
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(filtered) { c in
                                ContractorRow(contractor: c)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            HapticFeedback.warning()
                                            Task { await service.delete(c) }
                                        } label: { Label("Delete", systemImage: "trash") }
                                    }
                            }
                        }
                        .padding(.horizontal, 20).padding(.bottom, 110)
                    }
                }
            }
        }
        .task { await service.load() }
        .sheet(isPresented: $showAdd) { AddContractorSheet(service: service, userId: auth.session?.user.id) }
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
        .floatingSpeedDial(.contractors)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true; HapticFeedback.impact(.medium) } label: {
                    Image(systemName: "plus").font(.system(size: 17, weight: .semibold)).foregroundStyle(.primary)
                }
            }
        }
    }
}

private struct ContractorRow: View {
    let contractor: ContractorModel
    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                ColoredIconBadge(icon: contractor.specialtyIcon, color: .blue, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(contractor.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                    Text(contractor.specialty.capitalized).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.45))
                }
                Spacer()
                if !contractor.phone.isEmpty {
                    Button {
                        HapticFeedback.impact(.light)
                        if let url = URL(string: "tel://\(contractor.phone.filter { $0.isNumber })") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)
                            .frame(width: 38, height: 38)
                    }
                    .glassCircle()
                }
            }
        }
    }
}

private struct AddContractorSheet: View {
    @ObservedObject var service: ContractorService
    let userId: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var specialty = ""; @State private var phone = ""
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
                            fieldRow("wrench.fill", "Specialty (e.g. Plumber)", $specialty)
                            divider
                            fieldRow("phone.fill", "Phone", $phone, keyboard: .phonePad)
                            divider
                            fieldRow("envelope.fill", "Email (optional)", $email, keyboard: .emailAddress)
                            divider
                            fieldRow("note.text", "Notes (optional)", $notes)
                        }
                    }
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
                    .padding(.horizontal, 20).padding(.top, 8)
                }
            }
            .navigationTitle("Add Contractor").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(0.7)) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.accentColor)
                        .disabled(name.isEmpty || specialty.isEmpty || phone.isEmpty || isSaving)
                }
            }
        }
    }

    private func fieldRow(_ icon: String, _ placeholder: String, _ binding: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(.accentColor).frame(width: 28)
            TextField(placeholder, text: binding).font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor).keyboardType(keyboard)
        }.padding(.horizontal, 16).padding(.vertical, 13)
    }
    private var divider: some View { Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52) }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let c = NewContractor(userId: userId, name: name, specialty: specialty, phone: phone,
                              email: email.isEmpty ? nil : email, notes: notes.isEmpty ? nil : notes,
                              createdAt: ISO8601DateFormatter().string(from: Date()))
        try? await service.add(c)
        HapticFeedback.success()
        dismiss()
    }
}
