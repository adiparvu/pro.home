import SwiftUI
import PhotosUI
import Supabase
import UniformTypeIdentifiers

struct AddPropertyElementView: View {
    let defaultPosition: CGPoint
    let onAdd: (NewPropertyElement) -> Void

    @Environment(PropertyService.self) private var propertyService
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var elementType: PropertyElementType = .house
    @State private var description = ""
    @State private var healthScore = 100
    @State private var condition: TechnicalCondition = .good
    @State private var brand = ""
    @State private var model = ""
    @State private var serialNumber = ""
    @State private var estimatedValue = ""
    @State private var currency = "EUR"
    @State private var purchaseDate = ""
    @State private var warrantyUntil = ""
    @State private var notes = ""
    @State private var selectedLayer: PropertyLayer = .property
    @State private var showPurchaseDate = false
    @State private var showWarrantyDate = false
    @State private var purchaseDatePicker = Date()
    @State private var warrantyDatePicker = Date()
    @State private var scanPickerItem: PhotosPickerItem? = nil
    @State private var isScanning = false

    // Type picker (full list)
    @State private var showTypePicker = false

    // Photos
    @State private var coverURL: String?
    @State private var galleryURLs: [String] = []
    @State private var isUploadingMedia = false
    @State private var mediaTarget: MediaTarget = .gallery
    @State private var showSourceDialog = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var showFiles = false
    @State private var libraryItem: PhotosPickerItem?

    // Automation (gate / powered elements)
    @State private var isElectric = false
    @State private var automationSystem = ""

    private enum MediaTarget { case cover, gallery }

    private var showsAutomation: Bool {
        elementType == .gate || elementType == .garage
    }

    private var canSave: Bool { name.trimmingCharacters(in: .whitespaces).count >= 2 }

