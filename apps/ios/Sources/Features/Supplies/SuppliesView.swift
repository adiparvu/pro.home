import SwiftUI

// MARK: - Category helpers

private let supplyCategories: [(id: String, label: String)] = [
    ("food",        "Food"),
    ("cleaning",    "Cleaning"),
    ("bathroom",    "Bathroom"),
    ("garden",      "Garden"),
    ("diy",         "DIY"),
    ("electronics", "Electronics"),
    ("pet",         "Pets"),
    ("other",       "Other"),
]

private let supplyPriorities: [(id: String, label: String)] = [
    ("low",      "Low"),
    ("medium",   "Medium"),
    ("high",     "High"),
    ("critical", "Critical"),
]

// MARK: - Main Supplies view

struct SuppliesView: View {
    @EnvironmentObject private var supplyService: SupplyService
    @EnvironmentObject private var propertyService: PropertyService
    @State private var showAddList = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Supplies", subtitle: "PROPERTY")

            if propertyService.primary == nil {
                noPropertyState
            } else if supplyService.isLoading && supplyService.lists.isEmpty {
                loadingState
            } else if supplyService.lists.isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddList = true; HapticFeedback.impact(.light) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
        .sheet(isPresented: $showAddList) {
            AddSupplyListSheet()
                .environmentObject(supplyService)
                .environmentObject(propertyService)
        }
        .task {
            if let id = propertyService.primary?.id {
                await supplyService.load(propertyId: id)
            }
        }
        .userActivity("com.prvio.shopping") { activity in
            activity.title = "Shopping — PRVIO"
            activity.userInfo = ["tab": "shopping"]
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch = true
        }
    }

    // MARK: Lists content

    private var listContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                summaryCard
                listsGrid
                if supplyService.totalPending > 0 { upNextSection }
                Spacer(minLength: 110)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
        .refreshable {
            if let id = propertyService.primary?.id {
                await supplyService.load(propertyId: id)
            }
        }
    }

    // MARK: Summary card

    private var summaryCard: some View {
        GlassCard(padding: 18) {
            HStack(spacing: 0) {
                statCell(value: "\(supplyService.lists.count)", label: "Lists")
                Divider().frame(height: 32).opacity(0.3)
                statCell(value: "\(supplyService.totalPending)", label: "To buy")
                Divider().frame(height: 32).opacity(0.3)
                statCell(value: "\(supplyService.totalCompleted)", label: "Completed")
            }
        }
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Lists grid

    private var listsGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LISTS")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(supplyService.lists) { list in
                    NavigationLink(destination:
                        SupplyListDetailView(list: list)
                            .environmentObject(supplyService)
                            .environmentObject(propertyService)
                    ) {
                        SupplyListCard(list: list)
                            .environmentObject(supplyService)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { await supplyService.deleteList(list) }
                        } label: {
                            Label("Delete list", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: Up next

    private var upNextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("URGENT")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    let urgent = supplyService.items
                        .filter { !$0.isCompleted && ($0.priority == "critical" || $0.priority == "high") }
                        .prefix(5)
                    ForEach(Array(urgent.enumerated()), id: \.element.id) { idx, item in
                        compactItemRow(item, isLast: idx == urgent.count - 1)
                    }
                }
            }
        }
    }

    private func compactItemRow(_ item: SupplyItem, isLast: Bool) -> some View {
        let listName = supplyService.lists.first { $0.id == item.listId }?.name ?? ""
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(item.categoryColor.opacity(0.14))
                        .frame(width: 30, height: 30)
                    Image(systemName: item.categoryIcon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(item.categoryColor)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(listName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(item.priorityColor)
                    .frame(width: 3, height: 22)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            if !isLast {
                Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 54)
            }
        }
    }

    // MARK: Empty / loading states

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "cart.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(Color.primary.opacity(0.12))
            Text("No supplies lists")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.6))
            Text("Create your first list for food,\ncleaning, garden, and more.")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.35))
                .multilineTextAlignment(.center)
            Button { showAddList = true } label: {
                Label("Add first list", systemImage: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22).padding(.vertical, 13)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }

    private var loadingState: some View {
        VStack { Spacer(); ProgressView().tint(.primary); Spacer() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noPropertyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "house.slash")
                .font(.system(size: 48)).foregroundStyle(Color.primary.opacity(0.12))
            Text("No property added")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.5))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - List card

