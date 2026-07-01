import SwiftUI

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
            PageHeader(title: list.name, subtitleKey: "SUPPLIES")

            searchBar
                .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.sm).padding(.bottom, AppSpacing.xs)

            categoryChips
                .padding(.bottom, AppSpacing.sm)

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
                        .font(AppFont.title3)
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("Add item")
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
                .font(AppFont.footnoteEmphasis)
                .foregroundStyle(.secondary)
            TextField("Search items…", text: $searchText)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, AppSpacing.base).padding(.vertical, 10)
        .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
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
                Text(LocalizedStringKey(label))
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                if count > 0 && !isSelected {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.primary.opacity(0.12), in: Capsule())
                }
            }
            .foregroundStyle(isSelected ? .white : Color.primary.opacity(AppOpacity.emphasis))
            .padding(.horizontal, 13).padding(.vertical, AppSpacing.xs)
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
                        .padding(.horizontal, AppSpacing.xl)
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
                            .padding(.horizontal, AppSpacing.xl)
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
                                    .font(AppFont.label)
                                    .tracking(0.5)
                                Spacer()
                            }
                            .foregroundStyle(Color(red: 0.2, green: 0.78, blue: 0.45))
                            .padding(.horizontal, 28).padding(.vertical, AppSpacing.sm)
                            .background(appBackground)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer(minLength: 120)
            }
            .padding(.top, AppSpacing.md)
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        HStack {
            Text(title)
                .font(AppFont.label)
                .foregroundStyle(.secondary)
                .tracking(0.5)
            Spacer()
        }
        .padding(.horizontal, 28).padding(.vertical, AppSpacing.xs)
        .background(appBackground)
    }

    // MARK: States

    private var emptyListState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "cart")
                .font(.system(size: 48)).foregroundStyle(Color.primary.opacity(0.12))
            Text("No items in this list")
                .font(AppFont.headline).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
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
                .font(AppFont.subheadline).foregroundStyle(Color.primary.opacity(0.4))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
