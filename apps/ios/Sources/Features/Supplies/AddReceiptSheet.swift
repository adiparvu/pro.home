import SwiftUI
import PhotosUI

// MARK: - Add Receipt (manual entry)

struct AddReceiptSheet: View {
    @Environment(ReceiptService.self) private var receiptService
    @Environment(PropertyService.self) private var propertyService
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.dismiss) private var dismiss

    @State private var storeName = ""
    @State private var date = Date()
    @State private var total = ""
    @State private var category = "food"
    @State private var notes = ""
    @State private var items: [EditableReceiptItem] = []
    @State private var isSaving = false
    @State private var error: String?
    @State private var showScanner = false
    @State private var photoItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?

    var body: some View {
        FormScaffold(title: "add_receipt_title",
                     saveLabel: "Save",
                     canSave: canSave,
                     isSaving: isSaving,
                     error: $error,
                     onSave: { Task { await save() } }) {
            scanHero
            storeField
            dateField
            categoryField
            itemsSection
            totalField
            photoField
            notesField
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    pickedImage = image
                }
            }
        }
        .sheet(isPresented: $showScanner) {
            // The scanner runs the full scan → parse → save; when it saves, it
            // dismisses this manual form too, so the user isn't dropped back on
            // an empty sheet.
            ReceiptScannerView(onSaved: { dismiss() })
                .environment(receiptService)
                .environment(propertyService)
        }
    }

    // MARK: - Scan hero
    //
    // A receipt screen's fastest path is the camera — point it at the receipt
    // and store, date, total and line items fill themselves. Manual entry
    // stays right below for when there's nothing to scan.
    private var scanHero: some View {
        Button {
            showScanner = true
            HapticFeedback.impact(.medium)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.viewfinder.fill")
                    .font(AppFont.scaled(20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("add_receipt_scan_title")
                        .font(AppFont.subheadline)
                        .foregroundStyle(.primary)
                    Text("add_receipt_scan_sub")
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(12, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.3))
            }
            .padding(AppSpacing.base)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Fields

    private var storeField: some View {
        formField("STORE") {
            TextField(String(localized: "add_receipt_store_placeholder"), text: $storeName)
                .font(AppFont.scaled(16))
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
                                Image(systemName: ReceiptCategory.icon(for: cat.id)).font(AppFont.scaled(11))
                                Text(LocalizedStringKey(cat.label)).font(AppFont.scaled(13))
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
                Text("Items")
                    .font(AppFont.label).foregroundStyle(.secondary)
                Spacer()
                Button {
                    items.append(EditableReceiptItem())
                    HapticFeedback.selection()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(AppFont.scaled(16)).foregroundStyle(Color.accentColor)
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
                                    .font(AppFont.scaled(13))
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
                                        .font(AppFont.scaled(16)).foregroundStyle(.red.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, AppSpacing.xxs)
                        }
                    }
                }

                // The items' sum, offered whenever it differs from the entered
                // total — so an empty total fills in one tap and a mismatch
                // (items say 50, total says 45) surfaces instead of hiding.
                let computed = items.compactMap { Double($0.priceText.replacingOccurrences(of: ",", with: ".")) }.reduce(0, +)
                let computedStr = String(format: "%.2f", computed)
                if computed > 0, total != computedStr {
                    Button {
                        total = computedStr
                        HapticFeedback.selection()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "equal.circle")
                                .font(AppFont.scaled(11, weight: .semibold))
                            Text(String(format: String(localized: "add_receipt_use_computed"),
                                        CurrencyService.money(computed, code: appSettings.preferredCurrency)))
                                .font(AppFont.scaled(12))
                        }
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

    private var photoField: some View {
        formField("add_receipt_photo") {
            if let pickedImage {
                HStack(spacing: 12) {
                    Image(uiImage: pickedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                    Text("add_receipt_photo_attached")
                        .font(AppFont.scaled(13))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    Spacer()
                    Button {
                        self.pickedImage = nil
                        photoItem = nil
                        HapticFeedback.selection()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(AppFont.scaled(18))
                            .foregroundStyle(Color.primary.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Remove photo"))
                }
            } else {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    HStack(spacing: 10) {
                        Image(systemName: "photo.badge.plus")
                            .font(AppFont.scaled(16, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                        Text("add_receipt_photo_add")
                            .font(AppFont.scaled(14))
                            .foregroundStyle(Color.accentColor)
                        Spacer()
                    }
                    .padding(AppSpacing.base)
                    .background(Color.primary.opacity(AppOpacity.subtleFill),
                                in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                }
            }
        }
    }

    private var notesField: some View {
        formField("NOTES (OPTIONAL)") {
            TextField(String(localized: "add_receipt_notes_placeholder"), text: $notes, axis: .vertical)
                .font(AppFont.scaled(15))
                .lineLimit(2...4)
                .padding(AppSpacing.base)
                .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        }
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

        // Upload the attached photo (if any) to the private receipt-media bucket
        // first, storing only its path on the receipt.
        var imagePath: String? = nil
        if let pickedImage {
            imagePath = await receiptService.uploadReceiptImage(pickedImage, propertyId: propId)
        }

        let payload = NewReceiptPayload(
            propertyId: propId,
            storeName: storeName.trimmingCharacters(in: .whitespaces),
            date: dateStr,
            total: totalDouble,
            category: category,
            imageUrl: imagePath,
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
            self.error = error.recordableDescription
        }
    }
}

// MARK: - Editable item helper

private struct EditableReceiptItem: Identifiable {
    let id = UUID()
    var name = ""
    var priceText = ""
}