private struct SupplyListCard: View {
    @EnvironmentObject private var supplyService: SupplyService
    let list: SupplyList

    var body: some View {
        GlassCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(
                        colors: [list.swiftColor.opacity(0.65), list.swiftColor.opacity(0.35)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .frame(height: 72)

                    Image(systemName: list.icon)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(14)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(list.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    let pending = supplyService.pendingCount(for: list.id)
                    Text(pending == 0 ? "All done" : "\(pending) to buy")
                        .font(.system(size: 11))
                        .foregroundStyle(pending == 0
                            ? Color(red: 0.2, green: 0.78, blue: 0.45)
                            : Color.primary.opacity(0.45))
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
        }
    }
}

// MARK: - List detail view

struct SupplyListDetailView: View {
    @EnvironmentObject private var supplyService: SupplyService
    @EnvironmentObject private var propertyService: PropertyService
    var list: SupplyList

    @State private var searchText = ""
    @State private var selectedCategory: String? = nil
    @State private var showAddItem = false
    @State private var editingItem: SupplyItem? = nil
    @State private var showCompleted = false

    private var listItems: [SupplyItem] { supplyService.items(for: list.id) }

    private var filtered: [SupplyItem] {
        listItems.filter { item in
            let matchSearch = searchText.isEmpty || item.name.localizedCaseInsensitiveContains(searchText)
            let matchCat = selectedCategory == nil || item.category == selectedCategory
            return matchSearch && matchCat
        }
    }

    private var pending: [SupplyItem] { filtered.filter { !$0.isCompleted } }
    private var completed: [SupplyItem] { filtered.filter { $0.isCompleted } }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: list.name, subtitle: "SUPPLIES")

            searchBar
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 6)

            categoryChips
                .padding(.bottom, 8)

            Divider().opacity(0.3)

            if listItems.isEmpty {
                emptyListState
            } else if filtered.isEmpty {
                noResultsState
            } else {
                itemsScroll
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddItem = true; HapticFeedback.impact(.light) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
        .sheet(isPresented: $showAddItem) {
            AddSupplyItemSheet(list: list, editingItem: nil)
                .environmentObject(supplyService)
                .environmentObject(propertyService)
        }
        .sheet(item: $editingItem) { item in
            AddSupplyItemSheet(list: list, editingItem: item)
                .environmentObject(supplyService)
                .environmentObject(propertyService)
        }
        .floatingSpeedDial(.supplies)
    }

