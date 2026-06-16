import SwiftUI

// MARK: - AddApplianceSheet

struct AddApplianceSheet: View {
    @EnvironmentObject private var applianceService: ApplianceService
    @EnvironmentObject private var propertyService: PropertyService
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var brand = ""
    @State private var category: ApplianceCategory = .other
    @State private var modelNumber = ""
    @State private var serialNumber = ""
    @State private var location = ""
    @State private var hasPurchaseDate = false
    @State private var purchaseDate = Date()
    @State private var hasWarrantyDate = false
    @State private var warrantyUntil = Date()
    @State private var purchasePriceText = ""
    @State private var notes = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        formSection("Basic Info") {
                            fieldRow("tag.fill", "Name (required)", $name)
                            divider
                            fieldRow("building.2.fill", "Brand", $brand)
                            divider
                            categoryPicker
                            divider
                            fieldRow("number.circle.fill", "Model Number", $modelNumber)
                            divider
                            fieldRow("barcode", "Serial Number", $serialNumber)
                            divider
                            fieldRow("mappin.circle.fill", "Location (e.g. Kitchen)", $location)
                        }

                        formSection("Purchase & Warranty") {
                            Toggle(isOn: $hasPurchaseDate) {
                                HStack(spacing: 10) {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 28)
                                    Text("Purchase Date")
                                        .font(.system(size: 15))
                                        .foregroundStyle(.primary)
                                }
                            }
                            .tint(.accentColor)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                            if hasPurchaseDate {
                                divider
                                DatePicker("", selection: $purchaseDate, displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                                    .tint(.accentColor)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                            }

                            divider

                            Toggle(isOn: $hasWarrantyDate) {
                                HStack(spacing: 10) {
                                    Image(systemName: "shield.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 28)
                                    Text("Warranty Until")
                                        .font(.system(size: 15))
                                        .foregroundStyle(.primary)
                                }
                            }
                            .tint(.accentColor)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)

                            if hasWarrantyDate {
                                divider
                                DatePicker("", selection: $warrantyUntil, displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                                    .tint(.accentColor)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                            }

                            divider
                            fieldRow("banknote.fill", "Purchase Price", $purchasePriceText, keyboard: .decimalPad)
                        }

                        formSection("Notes") {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "note.text")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 28)
                                    .padding(.top, 2)
                                TextField("Additional notes…", text: $notes, axis: .vertical)
                                    .font(.system(size: 15))
                                    .foregroundStyle(.primary)
                                    .tint(.accentColor)
                                    .lineLimit(3...6)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Add Appliance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.primary.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().tint(.accentColor)
                    } else {
                        Button("Save") { Task { await save() } }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func formSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
                .padding(.bottom, 6)
            VStack(spacing: 0) {
                content()
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        }
    }

    private func fieldRow(_ icon: String, _ placeholder: String, _ binding: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            TextField(placeholder, text: binding)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .keyboardType(keyboard)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var categoryPicker: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            Picker("Category", selection: $category) {
                ForEach(ApplianceCategory.allCases, id: \.self) { cat in
                    Text(cat.displayName).tag(cat)
                }
            }
            .tint(.accentColor)
            .font(.system(size: 15))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, 52)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        guard let propertyId = propertyService.primary?.id,
              let ownerId = supabase.auth.currentSession?.user.id else { return }
        let price = Double(purchasePriceText) ?? 0
        let iso = ISO8601DateFormatter()
        let now = iso.string(from: Date())
        let payload = NewAppliancePayload(
            propertyId: propertyId,
            ownerId: ownerId,
            name: name.trimmingCharacters(in: .whitespaces),
            brand: brand.isEmpty ? nil : brand.trimmingCharacters(in: .whitespaces),
            modelNumber: modelNumber.isEmpty ? nil : modelNumber,
            serialNumber: serialNumber.isEmpty ? nil : serialNumber,
            location: location.isEmpty ? nil : location,
            category: category.rawValue,
            purchaseDate: hasPurchaseDate ? iso.string(from: purchaseDate) : nil,
            warrantyUntil: hasWarrantyDate ? iso.string(from: warrantyUntil) : nil,
            purchasePrice: price > 0 ? price : nil,
            notes: notes.isEmpty ? nil : notes,
            photoUrl: nil,
            createdAt: now,
            updatedAt: now
        )
        await applianceService.add(payload)
        HapticFeedback.success()
        dismiss()
    }
}

// MARK: - ApplianceDetailSheet

struct ApplianceDetailSheet: View {
    let appliance: Appliance
    @EnvironmentObject private var applianceService: ApplianceService
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteConfirm = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func formatDate(_ isoString: String) -> String {
        if let date = isoParser.date(from: isoString) {
            return dateFormatter.string(from: date)
        }
        let short = ISO8601DateFormatter()
        if let date = short.date(from: isoString) {
            return dateFormatter.string(from: date)
        }
        return isoString
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        headerCard
                        detailsSection
                        warrantySection
                        if let notes = appliance.notes, !notes.isEmpty {
                            notesSection(notes)
                        }
                        deleteButton
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .navigationTitle(appliance.name)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(false)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accentColor)
                }
            }
            .confirmationDialog("Delete \"\(appliance.name)\"?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task {
                        await applianceService.delete(appliance)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }

    private var headerCard: some View {
        GlassCard {
            HStack(spacing: 16) {
                ColoredIconBadge(icon: appliance.categoryIcon, color: appliance.categoryColor, size: 56)
                VStack(alignment: .leading, spacing: 5) {
                    Text(appliance.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(appliance.category.displayName)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.primary.opacity(0.45))
                    Text(appliance.warrantyStatus)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(appliance.warrantyColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(appliance.warrantyColor.opacity(0.13), in: Capsule())
                }
                Spacer()
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Details")
            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    if let brand = appliance.brand, !brand.isEmpty {
                        infoRow(icon: "building.2.fill", label: "Brand", value: brand)
                        rowDivider
                    }
                    if let model = appliance.modelNumber, !model.isEmpty {
                        infoRow(icon: "number.circle.fill", label: "Model", value: model)
                        rowDivider
                    }
                    if let serial = appliance.serialNumber, !serial.isEmpty {
                        infoRow(icon: "barcode", label: "Serial", value: serial)
                        rowDivider
                    }
                    if let location = appliance.location, !location.isEmpty {
                        infoRow(icon: "mappin.circle.fill", label: "Location", value: location)
                    }
                }
            }
        }
    }

    private var warrantySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Purchase & Warranty")
            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    if let date = appliance.purchaseDate {
                        infoRow(icon: "calendar", label: "Purchased", value: Self.formatDate(date))
                        rowDivider
                    }
                    if let warranty = appliance.warrantyUntil {
                        infoRow(icon: "shield.fill", label: "Warranty Until", value: Self.formatDate(warranty),
                                valueColor: appliance.warrantyColor)
                        rowDivider
                    }
                    if let price = appliance.purchasePrice, price > 0 {
                        infoRow(icon: "banknote.fill", label: "Purchase Price", value: String(format: "%.2f", price))
                    }
                }
            }
        }
    }

    private func notesSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Notes")
            GlassCard {
                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var deleteButton: some View {
        Button {
            showDeleteConfirm = true
            HapticFeedback.warning()
        } label: {
            Label("Delete Appliance", systemImage: "trash")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 6)
    }

    private func infoRow(icon: String, label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(valueColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, 52)
    }
}
