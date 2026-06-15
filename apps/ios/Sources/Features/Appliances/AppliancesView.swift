import SwiftUI

// MARK: - AppliancesView

struct AppliancesView: View {
    @EnvironmentObject private var applianceService: ApplianceService
    @EnvironmentObject private var propertyService: PropertyService

    @State private var showAdd = false
    @State private var selectedAppliance: Appliance? = nil
    @State private var search = ""
    @State private var selectedCategory: ApplianceCategory? = nil

    private var filtered: [Appliance] {
        var list = selectedCategory == nil
            ? applianceService.appliances
            : applianceService.byCategory[selectedCategory!] ?? []
        if !search.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(search) ||
                ($0.brand?.localizedCaseInsensitiveContains(search) ?? false) ||
                ($0.location?.localizedCaseInsensitiveContains(search) ?? false)
            }
        }
        return list
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                if applianceService.isLoading && applianceService.appliances.isEmpty {
                    loadingState
                } else if applianceService.appliances.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
        }
        .navigationTitle("Appliances")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                    HapticFeedback.impact(.light)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddApplianceSheet()
                .environmentObject(applianceService)
                .environmentObject(propertyService)
        }
        .sheet(item: $selectedAppliance) { appliance in
            ApplianceDetailSheet(appliance: appliance)
                .environmentObject(applianceService)
        }
        .task {
            if let id = propertyService.primary?.id {
                await applianceService.load(propertyId: id)
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                searchBar
                if !applianceService.appliancesExpiringWarranty.isEmpty {
                    warrantyBanner
                }
                categoryChips
                appliances
                Spacer(minLength: 110)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .refreshable {
            if let id = propertyService.primary?.id {
                await applianceService.load(propertyId: id)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.4))
            TextField("Search appliances…", text: $search)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var warrantyBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.orange)
            Text("\(applianceService.appliancesExpiringWarranty.count) warranty expiring soon")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.orange)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.8)
        )
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(label: "All", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                    HapticFeedback.impact(.light)
                }
                ForEach(ApplianceCategory.allCases, id: \.self) { cat in
                    chip(label: cat.displayName, isSelected: selectedCategory == cat) {
                        selectedCategory = selectedCategory == cat ? nil : cat
                        HapticFeedback.impact(.light)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func chip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : Color.primary.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private var appliances: some View {
        LazyVStack(spacing: 10) {
            ForEach(filtered) { appliance in
                ApplianceRow(appliance: appliance)
                    .onTapGesture {
                        selectedAppliance = appliance
                        HapticFeedback.impact(.light)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            HapticFeedback.warning()
                            Task { await applianceService.delete(appliance) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "cube.box.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.primary.opacity(0.15))
            Text("No appliances yet")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.6))
            Text("Track warranties, model numbers, and maintenance for all your home appliances.")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.35))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showAdd = true
            } label: {
                Label("Add your first appliance", systemImage: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView().tint(.primary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - ApplianceRow

private struct ApplianceRow: View {
    let appliance: Appliance

    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                ColoredIconBadge(icon: appliance.categoryIcon, color: appliance.categoryColor, size: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(appliance.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        if let brand = appliance.brand, !brand.isEmpty {
                            Text(brand)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.primary.opacity(0.45))
                        }
                        if let model = appliance.modelNumber, !model.isEmpty {
                            if appliance.brand?.isEmpty == false {
                                Text("·").foregroundStyle(Color.primary.opacity(0.2))
                            }
                            Text(model)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.primary.opacity(0.35))
                        }
                    }

                    HStack(spacing: 6) {
                        Text(appliance.warrantyStatus)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(appliance.warrantyColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(appliance.warrantyColor.opacity(0.12), in: Capsule())

                        if let location = appliance.location, !location.isEmpty {
                            Text(location)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.primary.opacity(0.4))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.primary.opacity(0.06), in: Capsule())
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.28))
            }
        }
    }
}

// MARK: - AddApplianceSheet

private struct AddApplianceSheet: View {
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

private struct ApplianceDetailSheet: View {
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
