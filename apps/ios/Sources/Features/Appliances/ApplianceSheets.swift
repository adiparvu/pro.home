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
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        formSection("Basic Info") {
                            fieldRow("tag.fill", "Name (required)", $name)
                            divider
                            HStack {
                                fieldRow("building.2.fill", "Brand", $brand)
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
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
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
        .padding(.horizontal, AppSpacing.lg)
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

