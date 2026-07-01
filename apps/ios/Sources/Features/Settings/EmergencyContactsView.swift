import SwiftUI

struct EmergencyContact: Identifiable, Codable {
    var id = UUID()
    var name: String
    var role: String
    var phone: String
    var color: String = "red"
}

struct EmergencyContactsView: View {
    @State private var contacts: [EmergencyContact] = []
    @State private var showAdd = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                PageHeader(titleKey: "Emergency Contacts")
                systemServicesSection
                if !contacts.isEmpty { customSection }
                addButton
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { load() }
        .sheet(isPresented: $showAdd) { AddEmergencySheet { save() } onSave: { c in contacts.append(c); save() } }
    }

    private var systemServicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("QUICK DIAL")
            VStack(spacing: 8) {
                ForEach(systemContacts, id: \.name) { c in
                    EmergencyRow(contact: c, isSystem: true)
                }
            }
        }
    }

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("MY CONTACTS")
            VStack(spacing: 8) {
                ForEach(contacts) { c in
                    EmergencyRow(contact: c, isSystem: false)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                contacts.removeAll { $0.id == c.id }
                                save()
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                }
            }
        }
    }

    private var addButton: some View {
        Button { showAdd = true; HapticFeedback.impact(.medium) } label: {
            Label("Add Contact", systemImage: "plus")
                .font(AppFont.footnoteEmphasis)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ t: LocalizedStringKey) -> some View {
        Text(t).font(AppFont.label).foregroundStyle(Color.primary.opacity(AppOpacity.disabled)).padding(.leading, 4)
    }

    private let systemContacts: [EmergencyContact] = [
        EmergencyContact(name: "Emergency", role: "Police / Fire / Ambulance", phone: "112", color: "red"),
        EmergencyContact(name: "Police", role: "Non-emergency", phone: "112", color: "blue"),
        EmergencyContact(name: "Gas Emergency", role: "Gas leak & emergencies", phone: "0800-001122", color: "orange"),
    ]

    private func load() {
        if let d = UserDefaults.standard.data(forKey: "prvio.emergency"),
           let decoded = try? JSONDecoder().decode([EmergencyContact].self, from: d) {
            contacts = decoded
        }
    }
    private func save() {
        if let d = try? JSONEncoder().encode(contacts) { UserDefaults.standard.set(d, forKey: "prvio.emergency") }
    }
}

private struct EmergencyRow: View {
    let contact: EmergencyContact
    let isSystem: Bool
    private var color: Color {
        switch contact.color {
        case "blue": return .blue
        case "orange": return .orange
        case "green": return Color(red: 0.3, green: 0.85, blue: 0.5)
        default: return .red
        }
    }
    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.18)).frame(width: 44, height: 44)
                    Image(systemName: isSystem ? "phone.fill" : "person.fill").font(.system(size: 18)).foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(contact.name).font(AppFont.subheadline).foregroundStyle(.primary)
                    Text(contact.role).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.4))
                }
                Spacer()
                Button {
                    HapticFeedback.impact(.heavy)
                    if let url = URL(string: "tel://\(contact.phone.filter { $0.isNumber || $0 == "+" })") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text(contact.phone)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                }
                .glassCapsule()
            }
        }
    }
}

private struct AddEmergencySheet: View {
    let onDismiss: () -> Void
    let onSave: (EmergencyContact) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var role = ""; @State private var phone = ""

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                VStack(spacing: 0) {
                    fieldRow("person.fill", "Name (e.g. Electrician)", $name)
                    divider
                    fieldRow("briefcase.fill", "Role / Company", $role)
                    divider
                    fieldRow("phone.fill", "Phone number", $phone, keyboard: .phonePad)
                }
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
                .padding(.horizontal, 20).padding(.top, 8)
                Spacer()
            }
            .navigationTitle("Add Contact").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(AppOpacity.emphasis)) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(EmergencyContact(name: name, role: role, phone: phone))
                        dismiss()
                    }.font(AppFont.subheadline).foregroundStyle(.blue).disabled(name.isEmpty || phone.isEmpty)
                }
            }
        }
    }

    private func fieldRow(_ icon: String, _ placeholder: String, _ binding: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(.blue).frame(width: 28)
            TextField(placeholder, text: binding).font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor).keyboardType(keyboard)
        }.padding(.horizontal, 16).padding(.vertical, 13)
    }
    private var divider: some View { Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52) }
}
