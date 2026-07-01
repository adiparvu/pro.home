import SwiftUI

// MARK: - Add supply item sheet

struct AddSupplyItemSheet: View {
    @EnvironmentObject private var supplyService: SupplyService
    @EnvironmentObject private var propertyService: PropertyService
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

    init(list: SupplyList?, editingItem: SupplyItem?) {
        self.list = list
        self.editingItem = editingItem
        if let item = editingItem {
            _name      = State(initialValue: item.name)
            _quantity  = State(initialValue: item.quantity ?? "")
            _category  = State(initialValue: item.category)
            _priority  = State(initialValue: item.priority)
            _notes     = State(initialValue: item.notes ?? "")
            _location  = State(initialValue: item.location ?? "")
        }
    }

    private var effectiveList: SupplyList? {
        list ?? supplyService.lists.first { $0.id == selectedListId } ?? supplyService.lists.first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        nameField
                        quantityField
                        if list == nil && supplyService.lists.count > 1 { listPicker }
                        categoryPicker
                        priorityPicker
                        locationField
                        notesField
                        if let error { Text(error).font(.caption).foregroundStyle(.red) }
                        saveButton
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20).padding(.top, 16)
                }
            }
            .navigationTitle(editingItem == nil ? String(localized: "New Item") : String(localized: "Edit Item"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            if list == nil { selectedListId = supplyService.lists.first?.id }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text).font(AppFont.label).foregroundStyle(.secondary)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("NAME")
            TextField("What needs to be bought?", text: $name)
                .font(.system(size: 16)).foregroundStyle(.primary).tint(.accentColor)
                .padding(14)
                .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var quantityField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("QUANTITY (OPTIONAL)")
            TextField("e.g. 2 pcs, 500 ml, 1 kg…", text: $quantity)
                .font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor)
                .padding(14)
                .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var locationField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("LOCATION (OPTIONAL)")
            TextField("e.g. Pantry, Bathroom, Kitchen…", text: $location)
                .font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor)
                .padding(14)
                .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("NOTES (OPTIONAL)")
            TextField("Additional notes…", text: $notes, axis: .vertical)
                .font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor)
                .lineLimit(2...5).padding(14)
                .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var listPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("LIST")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(supplyService.lists) { l in
                        Button { selectedListId = l.id; HapticFeedback.selection() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: l.icon).font(.system(size: 12))
                                Text(l.name).font(.system(size: 13))
                            }
                            .foregroundStyle(selectedListId == l.id ? .white : .primary)
                            .padding(.horizontal, 12).padding(.vertical, 7)
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
            fieldLabel("CATEGORY")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(supplyCategories, id: \.id) { cat in
                        Button { category = cat.id; HapticFeedback.selection() } label: {
                            Text(cat.label)
                                .font(.system(size: 13, weight: category == cat.id ? .semibold : .regular))
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
            fieldLabel("PRIORITY")
            HStack(spacing: 8) {
                ForEach(supplyPriorities, id: \.id) { p in
                    let item = SupplyItem(id: UUID(), listId: UUID(), propertyId: UUID(),
                                         name: "", category: "other", priority: p.id,
                                         isCompleted: false, createdAt: "", updatedAt: "")
                    Button { priority = p.id; HapticFeedback.selection() } label: {
                        Text(p.label)
                            .font(.system(size: 13, weight: priority == p.id ? .semibold : .regular))
                            .foregroundStyle(priority == p.id ? .white : Color.primary.opacity(0.65))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(priority == p.id ? item.priorityColor : Color.primary.opacity(AppOpacity.subtleFill),
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var saveButton: some View {
        Button { save() } label: {
            Group {
                if isSaving { ProgressView().tint(.primary) }
                else {
                    Text(LocalizedStringKey(editingItem == nil ? "Add item" : "Save changes"))
                        .font(AppFont.headline)
                }
            }
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(name.trimmingCharacters(in: .whitespaces).isEmpty
                ? Color.primary.opacity(0.2) : Color.primary,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(name.trimmingCharacters(in: .whitespaces).isEmpty
                ? Color.primary.opacity(0.4) : Color(UIColor.systemBackground))
        }
        .buttonStyle(.plain)
        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
    }

    private func save() {
        guard let propId = propertyService.primary?.id else { return }
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        isSaving = true

        if let existing = editingItem {
            var updated = existing
            updated.name     = n
            updated.quantity = quantity.isEmpty ? nil : quantity
            updated.category = category
            updated.priority = priority
            updated.notes    = notes.isEmpty ? nil : notes
            updated.location = location.isEmpty ? nil : location
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
                location: location.isEmpty ? nil : location,
                createdAt: now, updatedAt: now
            )
            Task {
                do {
                    _ = try await supplyService.addItem(payload)
                    HapticFeedback.success()
                    dismiss()
                } catch {
                    self.error = error.localizedDescription
                }
                isSaving = false
            }
        }
    }
}