    var body: some View {
        FormScaffold(title: "New element", saveLabel: "Add",
                     canSave: canSave, error: .constant(nil),
                     onSave: { save() }) {
                        // Type picker
                        GlassCard(padding: 14) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Label("Element type", systemImage: "tag").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    Spacer()
                                    Button { showTypePicker = true } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "square.grid.2x2.fill").font(.system(size: 11))
                                            Text("All types").font(.caption.weight(.semibold))
                                        }
                                        .foregroundStyle(Color.accentColor)
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                                    }
                                }
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        // Always include the currently-selected type so it stays visible.
                                        let chips = PropertyElementType.common.contains(elementType)
                                            ? PropertyElementType.common
                                            : [elementType] + PropertyElementType.common
                                        ForEach(chips, id: \.self) { type in
                                            TypeChip(type: type, isSelected: elementType == type) {
                                                selectType(type)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Basic info
                        GlassCard(padding: 14) {
                            VStack(spacing: 12) {
                                Label("Basic information", systemImage: "info.circle").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                fieldRow(label: "Name *", placeholder: "e.g. Viessmann Boiler", text: $name)
                                fieldRow(label: "Description", placeholder: "Additional details...", text: $description)
                            }
                        }

                        // Photos (cover + gallery)
                        photosCard

                        // Automation (gate / powered)
                        if showsAutomation { automationCard }

                        // Condition & health
                        GlassCard(padding: 14) {
                            VStack(spacing: 12) {
                                Label("Technical condition", systemImage: "heart").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                HStack {
                                    Text("Health score")
                                        .font(.subheadline)
                                    Spacer()
                                    Text("\(healthScore)")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(scoreColor)
                                }
                                Slider(value: .init(get: { Double(healthScore) }, set: { healthScore = Int($0) }), in: 0...100, step: 5)
                                    .tint(scoreColor)

                                HStack {
                                    Text("Condition")
                                        .font(.subheadline)
                                    Spacer()
                                    Picker("", selection: $condition) {
                                        ForEach(TechnicalCondition.allCases, id: \.self) { c in
                                            Text(c.displayName).tag(c)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(condition.color)
                                }
                            }
                        }

                        // Technical details
                        GlassCard(padding: 14) {
                            VStack(spacing: 12) {
                                HStack {
                                    Label("Technical details", systemImage: "wrench.and.screwdriver").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    Spacer()
                                    PhotosPicker(selection: $scanPickerItem, matching: .images) {
                                        HStack(spacing: 4) {
                                            if isScanning {
                                                ProgressView().scaleEffect(0.7)
                                            } else {
                                                Image(systemName: "camera.viewfinder")
                                            }
                                            Text("Scan label").font(.caption.weight(.semibold))
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
                                            let lines = await VisionCaptureService.recognizeText(in: uiImage)
                                            let parsed = VisionCaptureService.parseProduct(from: lines)
                                            await MainActor.run {
                                                if !parsed.brand.isEmpty { brand = parsed.brand }
                                                if !parsed.model.isEmpty { model = parsed.model }
                                                if !parsed.serialNumber.isEmpty { serialNumber = parsed.serialNumber }
                                                if !parsed.name.isEmpty && name.isEmpty { name = parsed.name }
                                                HapticFeedback.success()
                                            }
                                        }
                                    }
                                }
                                fieldRow(label: "Brand", placeholder: "e.g. Viessmann", text: $brand)
                                fieldRow(label: "Model", placeholder: "e.g. Vitodens 200-W", text: $model)
                                fieldRow(label: "Serial", placeholder: "Serial number", text: $serialNumber)
                            }
                        }

                        // Financial
                        GlassCard(padding: 14) {
                            VStack(spacing: 12) {
                                Label("Financial", systemImage: "banknote").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Estimated value")
                                            .font(.caption).foregroundStyle(.secondary)
                                        TextField("0", text: $estimatedValue)
                                            .keyboardType(.decimalPad)
                                            .font(.subheadline)
                                            .padding(10)
                                            .background(Color.primary.opacity(AppOpacity.hairline), in: RoundedRectangle(cornerRadius: 10))
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Currency")
                                            .font(.caption).foregroundStyle(.secondary)
                                        Picker("", selection: $currency) {
                                            ForEach(["EUR", "RON", "USD", "GBP", "CHF"], id: \.self) {
                                                Text($0).tag($0)
                                            }
                                        }
                                        .pickerStyle(.menu)
                                        .padding(AppSpacing.xs)
                                        .background(Color.primary.opacity(AppOpacity.hairline), in: RoundedRectangle(cornerRadius: 10))
                                    }
                                    .frame(width: 80)
                                }
                            }
                        }

                        // Dates
                        GlassCard(padding: 14) {
                            VStack(spacing: 12) {
                                Label("Important dates", systemImage: "calendar").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                DateToggleRow(label: "Purchase date", isShown: $showPurchaseDate, date: $purchaseDatePicker, stringValue: $purchaseDate)
                                DateToggleRow(label: "Warranty until", isShown: $showWarrantyDate, date: $warrantyDatePicker, stringValue: $warrantyUntil)
                            }
                        }

                        // Layer
                        GlassCard(padding: 14) {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Map layer", systemImage: "square.3.layers.3d").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(PropertyLayer.allCases, id: \.self) { layer in
                                            Button {
                                                withAnimation(.spring(response: 0.25)) { selectedLayer = layer }
                                            } label: {
                                                Label(layer.displayName, systemImage: layer.icon)
                                                    .font(.caption.weight(selectedLayer == layer ? .semibold : .regular))
                                                    .foregroundStyle(selectedLayer == layer ? Color.white : Color.secondary)
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, AppSpacing.xs)
                                                    .background(
                                                        Capsule().fill(selectedLayer == layer ? Color.brandPrimaryBlue : Color.primary.opacity(AppOpacity.subtleFill))
                                                    )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }

                        // Notes
                        GlassCard(padding: 14) {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Notes", systemImage: "note.text").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                TextEditor(text: $notes)
                                    .frame(minHeight: 72)
                                    .scrollContentBackground(.hidden)
                                    .font(.subheadline)
                                    .padding(AppSpacing.sm)
                                    .background(Color.primary.opacity(AppOpacity.hairline), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }

        }
        .sheet(isPresented: $showTypePicker) {
                ElementTypePickerSheet(selected: elementType) { selectType($0) }
            }
            .confirmationDialog("Add photo", isPresented: $showSourceDialog, titleVisibility: .visible) {
                Button("Take photo") { showCamera = true }
                Button("Photo library") { showLibrary = true }
                Button("Files") { showFiles = true }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showCamera) {
                CameraCapture { img in Task { await handlePicked(img) } }
                    .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showLibrary, selection: $libraryItem, matching: .images)
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        await handlePicked(img)
                    }
                    libraryItem = nil
                }
            }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image, .jpeg, .png, .heic]) { result in
                if case .success(let url) = result {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                        Task { await handlePicked(img) }
                    }
                }
            }
    }

    // MARK: - Photos card

    private var photosCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Photos", systemImage: "photo.on.rectangle.angled")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if isUploadingMedia { ProgressView().scaleEffect(0.7) }
                }

                // Cover
                Text("Cover photo").font(.caption2).foregroundStyle(.tertiary)
                Button {
                    mediaTarget = .cover; showSourceDialog = true
                } label: {
                    ZStack {
                        if let coverURL, let url = URL(string: coverURL) {
                            AsyncImage(url: url) { phase in
                                if case .success(let img) = phase { img.resizable().scaledToFill() }
                                else { Color.primary.opacity(AppOpacity.hairline) }
                            }
                        } else {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                                .overlay(
                                    VStack(spacing: 6) {
                                        Image(systemName: "photo.badge.plus").font(.system(size: 24))
                                        Text("Add cover").font(.caption)
                                    }.foregroundStyle(.secondary)
                                )
                        }
                    }
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                if coverURL != nil {
                    Button(role: .destructive) { coverURL = nil } label: {
                        Label("Remove cover", systemImage: "trash").font(.caption)
                    }
                }

                // Gallery
                Text("More photos").font(.caption2).foregroundStyle(.tertiary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(galleryURLs, id: \.self) { urlStr in
                            if let url = URL(string: urlStr) {
                                AsyncImage(url: url) { phase in
                                    if case .success(let img) = phase { img.resizable().scaledToFill() }
                                    else { Color.primary.opacity(AppOpacity.hairline) }
                                }
                                .frame(width: 78, height: 78)
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                                .contextMenu {
                                    Button { coverURL = urlStr } label: { Label("Set as cover", systemImage: "star") }
                                    Button(role: .destructive) { galleryURLs.removeAll { $0 == urlStr } } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                        }
                        Button {
                            mediaTarget = .gallery; showSourceDialog = true
                        } label: {
                            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                                .frame(width: 78, height: 78)
                                .overlay(Image(systemName: "plus").font(.system(size: 20)).foregroundStyle(Color.accentColor))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Automation card

    private var automationCard: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Automation", systemImage: "bolt.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Toggle(isOn: $isElectric) {
                    Text("Electric / automated").font(.subheadline)
                }
                .tint(Color.brandPrimaryBlue)
                if isElectric {
                    fieldRow(label: "Automation system", placeholder: "e.g. Nice sliding motor, remote + app", text: $automationSystem)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(["Nice", "BFT", "CAME", "Somfy", "FAAC", "Roger", "Hörmann"], id: \.self) { brandName in
                                Button { automationSystem = brandName } label: {
                                    Text(brandName)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(automationSystem == brandName ? Color.white : Color.secondary)
                                        .padding(.horizontal, AppSpacing.md).padding(.vertical, AppSpacing.xs)
                                        .background(
                                            Capsule().fill(automationSystem == brandName ? Color.brandPrimaryBlue : Color.primary.opacity(AppOpacity.subtleFill))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func selectType(_ type: PropertyElementType) {
        withAnimation(.spring(response: 0.25)) {
            elementType = type
            if name.isEmpty { name = type.displayName }
            selectedLayer = type.defaultLayer
            condition = .good
            healthScore = 100
        }
    }

    private func handlePicked(_ image: UIImage) async {
        guard let pid = propertyService.primary?.id,
              let data = image.jpegData(compressionQuality: 0.82) else { return }
        isUploadingMedia = true
        defer { isUploadingMedia = false }
        let uid = supabase.auth.currentSession?.user.id.uuidString ?? "anon"
        let path = "\(uid)/elements/\(pid.uuidString)/\(UUID().uuidString).jpg"
        do {
            try await supabase.storage.from("documents")
                .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: false))
            let url = try supabase.storage.from("documents").getPublicURL(path: path).absoluteString
            await MainActor.run {
                switch mediaTarget {
                case .cover: coverURL = url
                case .gallery: galleryURLs.append(url)
                }
                HapticFeedback.success()
            }
        } catch {
            await MainActor.run { HapticFeedback.warning() }
        }
    }

    // MARK: - Save

    private func save() {
        guard canSave, let pid = propertyService.primary?.id else { return }
        let payload = NewPropertyElement(
            propertyId: pid,
            name: name.trimmingCharacters(in: .whitespaces),
            elementType: elementType.rawValue,
            description: description.isEmpty ? nil : description,
            positionX: defaultPosition.x,
            positionY: defaultPosition.y,
            healthScore: healthScore,
            technicalCondition: condition.rawValue,
            estimatedValue: Double(estimatedValue.replacingOccurrences(of: ",", with: ".")),
            valueCurrency: currency,
            purchaseDate: purchaseDate.isEmpty ? nil : purchaseDate,
            warrantyUntil: warrantyUntil.isEmpty ? nil : warrantyUntil,
            brand: brand.isEmpty ? nil : brand,
            model: model.isEmpty ? nil : model,
            serialNumber: serialNumber.isEmpty ? nil : serialNumber,
            notes: notes.isEmpty ? nil : notes,
            layer: selectedLayer.rawValue,
            photoUrls: galleryURLs.isEmpty ? nil : galleryURLs,
            coverPhotoUrl: coverURL,
            isElectric: showsAutomation ? isElectric : false,
            automationSystem: (showsAutomation && isElectric && !automationSystem.isEmpty) ? automationSystem : nil,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        onAdd(payload)
        dismiss()
    }

    private var scoreColor: Color {
        switch healthScore {
        case 90...100: return Color.brandSuccess
        case 70..<90:  return Color(red: 0.4, green: 0.75, blue: 0.3)
        case 50..<70:  return .orange
        case 25..<50:  return Color.brandWarning
        default:       return .red
        }
    }

    @ViewBuilder
    private func fieldRow(label: LocalizedStringKey, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .font(.subheadline)
                .padding(10)
                .background(Color.primary.opacity(AppOpacity.hairline), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - TypeChip

private struct TypeChip: View {
    let type: PropertyElementType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: type.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? type.accentColor : Color.secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(isSelected ? type.accentColor.opacity(0.15) : Color.primary.opacity(AppOpacity.hairline))
                    )
                Text(LocalizedStringKey(type.displayName))
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 56)
            }
            .padding(AppSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .fill(isSelected ? type.accentColor.opacity(0.08) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.md)
                            .strokeBorder(isSelected ? type.accentColor.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - DateToggleRow

private struct DateToggleRow: View {
    let label: LocalizedStringKey
    @Binding var isShown: Bool
    @Binding var date: Date
    @Binding var stringValue: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Toggle("", isOn: $isShown)
                    .labelsHidden()
                    .onChange(of: isShown) { _, shown in
                        if shown {
                            stringValue = AppDate.dayString(from: date)
                        } else {
                            stringValue = ""
                        }
                    }
            }
            if isShown {
                DatePicker("", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .onChange(of: date) { _, d in
                        stringValue = AppDate.dayString(from: d)
                    }
            }
        }
    }
}