    // MARK: Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Search items…", text: $searchText)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.primary.opacity(0.35))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Category chips

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Spacer(minLength: 20)
                chip(label: "All", id: nil)
                ForEach(supplyCategories, id: \.id) { cat in
                    let count = listItems.filter { $0.category == cat.id && !$0.isCompleted }.count
                    if count > 0 || selectedCategory == cat.id {
                        chip(label: cat.label, id: cat.id, count: count)
                    }
                }
                Spacer(minLength: 20)
            }
        }
    }

    private func chip(label: String, id: String?, count: Int = 0) -> some View {
        let isSelected = selectedCategory == id
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedCategory = id }
            HapticFeedback.selection()
        } label: {
            HStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                if count > 0 && !isSelected {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.primary.opacity(0.12), in: Capsule())
                }
            }
            .foregroundStyle(isSelected ? .white : Color.primary.opacity(0.7))
            .padding(.horizontal, 13).padding(.vertical, 6)
            .background(isSelected ? list.swiftColor : Color.primary.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    // MARK: Items scroll

    private var itemsScroll: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                if !pending.isEmpty {
                    Section {
                        GlassCard(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(pending.enumerated()), id: \.element.id) { idx, item in
                                    SupplyItemRow(item: item, isLast: idx == pending.count - 1) {
                                        Task { await supplyService.toggleComplete(item); HapticFeedback.success() }
                                    } onEdit: {
                                        editingItem = item
                                    } onDelete: {
                                        Task { await supplyService.deleteItem(item) }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    } header: {
                        sectionHeader("TO BUY · \(pending.count)")
                    }
                }

                if !completed.isEmpty {
                    Section {
                        if showCompleted {
                            GlassCard(padding: 0) {
                                VStack(spacing: 0) {
                                    ForEach(Array(completed.enumerated()), id: \.element.id) { idx, item in
                                        SupplyItemRow(item: item, isLast: idx == completed.count - 1) {
                                            Task { await supplyService.toggleComplete(item); HapticFeedback.selection() }
                                        } onEdit: {
                                            editingItem = item
                                        } onDelete: {
                                            Task { await supplyService.deleteItem(item) }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    } header: {
                        Button {
                            withAnimation(.spring(response: 0.35)) { showCompleted.toggle() }
                            HapticFeedback.selection()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: showCompleted ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("COMPLETED · \(completed.count)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .tracking(0.5)
                                Spacer()
                            }
                            .foregroundStyle(Color(red: 0.2, green: 0.78, blue: 0.45))
                            .padding(.horizontal, 28).padding(.vertical, 8)
                            .background(appBackground)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer(minLength: 120)
            }
            .padding(.top, 12)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            Spacer()
        }
        .padding(.horizontal, 28).padding(.vertical, 6)
        .background(appBackground)
    }

    // MARK: States

    private var emptyListState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "cart")
                .font(.system(size: 48)).foregroundStyle(Color.primary.opacity(0.12))
            Text("No items in this list")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.5))
            Text("Tap + to add the first item.")
                .font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.3))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36)).foregroundStyle(Color.primary.opacity(0.12))
            Text("No results")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.primary.opacity(0.4))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Item row

private struct SupplyItemRow: View {
    let item: SupplyItem
    let isLast: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onToggle) {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(item.isCompleted
                            ? Color(red: 0.2, green: 0.78, blue: 0.45)
                            : Color.primary.opacity(0.28))
                        .symbolEffect(.bounce, value: item.isCompleted)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.system(size: 15))
                            .foregroundStyle(item.isCompleted ? Color.primary.opacity(0.35) : .primary)
                            .strikethrough(item.isCompleted, color: .secondary)
                            .lineLimit(1)
                        if let qty = item.quantity, !qty.isEmpty {
                            Text(qty)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(item.categoryColor)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(item.categoryColor.opacity(0.12), in: Capsule())
                        }
                    }
                    if let loc = item.location, !loc.isEmpty {
                        Label(loc, systemImage: "mappin.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.primary.opacity(0.35))
                    }
                }

                Spacer()

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(item.isCompleted ? Color.clear : item.priorityColor)
                    .frame(width: 3, height: 24)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .contentShape(Rectangle())
            .contextMenu {
                Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
                Button {
                    onToggle()
                } label: {
                    Label(item.isCompleted ? "Mark as incomplete" : "Mark as complete",
                          systemImage: item.isCompleted ? "circle" : "checkmark.circle")
                }
                Divider()
                Button(role: .destructive) { onDelete() } label: {
                    Label("Delete", systemImage: "trash")
                }
            }

            if !isLast {
                Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 58)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                onToggle()
            } label: {
                Label(item.isCompleted ? "Undo" : "Complete",
                      systemImage: item.isCompleted ? "arrow.uturn.backward" : "checkmark")
            }
            .tint(item.isCompleted ? .orange : Color(red: 0.2, green: 0.78, blue: 0.45))
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
            Button { onEdit() } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.accentColor)
        }
    }
}

// MARK: - Add supply list sheet

struct AddSupplyListSheet: View {
    @EnvironmentObject private var supplyService: SupplyService
    @EnvironmentObject private var propertyService: PropertyService
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedIcon = "cart.fill"
    @State private var selectedColor = "007AFF"
    @State private var note = ""
    @State private var isSaving = false
    @State private var error: String?

