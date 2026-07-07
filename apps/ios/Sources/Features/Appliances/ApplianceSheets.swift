import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - AddApplianceSheet

struct AddApplianceSheet: View {
    @Environment(ApplianceService.self) private var applianceService
    @Environment(PropertyService.self) private var propertyService
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var brand = ""
    @State private var category: ApplianceCategory = .other
    /// The catalog type driving category + name prefill (nil = free-form).
    @State private var selectedType: ApplianceType?
    @State private var modelNumber = ""
    @State private var serialNumber = ""
    @State private var scanPickerItem: PhotosPickerItem? = nil
    @State private var isScanning = false
    @State private var showScanCamera = false
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
                Color.clear
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        formSection("Basic Info") {
                            typeRow
                            divider
                            fieldRow("tag.fill", "Name (required)", $name)
                            divider
                            HStack {
                                fieldRow("building.2.fill", "Brand", $brand)
                                brandMenu
                                Spacer()
                                Menu {
                                    Button {
                                        showScanCamera = true
                                    } label: {
                                        Label("Camera", systemImage: "camera.fill")
                                    }
                                    PhotosPicker(selection: $scanPickerItem, matching: .images) {
                                        Label("Photo Library", systemImage: "photo.on.rectangle")
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        if isScanning { ProgressView().scaleEffect(0.7) }
                                        else { Image(systemName: "camera.viewfinder") }
                                        Text("Scan").font(.caption.weight(.semibold))
                                    }
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .glassCapsule()
                                }
                                .onChange(of: scanPickerItem) { _, item in
                                    guard let item else { return }
                                    isScanning = true
                                    Task {
                                        defer { isScanning = false; scanPickerItem = nil }
                                        guard let data = try? await item.loadTransferable(type: Data.self),
                                              let uiImage = UIImage(data: data) else { return }
                                        await runOCR(on: uiImage)
                                    }
                                }
                            }
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
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.vertical, AppSpacing.md)

                            if hasPurchaseDate {
                                divider
                                DatePicker("", selection: $purchaseDate, displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                                    .tint(.accentColor)
                                    .padding(.horizontal, AppSpacing.lg)
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
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.vertical, AppSpacing.md)

                            if hasWarrantyDate {
                                divider
                                DatePicker("", selection: $warrantyUntil, displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                                    .tint(.accentColor)
                                    .padding(.horizontal, AppSpacing.lg)
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
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.vertical, 13)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.sm)
                }
            }
            .navigationTitle("Add Appliance")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $showScanCamera) {
                CameraCapture { image in
                    isScanning = true
                    Task {
                        defer { isScanning = false }
                        await runOCR(on: image)
                    }
                }
                .ignoresSafeArea()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().tint(.accentColor)
                    } else {
                        Button("Save") { Task { await save() } }
                            .font(AppFont.subheadline)
                            .foregroundStyle(Color.accentColor)
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .presentationBackground(.thinMaterial)
    }

    private func formSection<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(AppFont.label)
                .foregroundStyle(.secondary)
                .padding(.leading, AppSpacing.sm)
                .padding(.bottom, AppSpacing.xs)
                .textCase(.uppercase)
            VStack(spacing: 0) {
                content()
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous).strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
        }
    }

    private func fieldRow(_ icon: String, _ placeholder: LocalizedStringKey, _ binding: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
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
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, 13)
    }

    // One tap picks what the thing IS — the category sets itself and the
    // name pre-fills; the brand menu then completes it ("Frigider Bosch").
    private var typeRow: some View {
        Menu {
            ForEach(ApplianceCatalog.byCategory, id: \.category) { group in
                Section(group.category.displayName) {
                    ForEach(group.types) { type in
                        Button {
                            apply(type: type)
                        } label: {
                            Label(type.name, systemImage: type.icon)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selectedType?.icon ?? "square.grid.2x2.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                (selectedType.map { Text(verbatim: $0.name) } ?? Text("appliance_type_pick"))
                    .font(.system(size: 15))
                    .foregroundStyle(selectedType == nil ? Color.accentColor : .primary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.28))
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
    }

    private var brandMenu: some View {
        Menu {
            ForEach(selectedType?.brands ?? ApplianceCatalog.allBrands, id: \.self) { b in
                Button(b) { apply(brand: b) }
            }
        } label: {
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("appliance_brand_pick"))
    }

    /// Prefill that never fights the user: it only rewrites the name while
    /// the name is still one of its own suggestions (or empty).
    private func apply(type: ApplianceType) {
        let autoNames = [selectedType?.name, selectedType.map { "\($0.name) \(brand)" }]
        selectedType = type
        category = type.category
        if name.trimmingCharacters(in: .whitespaces).isEmpty || autoNames.contains(name) {
            name = brand.isEmpty ? type.name : "\(type.name) \(brand)"
        }
        HapticFeedback.selection()
    }

    private func apply(brand newBrand: String) {
        let autoNames = [selectedType?.name, selectedType.map { "\($0.name) \(brand)" }]
        brand = newBrand
        if let type = selectedType,
           name.trimmingCharacters(in: .whitespaces).isEmpty || autoNames.contains(name) {
            name = "\(type.name) \(newBrand)"
        }
        HapticFeedback.selection()
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
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, 10)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, 52)
    }

    private func runOCR(on image: UIImage) async {
        let lines = await VisionCaptureService.recognizeText(in: image)
        let parsed = VisionCaptureService.parseProduct(from: lines)
        if !parsed.brand.isEmpty { brand = parsed.brand }
        if !parsed.model.isEmpty { modelNumber = parsed.model }
        if !parsed.serialNumber.isEmpty { serialNumber = parsed.serialNumber }
        if !parsed.name.isEmpty && name.isEmpty { name = parsed.name }
        HapticFeedback.success()
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

