import SwiftUI

struct TrustedContactView: View {
    @EnvironmentObject private var auth: AuthService
    @State private var name: String = ""
    @State private var phone: String = ""
    @State private var relationship: String = ""
    @State private var isSaving = false
    @State private var saved = false
    @State private var showRemoveConfirm = false

    private var hasContact: Bool { !savedName.isEmpty }
    @AppStorage("prvio.trustedContact.name")         private var savedName: String = ""
    @AppStorage("prvio.trustedContact.phone")        private var savedPhone: String = ""
    @AppStorage("prvio.trustedContact.relationship") private var savedRelationship: String = ""

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        phone.trimmingCharacters(in: .whitespaces).count >= 7
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                headerCard
                formSection
                if hasContact { removeButton }
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Contact de Încredere")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Group {
                    if isSaving {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button("Salvează") { save() }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(isValid ? .blue : Color.primary.opacity(0.3))
                            .disabled(!isValid)
                    }
                }
            }
        }
        .confirmationDialog("Elimină contactul de încredere?", isPresented: $showRemoveConfirm, titleVisibility: .visible) {
            Button("Elimină", role: .destructive) { removeContact() }
            Button("Anulează", role: .cancel) {}
        } message: {
            Text("Informațiile despre \(savedName) vor fi șterse.")
        }
        .onAppear { loadSaved() }
        .overlay(alignment: .bottom) {
            if saved {
                savedBadge
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 100)
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(red: 0.25, green: 0.55, blue: 1.0), Color(red: 0.55, green: 0.25, blue: 1.0)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 64, height: 64)
                Image(systemName: "person.badge.shield.checkmark.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text("Persoana ta de contact în caz de urgență")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Text("Această persoană poate fi notificată în situații de urgență legate de locuința ta. Informațiile sunt stocate local pe dispozitiv.")
                .font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .liquidGlass(cornerRadius: 20)
    }

    // MARK: - Form

    private var formSection: some View {
        SettingsGroup(title: "Detalii contact") {
            VStack(spacing: 0) {
                fieldRow(icon: "person.fill", color: .blue, placeholder: "Nume complet", text: $name, keyboard: .default)
                rowDivider
                fieldRow(icon: "phone.fill", color: Color(red: 0.3, green: 0.85, blue: 0.5), placeholder: "Număr de telefon", text: $phone, keyboard: .phonePad)
                rowDivider
                fieldRow(icon: "heart.fill", color: .pink, placeholder: "Relație (ex: soț, mamă, prieten)", text: $relationship, keyboard: .default)
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
                .autocorrectionDisabled(keyboard != .default)
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

    // MARK: - Remove button

    private var removeButton: some View {
        Button { showRemoveConfirm = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 13))
                Text("Elimină contactul de încredere")
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.red.opacity(0.15), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Saved badge

    private var savedBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text("Contact salvat")
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color(red: 0.12, green: 0.12, blue: 0.15).opacity(0.95), in: Capsule())
        .padding(.horizontal, 24)
    }

    // MARK: - Actions

    private func save() {
        HapticFeedback.success()
        isSaving = true
        savedName = name.trimmingCharacters(in: .whitespaces)
        savedPhone = phone.trimmingCharacters(in: .whitespaces)
        savedRelationship = relationship.trimmingCharacters(in: .whitespaces)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isSaving = false
            withAnimation { saved = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation { saved = false }
            }
        }
    }

    private func removeContact() {
        HapticFeedback.impact(.medium)
        savedName = ""
        savedPhone = ""
        savedRelationship = ""
        name = ""
        phone = ""
        relationship = ""
    }

    private func loadSaved() {
        name = savedName
        phone = savedPhone
        relationship = savedRelationship
    }
}
