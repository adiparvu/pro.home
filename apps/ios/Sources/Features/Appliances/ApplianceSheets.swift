import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Supabase

// MARK: - ApplianceFormSheet (add + edit)
//
// One form, two modes. Editing seeds every field from the live row and saves
// through ApplianceService.update; clearing an optional column (warranty,
// purchase date, photo…) additionally sends an explicit SQL-NULL patch,
// because the update payload's synthesized Codable omits nils and the old
// value would silently survive — a toggle that doesn't clear is a lie.

struct ApplianceFormSheet: View {
    var editing: Appliance? = nil

    @Environment(ApplianceService.self) private var applianceService
    @Environment(PropertyService.self) private var propertyService
    @Environment(PropertyZoneService.self) private var zoneService
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var brand: String
    @State private var category: ApplianceCategory
    /// The catalog type driving category + name prefill (nil = free-form).
    @State private var selectedType: ApplianceType?
    @State private var modelNumber: String
    @State private var serialNumber: String
    @State private var scanPickerItem: PhotosPickerItem? = nil
    @State private var isScanning = false
    @State private var showScanCamera = false
    @State private var location: String
    @State private var hasPurchaseDate: Bool
    @State private var purchaseDate: Date
    @State private var hasWarrantyDate: Bool
    @State private var warrantyUntil: Date
    @State private var purchasePriceText: String
    @State private var notes: String
    @State private var isSaving = false

    // Photo: the existing URL (edit), a freshly picked image, or a pending
    // removal — resolved at save time.
    @State private var photoPickerItem: PhotosPickerItem? = nil
    @State private var pickedImage: UIImage? = nil
    @State private var existingPhotoUrl: String?

    init(editing: Appliance? = nil) {
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _brand = State(initialValue: editing?.brand ?? "")
        _category = State(initialValue: editing?.category ?? .other)
        _modelNumber = State(initialValue: editing?.modelNumber ?? "")
        _serialNumber = State(initialValue: editing?.serialNumber ?? "")
        _location = State(initialValue: editing?.location ?? "")
        let purchase = editing?.purchaseDateValue
        _hasPurchaseDate = State(initialValue: purchase != nil)
        _purchaseDate = State(initialValue: purchase ?? Date())
        let warranty = editing?.warrantyDateValue
        _hasWarrantyDate = State(initialValue: warranty != nil)
        _warrantyUntil = State(initialValue: warranty ?? Date())
        _purchasePriceText = State(initialValue: (editing?.purchasePrice).map {
            $0.truncatingRemainder(dividingBy: 1) == 0 ? String(Int($0)) : String($0)
        } ?? "")
        _notes = State(initialValue: editing?.notes ?? "")
        _existingPhotoUrl = State(initialValue: editing?.photoUrl)
    }

