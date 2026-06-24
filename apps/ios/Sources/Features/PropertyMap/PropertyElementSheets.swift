import SwiftUI

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
                                Label("Edit element", systemImage: "pencil").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Name").font(.caption).foregroundStyle(.secondary)
                                    TextField("Element name", text: $element.name)
                                        .font(.subheadline).padding(10)
                                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Status").font(.caption).foregroundStyle(.secondary)
                                    HStack {
                                        Text("\(element.healthScore)/100").font(.subheadline.weight(.bold)).foregroundStyle(element.healthColor)
                                        Spacer()
                                        Slider(value: .init(get: { Double(element.healthScore) }, set: { element.healthScore = Int($0) }), in: 0...100, step: 5)
                                            .tint(element.healthColor)
                                    }
                                }
                                HStack {
                                    Text("Condition").font(.subheadline)
                                    Spacer()
                                    Picker("", selection: $element.technicalCondition) {
                                        ForEach(TechnicalCondition.allCases, id: \.self) { c in
                                            Text(c.displayName).tag(c)
                                        }
                                    }.pickerStyle(.menu).tint(element.technicalCondition.color)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Notes").font(.caption).foregroundStyle(.secondary)
                                    TextField("Notes...", text: .init(get: { element.notes ?? "" }, set: { element.notes = $0.isEmpty ? nil : $0 }))
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
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { onSave(); dismiss() }.fontWeight(.semibold)
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
                                    Text("Type").font(.subheadline)
                                    Spacer()
                                    Picker("", selection: $recordType) {
                                        ForEach(ElementRecordType.allCases, id: \.self) { t in
                                            Label(LocalizedStringKey(t.displayName), systemImage: t.icon).tag(t)
                                        }
                                    }.pickerStyle(.menu)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Title *").font(.caption).foregroundStyle(.secondary)
                                    TextField("e.g. Annual inspection", text: $title)
                                        .font(.subheadline).padding(10)
                                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Details").font(.caption).foregroundStyle(.secondary)
                                    TextField("Work description...", text: $content)
                                        .font(.subheadline).padding(10)
                                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Performed by").font(.caption).foregroundStyle(.secondary)
                                    TextField("Company / person", text: $performedBy)
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
                                        Text("Currency").font(.caption).foregroundStyle(.secondary)
                                        Picker("", selection: $currency) {
                                            ForEach(["EUR", "RON", "USD"], id: \.self) { Text($0).tag($0) }
                                        }.pickerStyle(.menu).padding(6)
                                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                    }.frame(width: 90)
                                }
                                HStack {
                                    Text("Date").font(.subheadline)
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
            .navigationTitle("New record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") { save() }.fontWeight(.semibold)
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
