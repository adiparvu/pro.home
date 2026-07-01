import SwiftUI

// MARK: - Add Receipt (manual entry)

struct AddReceiptSheet: View {
    @Environment(ReceiptService.self) private var receiptService
    @EnvironmentObject private var propertyService: PropertyService
    @Environment(\.dismiss) private var dismiss

    @State private var storeName = ""
    @State private var date = Date()
    @State private var total = ""
    @State private var category = "food"
    @State private var notes = ""
    @State private var items: [EditableReceiptItem] = []
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        storeField
                        dateField
                        categoryField
                        itemsSection
                        totalField
                        notesField
                        if let error {
                            Text(LocalizedStringKey(error)).font(.caption).foregroundStyle(.red).padding(.horizontal)
                        }
                        saveButton
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.lg)
                }
            }
            .navigationTitle(String(localized: "add_receipt_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
        }
    }

    // MARK: - Fields

    private var storeField: some View {
        formField("STORE") {
            TextField(String(localized: "add_receipt_store_placeholder"), text: $storeName)
                .font(.system(size: 16))
                .padding(AppSpacing.base)
                .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        }
    }

    private var dateField: some View {
        formField("DATE") {
            DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
                .padding(.vertical, AppSpacing.xxs)
        }
    }

    private var categoryField: some View {
        formField("CATEGORY") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ReceiptCategory.all, id: \.id) { cat in
                        Button { category = cat.id; HapticFeedback.selection() } label: {
                            HStack(spacing: 5) {
                                Image(systemName: ReceiptCategory.icon(for: cat.id)).font(.system(size: 11))
                                Text(LocalizedStringKey(cat.label)).font(.system(size: 13))
                            }
                            .foregroundStyle(category == cat.id ? .white : Color.primary.opacity(AppOpacity.emphasis))
                            .padding(.horizontal, AppSpacing.md).padding(.vertical, 7)
                            .background(category == cat.id
                                ? ReceiptCategory.color(for: cat.id)
                                : Color.primary.opacity(AppOpacity.subtleFill), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ITEMS")
                    .font(AppFont.label).foregroundStyle(.secondary)
                Spacer()
                Button {
                    items.append(EditableReceiptItem())
                    HapticFeedback.selection()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16)).foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add item")
            }

            if !items.isEmpty {
                GlassCard(padding: 12) {
                    VStack(spacing: 10) {
                        ForEach($items) { $item in
                            HStack(spacing: 8) {
                                TextField(String(localized: "add_receipt_item_name"), text: $item.name)
                                    .font(.system(size: 13))
                                    .frame(maxWidth: .infinity)
                                TextField("0.00", text: $item.priceText)
                                    .font(AppFont.captionEmphasis)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 70)
                                    .foregroundStyle(Color.accentColor)
                                Button {
                                    items.removeAll { $0.id == item.id }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 16)).foregroundStyle(.red.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, AppSpacing.xxs)
                        }
                    }
                }

                // Auto-compute total from items
                let computed = items.compactMap { Double($0.priceText) }.reduce(0, +)
                if computed > 0 && total.isEmpty {
                    Button {
                        total = String(format: "%.2f", computed)
                    } label: {
                        Text(String(format: String(localized: "add_receipt_use_computed"), Receipt.format(computed)))
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, AppSpacing.xxs)
                }
            }
        }
    }

    private var totalField: some View {
        formField("TOTAL") {
            TextField("0.00", text: $total)
                .font(AppFont.title2)
                .keyboardType(.decimalPad)
                .padding(AppSpacing.base)
                .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        }
    }

    private var notesField: some View {
        formField("NOTES (OPTIONAL)") {
            TextField(String(localized: "add_receipt_notes_placeholder"), text: $notes, axis: .vertical)
                .font(.system(size: 15))
                .lineLimit(2...4)
                .padding(AppSpacing.base)
                .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        }
    }

    private var saveButton: some View {
        Button { Task { await save() } } label: {
            Group {
                if isSaving { ProgressView().tint(Color(UIColor.systemBackground)) }
                else {
                    Text(String(localized: "add_receipt_save"))
                        .font(AppFont.headline)
                }
            }
            .foregroundStyle(Color(UIColor.systemBackground))
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(canSave ? Color.accentColor : Color.primary.opacity(0.25),
                        in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSave || isSaving)
    }

    private var canSave: Bool {
        !storeName.trimmingCharacters(in: .whitespaces).isEmpty ||
        Double(total.replacingOccurrences(of: ",", with: ".")) != nil
    }

    private func formField<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(label)).font(AppFont.label).foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: - Save

    private func save() async {
        guard let propId = propertyService.primary?.id else { return }
        isSaving = true
        defer { isSaving = false }

        let totalDouble = Double(total.replacingOccurrences(of: ",", with: ".")) ?? 0
        let now = ISO8601DateFormatter().string(from: Date())
        let dateStr = ReceiptParser.isoDate(date)

        let payload = NewReceiptPayload(
            propertyId: propId,
            storeName: storeName.trimmingCharacters(in: .whitespaces),
            date: dateStr,
            total: totalDouble,
            category: category,
            imageUrl: nil,
            notes: notes.isEmpty ? nil : notes,
            createdAt: now,
            updatedAt: now
        )
        let parsedItems = items.compactMap { item -> NewReceiptItemPayload? in
            let name = item.name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            let price = Double(item.priceText.replacingOccurrences(of: ",", with: ".")) ?? 0
            return NewReceiptItemPayload(
                receiptId: UUID(),
                propertyId: propId,
                name: name,
                quantity: 1,
                unitPrice: price,
                totalPrice: price,
                category: category,
                createdAt: now
            )
        }
        do {
            try await receiptService.addReceipt(payload, items: parsedItems)
            HapticFeedback.success()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Editable item helper

private struct EditableReceiptItem: Identifiable {
    let id = UUID()
    var name = ""
    var priceText = ""
}
