import SwiftUI

// MARK: - Model

struct TrustedPerson: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var email: String
    var canEmergencyAccess: Bool = false
    var canApproveRecovery: Bool = false
    var canTransferOwnership: Bool = false

    var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String((parts[0].first ?? "?")) + String((parts[1].first ?? "?"))
        }
        return String(name.prefix(2)).uppercased()
    }
}

// MARK: - Main view

struct TrustedPersonsView: View {
    @State private var persons: [TrustedPerson] = []
    @State private var showAdd = false

    private let key = "prvio.trustedPersons"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                if persons.isEmpty {
                    emptyState
                } else {
                    personsList
                }
                addButton
                footerText
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Persoane de încredere")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { load() }
        .sheet(isPresented: $showAdd) {
            AddTrustedPersonSheet { person in
                persons.append(person)
                save()
            }
        }
    }

    // MARK: - Persons list

    private var personsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PERSOANE DE ÎNCREDERE")
                .font(AppFont.label)
                .foregroundStyle(Color.primary.opacity(0.35))
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(persons.enumerated()), id: \.element.id) { idx, person in
                    if idx > 0 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.06))
                            .frame(height: 0.4)
                            .padding(.leading, 62)
                    }
                    personRow(person)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                persons.removeAll { $0.id == person.id }
                                save()
                            } label: {
                                Label("Șterge", systemImage: "trash")
                            }
                        }
                }
            }
            .liquidGlass(cornerRadius: 20)
        }
    }

    private func personRow(_ person: TrustedPerson) -> some View {
        HStack(spacing: 12) {
            // Initials circle
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(red: 0.35, green: 0.5, blue: 1.0), Color(red: 0.55, green: 0.3, blue: 1.0)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 40, height: 40)
                Text(person.initials)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(person.name)
                    .font(AppFont.body)
                    .foregroundStyle(.primary)
                Text(person.email)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.4))
                    .lineLimit(1)
                if person.canEmergencyAccess || person.canApproveRecovery || person.canTransferOwnership {
                    permissionTags(person)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func permissionTags(_ person: TrustedPerson) -> some View {
        HStack(spacing: 4) {
            if person.canEmergencyAccess {
                permTag("Urgență", color: .orange)
            }
            if person.canApproveRecovery {
                permTag("Recuperare", color: .blue)
            }
            if person.canTransferOwnership {
                permTag("Transfer", color: .purple)
            }
        }
    }

    private func permTag(_ label: String, color: Color) -> some View {
        Text(LocalizedStringKey(label))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 64, height: 64)
                Image(systemName: "person.2.badge.key.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.primary.opacity(0.3))
            }
            Text("Nicio persoană de încredere")
                .font(AppFont.body)
                .foregroundStyle(.primary)
            Text("Adaugă persoane care te pot ajuta cu recuperarea contului")
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Add button

    private var addButton: some View {
        Button {
            showAdd = true
            HapticFeedback.impact(.medium)
        } label: {
            Label("Adaugă persoană", systemImage: "plus")
                .font(AppFont.footnoteEmphasis)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private var footerText: some View {
        Text("Persoanele de încredere te pot ajuta cu recuperarea contului și accesul de urgență.")
            .font(.system(size: 12))
            .foregroundStyle(Color.primary.opacity(0.38))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([TrustedPerson].self, from: data)
        else { return }
        persons = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(persons) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Add sheet

private struct AddTrustedPersonSheet: View {
    let onSave: (TrustedPerson) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var canEmergencyAccess = false
    @State private var canApproveRecovery = false
    @State private var canTransferOwnership = false

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        email.contains("@")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Info fields
                        VStack(alignment: .leading, spacing: 8) {
                            Text("DETALII")
                                .font(AppFont.label)
                                .foregroundStyle(Color.primary.opacity(0.35))
                                .padding(.leading, 4)

                            VStack(spacing: 0) {
                                fieldRow(icon: "person.fill", color: .blue, placeholder: "Nume complet", text: $name, keyboard: .default)
                                rowDivider
                                fieldRow(icon: "envelope.fill", color: .indigo, placeholder: "Adresă email", text: $email, keyboard: .emailAddress)
                            }
                            .liquidGlass(cornerRadius: 16)
                        }

                        // Permissions
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PERMISIUNI")
                                .font(AppFont.label)
                                .foregroundStyle(Color.primary.opacity(0.35))
                                .padding(.leading, 4)

                            VStack(spacing: 0) {
                                toggleRow(icon: "exclamationmark.shield.fill", color: .orange,
                                          title: "Acces de urgență",
                                          subtitle: "Poate solicita acces în situații de urgență",
                                          isOn: $canEmergencyAccess)
                                rowDivider
                                toggleRow(icon: "checkmark.shield.fill", color: .blue,
                                          title: "Aprobare recuperare",
                                          subtitle: "Poate aproba recuperarea contului tău",
                                          isOn: $canApproveRecovery)
                                rowDivider
                                toggleRow(icon: "arrow.triangle.swap", color: .purple,
                                          title: "Transfer proprietate",
                                          subtitle: "Poate prelua proprietatea contului",
                                          isOn: $canTransferOwnership)
                            }
                            .liquidGlass(cornerRadius: 16)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Adaugă persoană")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anulează") { dismiss() }
                        .foregroundStyle(Color.primary.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvează") {
                        let person = TrustedPerson(
                            name: name.trimmingCharacters(in: .whitespaces),
                            email: email.trimmingCharacters(in: .whitespaces),
                            canEmergencyAccess: canEmergencyAccess,
                            canApproveRecovery: canApproveRecovery,
                            canTransferOwnership: canTransferOwnership
                        )
                        onSave(person)
                        dismiss()
                    }
                    .font(AppFont.subheadline)
                    .foregroundStyle(isValid ? .blue : Color.primary.opacity(0.3))
                    .disabled(!isValid)
                }
            }
        }
    }

    private func fieldRow(icon: String, color: Color, placeholder: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color)
            TextField(placeholder, text: text)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .tint(.blue)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    private func toggleRow(icon: String, color: Color, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                Text(LocalizedStringKey(subtitle))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.primary.opacity(0.4))
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 0.4)
            .padding(.leading, 54)
    }
}
