import SwiftUI
import PhotosUI

struct AddPropertyElementView: View {
    let defaultPosition: CGPoint
    let onAdd: (NewPropertyElement) -> Void

    @EnvironmentObject private var propertyService: PropertyService
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

    private var canSave: Bool { name.trimmingCharacters(in: .whitespaces).count >= 2 }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Type picker
                        GlassCard(padding: 14) {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Element type", systemImage: "tag").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(PropertyElementType.allCases, id: \.self) { type in
                                            TypeChip(type: type, isSelected: elementType == type) {
                                                withAnimation(.spring(response: 0.25)) {
                                                    elementType = type
                                                    if name.isEmpty { name = type.displayName }
                                                    selectedLayer = type.defaultLayer
                                                    condition = .good
                                                    healthScore = 100
                                                }
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
                                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
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
                                        .padding(6)
                                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
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
                                                    .padding(.vertical, 6)
                                                    .background(
                                                        Capsule().fill(selectedLayer == layer ? Color(red: 0.29, green: 0.56, blue: 0.89) : Color.primary.opacity(0.07))
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
                                    .padding(8)
                                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("New element")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") { save() }
                        .fontWeight(.semibold)
                        .foregroundStyle(canSave ? Color(red: 0.29, green: 0.56, blue: 0.89) : Color.secondary)
                        .disabled(!canSave)
                }
            }
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
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        onAdd(payload)
        dismiss()
    }

    private var scoreColor: Color {
        switch healthScore {
        case 90...100: return Color(red: 0.2, green: 0.8, blue: 0.4)
        case 70..<90:  return Color(red: 0.4, green: 0.75, blue: 0.3)
        case 50..<70:  return .orange
        case 25..<50:  return Color(red: 1.0, green: 0.45, blue: 0.1)
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
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
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
                        Circle().fill(isSelected ? type.accentColor.opacity(0.15) : Color.primary.opacity(0.06))
                    )
                Text(LocalizedStringKey(type.displayName))
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 56)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? type.accentColor.opacity(0.08) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
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
                            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                            stringValue = f.string(from: date)
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
                        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                        stringValue = f.string(from: d)
                    }
            }
        }
    }
}
