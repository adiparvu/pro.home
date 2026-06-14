import SwiftUI

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
                                Label("Tip element", systemImage: "tag").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
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
                                Label("Informații de bază", systemImage: "info.circle").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                fieldRow(label: "Nume *", placeholder: "ex. Centrală Viessmann", text: $name)
                                fieldRow(label: "Descriere", placeholder: "Detalii suplimentare...", text: $description)
                            }
                        }

                        // Condition & health
                        GlassCard(padding: 14) {
                            VStack(spacing: 12) {
                                Label("Stare tehnică", systemImage: "heart").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                HStack {
                                    Text("Scor sănătate")
                                        .font(.subheadline)
                                    Spacer()
                                    Text("\(healthScore)")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(scoreColor)
                                }
                                Slider(value: .init(get: { Double(healthScore) }, set: { healthScore = Int($0) }), in: 0...100, step: 5)
                                    .tint(scoreColor)

                                HStack {
                                    Text("Condiție")
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
                                Label("Detalii tehnice", systemImage: "wrench.and.screwdriver").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                fieldRow(label: "Marcă", placeholder: "ex. Viessmann", text: $brand)
                                fieldRow(label: "Model", placeholder: "ex. Vitodens 200-W", text: $model)
                                fieldRow(label: "Serie", placeholder: "Număr de serie", text: $serialNumber)
                            }
                        }

                        // Financial
                        GlassCard(padding: 14) {
                            VStack(spacing: 12) {
                                Label("Financiar", systemImage: "banknote").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Valoare estimată")
                                            .font(.caption).foregroundStyle(.secondary)
                                        TextField("0", text: $estimatedValue)
                                            .keyboardType(.decimalPad)
                                            .font(.subheadline)
                                            .padding(10)
                                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Monedă")
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
                                Label("Date importante", systemImage: "calendar").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                DateToggleRow(label: "Data achiziției", isShown: $showPurchaseDate, date: $purchaseDatePicker, stringValue: $purchaseDate)
                                DateToggleRow(label: "Garanție până la", isShown: $showWarrantyDate, date: $warrantyDatePicker, stringValue: $warrantyUntil)
                            }
                        }

                        // Layer
                        GlassCard(padding: 14) {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Layer hartă", systemImage: "square.3.layers.3d").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
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
                                Label("Note", systemImage: "note.text").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
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
            .navigationTitle("Element nou")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Anulează") { dismiss() }.foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Adaugă") { save() }
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
    private func fieldRow(label: String, placeholder: String, text: Binding<String>) -> some View {
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
                Text(type.displayName)
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
    let label: String
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

// MARK: - EditPropertyElementView (inline edit)

struct EditPropertyElementView: View {
    @Binding var element: PropertyElement
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        GlassCard(padding: 14) {
                            VStack(spacing: 12) {
                                Label("Editează element", systemImage: "pencil").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Nume").font(.caption).foregroundStyle(.secondary)
                                    TextField("Nume element", text: $element.name)
                                        .font(.subheadline).padding(10)
                                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Stare").font(.caption).foregroundStyle(.secondary)
                                    HStack {
                                        Text("\(element.healthScore)/100").font(.subheadline.weight(.bold)).foregroundStyle(element.healthColor)
                                        Spacer()
                                        Slider(value: .init(get: { Double(element.healthScore) }, set: { element.healthScore = Int($0) }), in: 0...100, step: 5)
                                            .tint(element.healthColor)
                                    }
                                }
                                HStack {
                                    Text("Condiție").font(.subheadline)
                                    Spacer()
                                    Picker("", selection: $element.technicalCondition) {
                                        ForEach(TechnicalCondition.allCases, id: \.self) { c in
                                            Text(c.displayName).tag(c)
                                        }
                                    }.pickerStyle(.menu).tint(element.technicalCondition.color)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Note").font(.caption).foregroundStyle(.secondary)
                                    TextField("Note...", text: .init(get: { element.notes ?? "" }, set: { element.notes = $0.isEmpty ? nil : $0 }))
                                        .font(.subheadline).padding(10)
                                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20).padding(.top, 8)
                }
            }
            .navigationTitle("Editează")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Anulează") { dismiss() }.foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Salvează") { onSave(); dismiss() }.fontWeight(.semibold)
                        .foregroundStyle(Color(red: 0.29, green: 0.56, blue: 0.89))
                }
            }
        }
    }
}

// MARK: - AddElementRecordView

struct AddElementRecordView: View {
    let element: PropertyElement
    let onAdd: (NewElementRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var propertyService: PropertyService

    @State private var title = ""
    @State private var recordType: ElementRecordType = .maintenance
    @State private var content = ""
    @State private var cost = ""
    @State private var currency = "EUR"
    @State private var performedBy = ""
    @State private var recordDate = Date()
    @State private var nextActionDate: Date? = nil
    @State private var hasNextAction = false

    private var canSave: Bool { title.trimmingCharacters(in: .whitespaces).count >= 2 }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        GlassCard(padding: 14) {
                            VStack(spacing: 10) {
                                HStack {
                                    Text("Tip").font(.subheadline)
                                    Spacer()
                                    Picker("", selection: $recordType) {
                                        ForEach(ElementRecordType.allCases, id: \.self) { t in
                                            Label(t.displayName, systemImage: t.icon).tag(t)
                                        }
                                    }.pickerStyle(.menu)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Titlu *").font(.caption).foregroundStyle(.secondary)
                                    TextField("ex. Revizie anuală", text: $title)
                                        .font(.subheadline).padding(10)
                                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Detalii").font(.caption).foregroundStyle(.secondary)
                                    TextField("Descriere lucrare...", text: $content)
                                        .font(.subheadline).padding(10)
                                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Efectuat de").font(.caption).foregroundStyle(.secondary)
                                    TextField("Firmă / persoană", text: $performedBy)
                                        .font(.subheadline).padding(10)
                                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                }
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Cost").font(.caption).foregroundStyle(.secondary)
                                        TextField("0", text: $cost).keyboardType(.decimalPad)
                                            .font(.subheadline).padding(10)
                                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Monedă").font(.caption).foregroundStyle(.secondary)
                                        Picker("", selection: $currency) {
                                            ForEach(["EUR", "RON", "USD"], id: \.self) { Text($0).tag($0) }
                                        }.pickerStyle(.menu).padding(6)
                                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                    }.frame(width: 90)
                                }
                                HStack {
                                    Text("Data").font(.subheadline)
                                    Spacer()
                                    DatePicker("", selection: $recordDate, displayedComponents: .date)
                                        .datePickerStyle(.compact).labelsHidden()
                                }
                            }
                        }
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20).padding(.top, 8)
                }
            }
            .navigationTitle("Înregistrare nouă")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Anulează") { dismiss() }.foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Adaugă") { save() }.fontWeight(.semibold)
                        .foregroundStyle(canSave ? Color(red: 0.29, green: 0.56, blue: 0.89) : Color.secondary)
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        guard canSave, let pid = propertyService.primary?.id else { return }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        let payload = NewElementRecord(
            elementId: element.id,
            propertyId: pid,
            recordType: recordType.rawValue,
            title: title.trimmingCharacters(in: .whitespaces),
            content: content.isEmpty ? nil : content,
            cost: Double(cost.replacingOccurrences(of: ",", with: ".")),
            currency: currency,
            recordDate: df.string(from: recordDate),
            performedBy: performedBy.isEmpty ? nil : performedBy,
            nextActionDate: nil
        )
        onAdd(payload)
        dismiss()
    }
}
