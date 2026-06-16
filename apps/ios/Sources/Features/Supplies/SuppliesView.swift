import SwiftUI

// MARK: - Category helpers

let supplyCategories: [(id: String, label: String)] = [
    ("food",        "Food"),
    ("cleaning",    "Cleaning"),
    ("bathroom",    "Bathroom"),
    ("garden",      "Garden"),
    ("diy",         "DIY"),
    ("electronics", "Electronics"),
    ("pet",         "Pets"),
    ("other",       "Other"),
]

let supplyPriorities: [(id: String, label: String)] = [
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

// MARK: - Item row

struct SupplyItemRow: View {
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
