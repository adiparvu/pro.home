import SwiftUI

// MARK: - Add supply item sheet

struct AddSupplyItemSheet: View {
    @Environment(SupplyService.self) private var supplyService
    @Environment(PropertyService.self) private var propertyService
    @Environment(ReceiptService.self) private var receiptService
    @Environment(\.dismiss) private var dismiss

    let list: SupplyList?
    let editingItem: SupplyItem?

    @State private var name = ""
    @State private var quantity = ""
    @State private var category = "other"
    @State private var priority = "medium"
    @State private var notes = ""
    @State private var location = ""
    @State private var selectedListId: UUID? = nil
    @State private var isSaving = false
    @State private var error: String?
    /// Real purchase history only, computed once per presentation.
    @State private var frequentSuggestions: [String] = []

    init(list: SupplyList?, editingItem: SupplyItem?) {
        self.list = list
        self.editingItem = editingItem
        if let item = editingItem {
            _name      = State(initialValue: item.name)
            _quantity  = State(initialValue: item.quantity ?? "")
            _category  = State(initialValue: item.category)
            _priority  = State(initialValue: item.priority)
            _notes     = State(initialValue: item.notes ?? "")
            // Stored canonically (or as legacy free text) — edit what the
            // user reads, not the slug.
            _location  = State(initialValue: (item.location).map(SupplyLocation.displayName(for:)) ?? "")
        }
    }

    private var effectiveList: SupplyList? {
        list ?? supplyService.lists.first { $0.id == selectedListId } ?? supplyService.lists.first
    }

    var body: some View {
        FormScaffold(title: editingItem == nil ? "New Item" : "Edit Item",
                     saveLabel: editingItem == nil ? "Add" : "Save",
                     canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty,
                     isSaving: isSaving,
                     error: $error,
                     onSave: { save() }) {
            nameField
            if editingItem == nil && !frequentSuggestions.isEmpty { frequentSection }
            quantityField
            if list == nil && supplyService.lists.count > 1 { listPicker }
            categoryPicker
            priorityPicker
            locationField
            notesField
        }
        .onAppear {
            if list == nil { selectedListId = supplyService.lists.first?.id }
            if editingItem == nil {
                frequentSuggestions = receiptService.frequentProducts(
                    excluding: supplyService.items.filter { !$0.isCompleted }.map(\.name),
                    limit: 6)
            }
        }
    }

    private func fieldLabel(_ key: LocalizedStringKey) -> some View {
        Text(key).font(AppFont.label).foregroundStyle(.secondary)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("sup_field_name")
            TextField("What needs to be bought?", text: $name)
                .font(AppFont.scaled(16)).foregroundStyle(.primary).tint(.accentColor)
                .padding(AppSpacing.base)
                .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        }
    }

    private var quantityField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("sup_field_quantity")
            TextField("e.g. 2 pcs, 500 ml, 1 kg…", text: $quantity)
                .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                .padding(AppSpacing.base)
                .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        }
    }

    /// "You buy this often" — the household's most scanned products, one
    /// tap to fill the name (category follows the lexicon). Only real
    /// history: no scans, no section.
    private var frequentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(AppFont.scaled(10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(String(localized: "sup_frequent_label"))
                    .font(AppFont.label).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(frequentSuggestions, id: \.self) { suggestion in
                        GlassFilterChip(label: suggestion,
                                        isSelected: name == suggestion) {
                            name = suggestion
                            category = supplyCategory(forProduct: suggestion)
                            HapticFeedback.selection()
                        }
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    /// Maps the lexicon's ReceiptCategory to this form's supply categories.
    private func supplyCategory(forProduct product: String) -> String {
        let receiptCategory = ReceiptProductLexicon.category(for: product)
        return supplyCategories.contains { $0.id == receiptCategory } ? receiptCategory : "other"
    }

    private var locationField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "mappin")
                    .font(AppFont.scaled(10, weight: .semibold))
                    .foregroundStyle(.secondary)
                fieldLabel("sup_field_location")
            }
            TextField("e.g. Pantry, Bathroom, Kitchen…", text: $location)
                .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                .padding(AppSpacing.base)
                .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("sup_field_notes")
            TextField("Additional notes…", text: $notes, axis: .vertical)
                .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                .lineLimit(2...5).padding(AppSpacing.base)
                .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        }
    }

    private var listPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("sup_field_list")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(supplyService.lists) { l in
                        Button { selectedListId = l.id; HapticFeedback.selection() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: l.icon).font(AppFont.scaled(12))
                                Text(l.name).font(AppFont.scaled(13))
                            }
                            .foregroundStyle(selectedListId == l.id ? .white : .primary)
                            .padding(.horizontal, AppSpacing.md).padding(.vertical, 7)
                            .background(selectedListId == l.id ? l.swiftColor : Color.primary.opacity(0.08),
                                        in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("sup_field_category")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(supplyCategories, id: \.id) { cat in
                        Button { category = cat.id; HapticFeedback.selection() } label: {
                            Text(LocalizedStringKey(cat.label))
                                .font(AppFont.scaled(13, weight: category == cat.id ? .semibold : .regular))
                                .foregroundStyle(category == cat.id ? .white : Color.primary.opacity(0.65))
                                .padding(.horizontal, 13).padding(.vertical, 7)
                                .background(category == cat.id ? Color.accentColor : Color.primary.opacity(AppOpacity.subtleFill),
                                            in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private var priorityPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("sup_field_priority")
            HStack(spacing: 8) {
                ForEach(supplyPriorities, id: \.id) { p in
                    let item = SupplyItem(id: UUID(), listId: UUID(), propertyId: UUID(),
                                         name: "", category: "other", priority: p.id,
                                         isCompleted: false, createdAt: "", updatedAt: "")
                    Button { priority = p.id; HapticFeedback.selection() } label: {
                        Text(LocalizedStringKey(p.label))
                            .font(AppFont.scaled(13, weight: priority == p.id ? .semibold : .regular))
                            .foregroundStyle(priority == p.id ? .white : Color.primary.opacity(0.65))
                            .padding(.horizontal, AppSpacing.md).padding(.vertical, 7)
                            .background(priority == p.id ? item.priorityColor : Color.primary.opacity(AppOpacity.subtleFill),
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func save() {
        guard let propId = propertyService.primary?.id else { return }
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        isSaving = true
        // Locations persist canonically ("kitchen"), display localized.
        let storedLocation = SupplyLocation.normalized(location)

        if let existing = editingItem {
            var updated = existing
            updated.name     = n
            updated.quantity = quantity.isEmpty ? nil : quantity
            updated.category = category
            updated.priority = priority
            updated.notes    = notes.isEmpty ? nil : notes
            updated.location = storedLocation.isEmpty ? nil : storedLocation
            Task {
                await supplyService.updateItem(updated)
                HapticFeedback.success()
                dismiss()
                isSaving = false
            }
        } else {
            guard let targetList = effectiveList else { isSaving = false; return }
            let now = ISO8601DateFormatter().string(from: Date())
            let payload = NewSupplyItemPayload(
                listId: targetList.id, propertyId: propId,
                name: n,
                quantity: quantity.isEmpty ? nil : quantity,
                category: category, priority: priority,
                notes: notes.isEmpty ? nil : notes,
                isCompleted: false,
                location: storedLocation.isEmpty ? nil : storedLocation,
                createdAt: now, updatedAt: now
            )
            Task {
                do {
                    _ = try await supplyService.addItem(payload)
                    HapticFeedback.success()
                    dismiss()
                } catch {
                    self.error = error.recordableDescription
                }
                isSaving = false
            }
        }
    }
}