    private let iconOptions = ["cart.fill","fork.knife","sparkles","leaf.fill","hammer.fill",
                               "lightbulb.fill","pawprint.fill","drop.fill","house.fill","bag.fill"]

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        previewCard
                        nameField
                        iconPicker
                        colorPicker
                        noteField
                        if let error { Text(error).font(.caption).foregroundStyle(.red) }
                        saveButton
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20).padding(.top, 16)
                }
            }
            .navigationTitle("New List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var previewCard: some View {
        let color = SupplyList.colorOptions.first { $0.hex == selectedColor }.flatMap {
            Color(hex: $0.hex)
        } ?? .blue
        return GlassCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: [color.opacity(0.7), color.opacity(0.4)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(height: 72)
                    Image(systemName: selectedIcon)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(14)
                }
                Text(name.isEmpty ? "List name" : name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(name.isEmpty ? Color.primary.opacity(0.3) : .primary)
                    .padding(.horizontal, 12).padding(.vertical, 10)
            }
        }
        .frame(width: 150)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NAME")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            TextField("e.g. Supermarket, Garden, Bathroom…", text: $name)
                .font(.system(size: 16)).foregroundStyle(.primary).tint(.accentColor)
                .padding(14)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTE (OPTIONAL)")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            TextField("Note about this list…", text: $note, axis: .vertical)
                .font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor)
                .lineLimit(2...4).padding(14)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var iconPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ICON")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            let color = Color(hex: selectedColor) ?? .blue
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                ForEach(iconOptions, id: \.self) { icon in
                    Button { selectedIcon = icon; HapticFeedback.selection() } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selectedIcon == icon ? color.opacity(0.18) : Color.primary.opacity(0.07))
                                .frame(height: 52)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(selectedIcon == icon ? color : Color.clear, lineWidth: 2)
                                )
                            Image(systemName: icon)
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(selectedIcon == icon ? color : Color.primary.opacity(0.5))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COLOR")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                ForEach(SupplyList.colorOptions, id: \.hex) { opt in
                    let c = Color(hex: opt.hex) ?? .blue
                    Button { selectedColor = opt.hex; HapticFeedback.selection() } label: {
                        ZStack {
                            Circle().fill(c).frame(width: 32, height: 32)
                            if selectedColor == opt.hex {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }

    private var saveButton: some View {
        Button { save() } label: {
            Group {
                if isSaving { ProgressView().tint(.primary) }
                else {
                    Text("Create list")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(name.trimmingCharacters(in: .whitespaces).isEmpty
                ? Color.primary.opacity(0.2)
                : Color.primary,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(name.trimmingCharacters(in: .whitespaces).isEmpty
                ? Color.primary.opacity(0.4)
                : Color(UIColor.systemBackground))
        }
        .buttonStyle(.plain)
        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
    }

    private func save() {
        guard let propId = propertyService.primary?.id,
              let ownerId = supabase.auth.currentSession?.user.id else { return }
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        isSaving = true
        let now = ISO8601DateFormatter().string(from: Date())
        let payload = NewSupplyListPayload(propertyId: propId, ownerId: ownerId,
                                           name: n, icon: selectedIcon, color: selectedColor,
                                           note: note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note,
                                           createdAt: now, updatedAt: now)
        Task {
            do {
                _ = try await supplyService.addList(payload)
                HapticFeedback.success()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            isSaving = false
        }
    }
}

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
            .navigationTitle(editingItem == nil ? "New Item" : "Edit Item")
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
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("NAME")
            TextField("What needs to be bought?", text: $name)
                .font(.system(size: 16)).foregroundStyle(.primary).tint(.accentColor)
                .padding(14)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var quantityField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("QUANTITY (OPTIONAL)")
            TextField("e.g. 2 pcs, 500 ml, 1 kg…", text: $quantity)
                .font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor)
                .padding(14)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var locationField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("LOCATION (OPTIONAL)")
            TextField("e.g. Pantry, Bathroom, Kitchen…", text: $location)
                .font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor)
                .padding(14)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("NOTES (OPTIONAL)")
            TextField("Additional notes…", text: $notes, axis: .vertical)
                .font(.system(size: 15)).foregroundStyle(.primary).tint(.accentColor)
                .lineLimit(2...5).padding(14)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                                .background(category == cat.id ? Color.accentColor : Color.primary.opacity(0.07),
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
                            .background(priority == p.id ? item.priorityColor : Color.primary.opacity(0.07),
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
                    Text(editingItem == nil ? "Add item" : "Save changes")
                        .font(.system(size: 16, weight: .semibold))
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