    private var purchasePrice: Double? {
        Double(purchasePriceText.replacingOccurrences(of: ",", with: "."))
    }

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
                                scanMenu
                            }
                            divider
                            categoryPicker
                            divider
                            fieldRow("number.circle.fill", "Model Number", $modelNumber)
                            divider
                            fieldRow("barcode", "Serial Number", $serialNumber)
                            divider
                            fieldRow("mappin.circle.fill", "Location (e.g. Kitchen)", $location)
                            if !zoneService.zones.isEmpty {
                                zoneSuggestions
                            }
                            divider
                            photoRow
                        }

                        formSection("Purchase & Warranty") {
                            Toggle(isOn: $hasPurchaseDate.animation(.smooth(duration: 0.25))) {
                                HStack(spacing: 10) {
                                    Image(systemName: "calendar")
                                        .font(AppFont.scaled(14))
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 28)
                                    Text("Purchase Date")
                                        .font(AppFont.scaled(15))
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

                            Toggle(isOn: $hasWarrantyDate.animation(.smooth(duration: 0.25))) {
                                HStack(spacing: 10) {
                                    Image(systemName: "shield.fill")
                                        .font(AppFont.scaled(14))
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 28)
                                    Text("Warranty Until")
                                        .font(AppFont.scaled(15))
                                        .foregroundStyle(.primary)
                                }
                            }
                            .tint(.accentColor)
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.vertical, AppSpacing.md)
                            .onChange(of: hasWarrantyDate) { _, on in
                                // Enabling starts from a sensible default:
                                // 2 years (the EU statutory minimum) from the
                                // purchase date — or today when none is set.
                                if on, editing?.warrantyDateValue == nil {
                                    warrantyUntil = warrantyBase(addingYears: 2)
                                }
                            }

                            if hasWarrantyDate {
                                divider
                                DatePicker("", selection: $warrantyUntil, displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                                    .tint(.accentColor)
                                    .padding(.horizontal, AppSpacing.lg)
                                    .padding(.vertical, 10)
                                warrantyQuickPicks
                            }

                            divider
                            priceRow
                        }

                        formSection("Notes") {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "note.text")
                                    .font(AppFont.scaled(14))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 28)
                                    .padding(.top, 2)
                                TextField("Additional notes…", text: $notes, axis: .vertical)
                                    .font(AppFont.scaled(15))
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
            .navigationTitle(editing == nil ? Text("Add Appliance") : Text("appliance_edit_title"))
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
            .task {
                if zoneService.zones.isEmpty,
                   let pid = editing?.propertyId ?? propertyService.primary?.id {
                    await zoneService.load(propertyId: pid)
                }
            }
        }
        .presentationBackground(.thinMaterial)
    }

    // MARK: - Scan (OCR fills brand + model + serial from a label photo)

    private var scanMenu: some View {
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
                Text("Scan").font(AppFont.captionEmphasis)
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

    // MARK: - Location suggestions (real property zones; free text stays)

    private var zoneSuggestions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(zoneService.zones) { zone in
                    let isSelected = location == zone.name
                    Button {
                        location = isSelected ? "" : zone.name
                        HapticFeedback.selection()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: zone.icon)
                                .font(AppFont.scaled(10, weight: .medium))
                            Text(zone.name)
                                .font(AppFont.scaled(12, weight: isSelected ? .semibold : .regular))
                        }
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(AppOpacity.emphasis))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassFilterCapsule(selected: isSelected)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
        }
        .padding(.bottom, AppSpacing.md)
    }

    // MARK: - Photo (real storage; column photo_url)

    private var photoRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo")
                .font(AppFont.scaled(14))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)

            if hasPhoto {
                previewImage
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
            }

            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                (hasPhoto ? Text("appliance_photo_change") : Text("appliance_photo_add"))
                    .font(AppFont.scaled(15))
                    .foregroundStyle(Color.accentColor)
            }
            .onChange(of: photoPickerItem) { _, item in
                guard let item else { return }
                Task {
                    defer { photoPickerItem = nil }
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { return }
                    pickedImage = image
                    HapticFeedback.selection()
                }
            }

            Spacer()

            if hasPhoto {
                Button {
                    pickedImage = nil
                    existingPhotoUrl = nil
                    HapticFeedback.impact(.light)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppFont.scaled(16))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("appliance_photo_remove"))
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, 10)
    }

    private var hasPhoto: Bool { pickedImage != nil || existingPhotoUrl != nil }

    @ViewBuilder private var previewImage: some View {
        if let picked = pickedImage {
            Image(uiImage: picked).resizable().scaledToFill()
        } else if let urlString = existingPhotoUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Rectangle().fill(Color.primary.opacity(AppOpacity.subtleFill))
                }
            }
        }
    }

    // MARK: - Warranty quick-picks (+1/+2/+5 years from purchase date)

    private var warrantyQuickPicks: some View {
        HStack(spacing: 8) {
            quickPick("appliance_warranty_plus1", years: 1)
            quickPick("appliance_warranty_plus2", years: 2)
            quickPick("appliance_warranty_plus5", years: 5)
            Spacer()
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.bottom, AppSpacing.md)
    }

    private func quickPick(_ label: LocalizedStringKey, years: Int) -> some View {
        let target = warrantyBase(addingYears: years)
        let isCurrent = Calendar.current.isDate(warrantyUntil, inSameDayAs: target)
        return Button {
            warrantyUntil = target
            HapticFeedback.selection()
        } label: {
            Text(label)
                .font(AppFont.scaled(12, weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? Color.accentColor : Color.primary.opacity(AppOpacity.emphasis))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassFilterCapsule(selected: isCurrent)
        }
        .buttonStyle(.plain)
    }

    /// Quick-pick anchor: the purchase date when set, otherwise today.
    private func warrantyBase(addingYears years: Int) -> Date {
        let base = hasPurchaseDate ? purchaseDate : Date()
        return Calendar.current.date(byAdding: .year, value: years, to: base) ?? base
    }

    // MARK: - Price (household currency, comma-tolerant)

    private var priceRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "banknote.fill")
                .font(AppFont.scaled(14))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            TextField("Purchase Price", text: $purchasePriceText)
                .font(AppFont.scaled(15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .keyboardType(.decimalPad)
            Text(appSettings.preferredCurrency)
                .font(AppFont.captionEmphasis)
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, 13)
    }

    // MARK: - Shared form pieces

    private func formSection<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(AppFont.label)
                .foregroundStyle(.secondary)
                .padding(.leading, AppSpacing.sm)
                .padding(.bottom, AppSpacing.xs)
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
                .font(AppFont.scaled(14))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            TextField(placeholder, text: binding)
                .font(AppFont.scaled(15))
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
                    .font(AppFont.scaled(14))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                (selectedType.map { Text(verbatim: $0.name) } ?? Text("appliance_type_pick"))
                    .font(AppFont.scaled(15))
                    .foregroundStyle(selectedType == nil ? Color.accentColor : .primary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(AppFont.captionStrong)
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
                .font(AppFont.captionEmphasis)
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
                .font(AppFont.scaled(14))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            Picker("Category", selection: $category) {
                ForEach(ApplianceCategory.allCases, id: \.self) { cat in
                    Text(cat.displayName).tag(cat)
                }
            }
            .tint(.accentColor)
            .font(AppFont.scaled(15))
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

    // MARK: - Save

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        // Fresh photo first: both modes share the upload.
        var photoUrl = existingPhotoUrl
        if let image = pickedImage,
           let pid = editing?.propertyId ?? propertyService.primary?.id,
           let uploaded = try? await ApplianceMediaUploader.upload(image, propertyId: pid) {
            photoUrl = uploaded
        }

        let iso = ISO8601DateFormatter()
        let price = purchasePrice ?? 0
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        if let original = editing {
            var updated = original
            updated.name = trimmedName
            updated.brand = brand.isEmpty ? nil : brand.trimmingCharacters(in: .whitespaces)
            updated.modelNumber = modelNumber.isEmpty ? nil : modelNumber
            updated.serialNumber = serialNumber.isEmpty ? nil : serialNumber
            updated.location = location.isEmpty ? nil : location
            updated.category = category
            updated.purchaseDate = hasPurchaseDate ? iso.string(from: purchaseDate) : nil
            updated.warrantyUntil = hasWarrantyDate ? iso.string(from: warrantyUntil) : nil
            updated.purchasePrice = price > 0 ? price : nil
            updated.notes = notes.isEmpty ? nil : notes
            updated.photoUrl = photoUrl
            await applianceService.update(updated)
            await clearNulledColumns(original: original, updated: updated)
        } else {
            guard let propertyId = propertyService.primary?.id,
                  let ownerId = supabase.auth.currentSession?.user.id else { return }
            let now = iso.string(from: Date())
            let payload = NewAppliancePayload(
                propertyId: propertyId,
                ownerId: ownerId,
                name: trimmedName,
                brand: brand.isEmpty ? nil : brand.trimmingCharacters(in: .whitespaces),
                modelNumber: modelNumber.isEmpty ? nil : modelNumber,
                serialNumber: serialNumber.isEmpty ? nil : serialNumber,
                location: location.isEmpty ? nil : location,
                category: category.rawValue,
                purchaseDate: hasPurchaseDate ? iso.string(from: purchaseDate) : nil,
                warrantyUntil: hasWarrantyDate ? iso.string(from: warrantyUntil) : nil,
                purchasePrice: price > 0 ? price : nil,
                notes: notes.isEmpty ? nil : notes,
                photoUrl: photoUrl,
                createdAt: now,
                updatedAt: now
            )
            await applianceService.add(payload)
        }
        HapticFeedback.success()
        dismiss()
    }

    /// ApplianceUpdate's synthesized Codable OMITS nil fields, so the service
    /// update can set values but never clear them. For every optional the
    /// user actually cleared, send one explicit-NULL patch and re-sync — the
    /// toggles stay honest without touching the read-only Services layer.
    private func clearNulledColumns(original: Appliance, updated: Appliance) async {
        var cleared: [String] = []
        func check(_ old: String?, _ new: String?, _ column: String) {
            if let old, !old.isEmpty, new == nil { cleared.append(column) }
        }
        check(original.brand, updated.brand, "brand")
        check(original.modelNumber, updated.modelNumber, "model_number")
        check(original.serialNumber, updated.serialNumber, "serial_number")
        check(original.location, updated.location, "location")
        check(original.purchaseDate, updated.purchaseDate, "purchase_date")
        check(original.warrantyUntil, updated.warrantyUntil, "warranty_until")
        check(original.notes, updated.notes, "notes")
        check(original.photoUrl, updated.photoUrl, "photo_url")
        if original.purchasePrice != nil, updated.purchasePrice == nil { cleared.append("purchase_price") }
        guard !cleared.isEmpty else { return }

        do {
            try await supabase
                .from("appliances")
                .update(ApplianceNullPatch(columns: cleared, updatedAt: ISODate.string(from: Date())))
                .eq("id", value: original.id.uuidString)
                .execute()
            await applianceService.load(propertyId: original.propertyId)
        } catch {
            // Best-effort: the primary update already saved everything else.
        }
    }
}

/// Encodes explicit SQL NULLs for the given columns — what the synthesized
/// `ApplianceUpdate` cannot express.
private struct ApplianceNullPatch: Encodable {
    let columns: [String]
    let updatedAt: String

    private struct Key: CodingKey {
        var stringValue: String
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { return nil }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        for column in columns { try c.encodeNil(forKey: Key(column)) }
        try c.encode(updatedAt, forKey: Key("updated_at"))
    }
}

// MARK: - Photo upload (same pipeline as tasks/journal: documents bucket)

enum ApplianceMediaUploader {
    static func upload(_ image: UIImage, propertyId: UUID) async throws -> String? {
        guard let ownerId = supabase.auth.currentSession?.user.id,
              let data = image.uploadJPEG(quality: 0.8) else { return nil }
        let path = "\(ownerId.uuidString.lowercased())/appliances/\(propertyId.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        try await supabase.storage
            .from("documents")
            .upload(path, data: data,
                    options: FileOptions(contentType: "image/jpeg", upsert: false))
        return try supabase.storage.from("documents").getPublicURL(path: path).absoluteString
    }
}
