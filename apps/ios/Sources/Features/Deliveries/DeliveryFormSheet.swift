import SwiftUI

// MARK: - DeliveryFormSheet (Add + Edit)

struct DeliveryFormSheet: View {
    @Environment(DeliveryService.self) private var deliveryService
    @Environment(\.dismiss) private var dismiss

    let editingDelivery: Delivery?

    @State private var description: String
    @State private var carrier: String
    @State private var trackingNumber: String
    @State private var status: String
    @State private var hasExpectedDate: Bool
    @State private var expectedDate: Date
    @State private var notes: String
    @State private var isSaving = false

    private var isEditing: Bool { editingDelivery != nil }

    private var canSave: Bool {
        !description.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    init(editingDelivery: Delivery?) {
        self.editingDelivery = editingDelivery

        if let d = editingDelivery {
            _description    = State(initialValue: d.description)
            _carrier        = State(initialValue: d.carrier ?? Delivery.carrierOptions.first ?? "DHL")
            _trackingNumber = State(initialValue: d.trackingNumber ?? "")
            _status         = State(initialValue: d.status)
            _notes          = State(initialValue: d.notes ?? "")

            if let ds = d.expectedDate,
               let parsed = Self.parseExpectedDate(ds) {
                _hasExpectedDate = State(initialValue: true)
                _expectedDate    = State(initialValue: parsed)
            } else {
                _hasExpectedDate = State(initialValue: false)
                _expectedDate    = State(initialValue: Date())
            }
        } else {
            _description    = State(initialValue: "")
            _carrier        = State(initialValue: Delivery.carrierOptions.first ?? "DHL")
            _trackingNumber = State(initialValue: "")
            _status         = State(initialValue: "expected")
            _hasExpectedDate = State(initialValue: false)
            _expectedDate   = State(initialValue: Date())
            _notes          = State(initialValue: "")
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        descriptionField
                        carrierPickerSection
                        trackingField
                        statusPickerSection
                        expectedDateSection
                        notesField
                        saveButton
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.lg)
                }
            }
            .navigationTitle(isEditing ? String(localized: "Edit delivery") : String(localized: "New delivery"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationBackground(.thinMaterial)
    }

    // MARK: Fields

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("DESCRIPTION *")
            TextField("e.g. Laptop, Shoes, Book…", text: $description)
                .font(AppFont.scaled(16))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .padding(AppSpacing.base)
                .background(
                    Color.primary.opacity(AppOpacity.subtleFill),
                    in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                )
        }
    }

    private var trackingField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("TRACKING CODE")
            TextField("ex. 1Z999AA10123456784", text: $trackingNumber)
                .font(AppFont.scaled(15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .padding(AppSpacing.base)
                .background(
                    Color.primary.opacity(AppOpacity.subtleFill),
                    in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                )
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("NOTES (OPTIONAL)")
            TextField("Additional notes…", text: $notes, axis: .vertical)
                .font(AppFont.scaled(15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .lineLimit(2...4)
                .padding(AppSpacing.base)
                .background(
                    Color.primary.opacity(AppOpacity.subtleFill),
                    in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                )
        }
    }

    // MARK: Carrier picker

    private var carrierPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("CARRIER")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Delivery.carrierOptions, id: \.self) { c in
                        Button {
                            carrier = c
                            HapticFeedback.selection()
                        } label: {
                            Text(c)
                                .font(AppFont.scaled(13, weight: carrier == c ? .semibold : .regular))
                                .foregroundStyle(carrier == c ? .white : Color.primary.opacity(0.65))
                                .padding(.horizontal, AppSpacing.base)
                                .padding(.vertical, AppSpacing.sm)
                                .background(
                                    carrier == c ? Color.accentColor : Color.primary.opacity(AppOpacity.subtleFill),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    // MARK: Status picker

    private var statusPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("STATUS")
            VStack(spacing: 0) {
                ForEach(Array(Delivery.statusOptions.enumerated()), id: \.element.id) { idx, opt in
                    Button {
                        status = opt.id
                        HapticFeedback.selection()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: statusIcon(for: opt.id))
                                .font(AppFont.footnoteEmphasis)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.primary)
                                .frame(width: 32, height: 32)
                                .glassCircle()
                            Text(LocalizedStringKey(opt.label))
                                .font(AppFont.scaled(15))
                                .foregroundStyle(.primary)
                            Spacer()
                            if status == opt.id {
                                Image(systemName: "checkmark")
                                    .font(AppFont.captionEmphasis)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.horizontal, AppSpacing.base)
                        .padding(.vertical, AppSpacing.md)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if idx < Delivery.statusOptions.count - 1 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.05))
                            .frame(height: 0.5)
                            .padding(.leading, 58)
                    }
                }
            }
            .liquidGlass(cornerRadius: AppRadius.lg)
        }
    }

    private func statusIcon(for id: String) -> String {
        switch id {
        case "expected":         return "shippingbox.fill"
        case "out_for_delivery": return "bicycle"
        case "delivered":        return "checkmark.seal.fill"
        case "missed":           return "exclamationmark.triangle.fill"
        case "returned":         return "arrow.uturn.left.circle.fill"
        default:                 return "shippingbox"
        }
    }

    // MARK: Expected date

    private var expectedDateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("ESTIMATED DELIVERY DATE")

            GlassCard(padding: 14) {
                VStack(spacing: 12) {
                    Toggle(isOn: $hasExpectedDate) {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar")
                                .font(AppFont.scaled(14))
                                .foregroundStyle(Color.accentColor)
                            Text("Set estimated date")
                                .font(AppFont.scaled(15))
                                .foregroundStyle(.primary)
                        }
                    }
                    .tint(.accentColor)

                    if hasExpectedDate {
                        Divider().opacity(0.3)
                        DatePicker(
                            "",
                            selection: $expectedDate,
                            in: Date()...,
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .datePickerStyle(.graphical)
                        .tint(.accentColor)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
        }
    }

    // MARK: Save button

    private var saveButton: some View {
        GlassWideButton(
            label: LocalizedStringKey(isEditing ? "Save changes" : "Add delivery"),
            isBusy: isSaving
        ) {
            Task { await save() }
        }
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.5)
    }

    // MARK: Helpers

    private func fieldLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(AppFont.label)
            .foregroundStyle(.secondary)
    }

    private static func parseExpectedDate(_ string: String) -> Date? {
        AppDate.day(from: string)
    }

    private func expectedDateString() -> String? {
        guard hasExpectedDate else { return nil }
        return AppDate.dayString(from: expectedDate)
    }

    private func save() async {
        let trimmedDesc = description.trimmingCharacters(in: .whitespaces)
        guard !trimmedDesc.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }

        let trimmedTracking = trackingNumber.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)

        if var existing = editingDelivery {
            existing.description    = trimmedDesc
            existing.carrier        = carrier
            existing.trackingNumber = trimmedTracking.isEmpty ? nil : trimmedTracking
            existing.status         = status
            existing.expectedDate   = expectedDateString()
            existing.notes          = trimmedNotes.isEmpty ? nil : trimmedNotes
            await deliveryService.update(existing)
        } else {
            guard let propertyId = deliveryService.currentPropertyId else { return }
            let new = NewDelivery(
                propertyId: propertyId,
                description: trimmedDesc,
                carrier: carrier,
                trackingNumber: trimmedTracking.isEmpty ? nil : trimmedTracking,
                status: status,
                expectedDate: expectedDateString(),
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes
            )
            await deliveryService.add(new)
        }

        HapticFeedback.success()
        dismiss()
    }
}
