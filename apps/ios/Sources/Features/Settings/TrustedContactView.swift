import SwiftUI

struct TrustedContactView: View {
    @Environment(AuthService.self) private var auth
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
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Trusted Contact")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Group {
                    if isSaving {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button("Save") { save() }
                            .font(AppFont.subheadline)
                            .foregroundStyle(isValid ? .blue : Color.primary.opacity(0.3))
                            .disabled(!isValid)
                    }
                }
            }
        }
        .confirmationDialog("Remove trusted contact?", isPresented: $showRemoveConfirm, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { removeContact() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Information about \(savedName) will be deleted.")
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
                    .fill(LinearGradient(colors: [Color.brandSkyBlue, Color(red: 0.55, green: 0.25, blue: 1.0)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 64, height: 64)
                Image(systemName: "person.badge.shield.checkmark.fill")
                    .font(AppFont.scaled(28, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text("Your emergency contact person")
                .font(AppFont.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Text("This person can be notified in emergency situations related to your home. Information is stored locally on the device.")
                .font(AppFont.scaled(13))
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, AppSpacing.xl)
        .padding(.horizontal, AppSpacing.lg)
        .frame(maxWidth: .infinity)
        .liquidGlass(cornerRadius: AppRadius.xl)
    }

    // MARK: - Form

    private var formSection: some View {
        SettingsGroup(title: "Contact details") {
            VStack(spacing: 0) {
                fieldRow(icon: "person.fill", color: .blue, placeholder: "Full name", text: $name, keyboard: .default)
                rowDivider
                fieldRow(icon: "phone.fill", color: Color.brandSuccess, placeholder: "Phone number", text: $phone, keyboard: .phonePad)
                rowDivider
                fieldRow(icon: "heart.fill", color: .pink, placeholder: "Relationship (e.g. spouse, mother, friend)", text: $relationship, keyboard: .default)
            }
        }
    }

    // `placeholder` is a LocalizedStringKey, not String — a String parameter
    // reaches TextField's verbatim initializer and Romanian never applies.
    private func fieldRow(icon: String, color: Color, placeholder: LocalizedStringKey, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color)
            TextField(placeholder, text: text)
                .font(AppFont.scaled(15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .keyboardType(keyboard)
                .autocorrectionDisabled(keyboard != .default)
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, 13)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(AppOpacity.hairline))
            .frame(height: 0.4)
            .padding(.leading, 54)
    }

    // MARK: - Remove button

    private var removeButton: some View {
        Button { showRemoveConfirm = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash.fill")
                    .font(AppFont.scaled(13))
                Text("Remove trusted contact")
                    .font(AppFont.footnote)
            }
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.base)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous).strokeBorder(Color.red.opacity(0.15), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Saved badge

    private var savedBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text("Contact saved")
                .font(AppFont.scaled(13, weight: .medium))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
        .background(Color(red: 0.12, green: 0.12, blue: 0.15).opacity(0.95), in: Capsule())
        .padding(.horizontal, AppSpacing.xxl)
    }

    // MARK: - Actions

    private func save() {
        HapticFeedback.success()
        isSaving = true
        savedName = name.trimmingCharacters(in: .whitespaces)
        savedPhone = phone.trimmingCharacters(in: .whitespaces)
        savedRelationship = relationship.trimmingCharacters(in: .whitespaces)
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            isSaving = false
            withAnimation(AppMotion.state) { saved = true }
            try? await Task.sleep(for: .milliseconds(2500))
            withAnimation(AppMotion.state) { saved = false }
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
