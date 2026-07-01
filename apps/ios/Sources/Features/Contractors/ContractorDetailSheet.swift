import SwiftUI

struct ContractorDetailSheet: View {
    let contractor: ContractorModel
    @ObservedObject var service: ContractorService
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss

    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var localRating: Int

    init(contractor: ContractorModel, service: ContractorService) {
        self.contractor = contractor
        self.service = service
        _localRating = State(initialValue: contractor.rating ?? 0)
    }

    var currentContractor: ContractorModel {
        service.contractors.first(where: { $0.id == contractor.id }) ?? contractor
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        heroHeader
                        contactSection
                        if currentContractor.notes?.isEmpty == false {
                            notesSection
                        }
                        actionsSection
                        Spacer(minLength: 60)
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.sm)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.primary.opacity(0.6))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showEdit = true } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("Menu")
                }
            }
            .confirmationDialog("Delete \(contractor.name)?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete Contractor", role: .destructive) {
                    Task { await service.delete(contractor); dismiss() }
                }
            }
            .sheet(isPresented: $showEdit) {
                EditContractorSheet(contractor: currentContractor, service: service)
            }
        }
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.teal.opacity(0.18))
                    .frame(width: 72, height: 72)
                Image(systemName: contractor.specialtyIcon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.teal)
            }

            VStack(spacing: 4) {
                Text(currentContractor.name)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)

                Text(LocalizedStringKey(currentContractor.specialty.capitalized))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            ratingStars
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppSpacing.sm)
    }

    private var ratingStars: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= localRating ? "star.fill" : "star")
                    .font(.system(size: 22))
                    .foregroundStyle(star <= localRating ? Color.yellow : Color.primary.opacity(0.25))
                    .onTapGesture {
                        HapticFeedback.selection()
                        localRating = star
                        var updated = contractor
                        updated.rating = star
                        Task { await service.update(updated) }
                    }
            }
        }
    }

    // MARK: - Contact Section

    private var contactSection: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                if let phone = currentContractor.phone, !phone.isEmpty {
                    contactRow(
                        icon: "phone.fill",
                        label: "Phone",
                        value: phone,
                        color: .green
                    ) {
                        if let url = URL(string: "tel://\(phone.filter { $0.isNumber })") {
                            UIApplication.shared.open(url)
                        }
                    }
                    rowDivider
                }

                if let email = currentContractor.email, !email.isEmpty {
                    contactRow(
                        icon: "envelope.fill",
                        label: "Email",
                        value: email,
                        color: .blue
                    ) {
                        if let url = URL(string: "mailto:\(email)") {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
        }
    }

    private func contactRow(icon: String, label: LocalizedStringKey, value: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: { HapticFeedback.impact(.light); action() }) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(color.opacity(0.15)).frame(width: 40, height: 40)
                    Image(systemName: icon).font(.system(size: 16)).foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(value).font(.system(size: 15)).foregroundStyle(.primary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(AppFont.captionStrong)
                    .foregroundStyle(Color.primary.opacity(0.25))
            }
            .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.base)
        }
        .buttonStyle(.plain)
    }

    private var rowDivider: some View {
        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 70)
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Notes", systemImage: "note.text")
                    .font(AppFont.captionStrong)
                    .foregroundStyle(.secondary)
                Text(currentContractor.notes ?? "")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.primary.opacity(0.75))
            }
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: 10) {
            if let phone = currentContractor.phone, !phone.isEmpty {
                actionButton(
                    icon: "phone.fill",
                    label: "Call",
                    color: .green
                ) {
                    if let url = URL(string: "tel://\(phone.filter { $0.isNumber })") {
                        UIApplication.shared.open(url)
                    }
                }
            }

            actionButton(
                icon: "checklist",
                label: "Add Maintenance Task",
                color: .orange
            ) {
                router.showAddTask = true
                dismiss()
            }

            if let email = currentContractor.email, !email.isEmpty {
                actionButton(
                    icon: "envelope.fill",
                    label: "Send Email",
                    color: .blue
                ) {
                    if let url = URL(string: "mailto:\(email)") {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }

    private func actionButton(icon: String, label: LocalizedStringKey, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: { HapticFeedback.impact(.medium); action() }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(color.opacity(0.15)).frame(width: 40, height: 40)
                    Image(systemName: icon).font(.system(size: 16)).foregroundStyle(color)
                }
                Text(label)
                    .font(AppFont.body)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.base)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Edit Contractor Sheet

private struct EditContractorSheet: View {
    let contractor: ContractorModel
    @ObservedObject var service: ContractorService
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var category: String
    @State private var phone: String
    @State private var email: String
    @State private var notes: String
    @State private var isSaving = false

    init(contractor: ContractorModel, service: ContractorService) {
        self.contractor = contractor
        self.service = service
        _name     = State(initialValue: contractor.name)
        _category = State(initialValue: contractor.category)
        _phone    = State(initialValue: contractor.phone ?? "")
        _email    = State(initialValue: contractor.email ?? "")
        _notes    = State(initialValue: contractor.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Group {
                            fieldRow("person.fill", "Name", $name)
                            divider
                            fieldRow("wrench.fill", "Specialty", $category)
                            divider
                            fieldRow("phone.fill", "Phone", $phone, keyboard: .phonePad)
                            divider
                            fieldRow("envelope.fill", "Email", $email, keyboard: .emailAddress)
                            divider
                            fieldRow("note.text", "Notes", $notes)
                        }
                    }
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
                    .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.sm)
                }
            }
            .navigationTitle("Edit Contractor").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                }
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

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        var updated = contractor
        updated.name = name
        updated.category = category
        updated.phone = phone.isEmpty ? nil : phone
        updated.email = email.isEmpty ? nil : email
        updated.notes = notes.isEmpty ? nil : notes
        await service.update(updated)
        HapticFeedback.success()
        dismiss()
    }
}
