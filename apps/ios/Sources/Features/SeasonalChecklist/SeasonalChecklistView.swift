import SwiftUI

// MARK: - SeasonalChecklistView

struct SeasonalChecklistView: View {
    @State private var service = SeasonalChecklistService()
    @State var selectedSeason: Season = .current
    @State private var showAddSheet = false
    @State private var editingItem: CustomSeasonalItem?

    private var allItems: [SeasonalListItem] { service.allListItems(for: selectedSeason) }
    private var completedCount: Int { service.completedCount(for: selectedSeason) }
    private var totalCount: Int { service.totalCount(for: selectedSeason) }
    private var isAllDone: Bool { totalCount > 0 && completedCount == totalCount }

    private var groupedItems: [String: [SeasonalListItem]] {
        Dictionary(grouping: allItems, by: \.category)
    }
    private var sortedCategories: [String] {
        let builtin = service.builtinItems(for: selectedSeason).map(\.category)
        var seen = Set<String>()
        var ordered = builtin.filter { seen.insert($0).inserted }
        for cat in groupedItems.keys.sorted() where !seen.contains(cat) { ordered.append(cat) }
        return ordered
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    seasonPicker
                    progressCard
                    if isAllDone { allDoneBanner }
                    checklistContent
                    Spacer(minLength: 110)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.md)
            }
        }
        .navigationTitle("Seasonal Checklists")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    HapticFeedback.impact(.light)
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                }
                .tint(.accentColor)
                .accessibilityLabel("Add item")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddCustomSeasonalItemSheet(season: selectedSeason, existingCategories: existingCategories) { item in
                service.addCustomItem(item)
            }
        }
        .sheet(item: $editingItem) { item in
            AddCustomSeasonalItemSheet(season: selectedSeason, existingCategories: existingCategories, editingItem: item) { updated in
                service.updateCustomItem(updated)
            }
        }
    }

    private var existingCategories: [String] {
        var seen = Set<String>()
        return allItems.map(\.category).filter { seen.insert($0).inserted }
    }

    // MARK: - Season Picker

    private var seasonPicker: some View {
        GlassCard(padding: 10) {
            HStack(spacing: 6) {
                ForEach([Season.spring, .summer, .fall, .winter], id: \.self) { season in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedSeason = season }
                        HapticFeedback.impact(.light)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: season.icon).font(.system(size: 20))
                                .foregroundStyle(selectedSeason == season ? season.color : Color.primary.opacity(0.55))
                            Text(LocalizedStringKey(season.displayName))
                                .font(.system(size: 11, weight: selectedSeason == season ? .semibold : .regular))
                                .foregroundStyle(selectedSeason == season ? .primary : Color.primary.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if selectedSeason == season {
                                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                    .fill(.regularMaterial)
                                    .overlay(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                        .strokeBorder(season.color.opacity(0.5), lineWidth: 1))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Progress Card

    private var progressCard: some View {
        GlassCard {
            HStack(spacing: 16) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.1), lineWidth: 5).frame(width: 52, height: 52)
                    Circle()
                        .trim(from: 0, to: totalCount > 0 ? CGFloat(completedCount) / CGFloat(totalCount) : 0)
                        .stroke(selectedSeason.color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90)).frame(width: 52, height: 52)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: completedCount)
                    Text("\(totalCount > 0 ? Int(CGFloat(completedCount) / CGFloat(totalCount) * 100) : 0)%")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(.primary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(completedCount) of \(totalCount) done")
                        .font(AppFont.headline).foregroundStyle(.primary)
                    Text("\(selectedSeason.displayName) maintenance checklist")
                        .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                }
                Spacer()
            }
        }
    }

    // MARK: - All Done Banner

    private var allDoneBanner: some View {
        GlassCard {
            HStack(spacing: 12) {
                Text("🎉").font(.system(size: 28))
                VStack(alignment: .leading, spacing: 3) {
                    Text("All done!").font(.system(size: 16, weight: .bold)).foregroundStyle(.primary)
                    Text("Your \(selectedSeason.displayName) checklist is complete.")
                        .font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.55))
                }
                Spacer()
            }
        }
        .overlay(RoundedRectangle(cornerRadius: AppRadius.xxl, style: .continuous)
            .strokeBorder(selectedSeason.color.opacity(0.35), lineWidth: 1))
    }

    // MARK: - Checklist

    private var checklistContent: some View {
        LazyVStack(spacing: 16) {
            ForEach(sortedCategories, id: \.self) { category in
                categorySection(category: category, items: groupedItems[category] ?? [])
            }
        }
    }

    private func categorySection(category: String, items: [SeasonalListItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(category))
                .textCase(.uppercase)
                .font(AppFont.label)
                .foregroundStyle(.secondary)
                .padding(.leading, AppSpacing.xs)

            GlassCard(padding: 0) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        listItemRow(item)
                        if index < items.count - 1 {
                            Rectangle()
                                .fill(Color.primary.opacity(0.05))
                                .frame(height: 0.5)
                                .padding(.leading, 52)
                        }
                    }
                }
            }
        }
    }

    private func listItemRow(_ item: SeasonalListItem) -> some View {
        let done = service.isCompleted(item.id)
        return Button {
            service.toggleItem(item.id)
            HapticFeedback.impact(done ? .light : .medium)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(done ? selectedSeason.color : Color.primary.opacity(0.3))
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: done)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.title)
                            .font(AppFont.body)
                            .foregroundStyle(done ? Color.primary.opacity(AppOpacity.disabled) : .primary)
                            .strikethrough(done, color: Color.primary.opacity(AppOpacity.disabled))
                            .animation(.easeInOut(duration: 0.2), value: done)
                        if item.isCustom {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(selectedSeason.color.opacity(0.6))
                        }
                    }
                    if !item.description.isEmpty {
                        Text(item.description)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.primary.opacity(done ? 0.25 : 0.45))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(done ? 0.7 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: done)
        .contextMenu {
            if let custom = item.customItem {
                Button {
                    editingItem = custom
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    withAnimation { service.deleteCustomItem(custom) }
                    HapticFeedback.warning()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Add / Edit Sheet

struct AddCustomSeasonalItemSheet: View {
    let season: Season
    let existingCategories: [String]
    var editingItem: CustomSeasonalItem? = nil
    let onSave: (CustomSeasonalItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var category = ""
    @State private var showCategoryPicker = false

    private var isEditing: Bool { editingItem != nil }
    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Title
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Title")
                                .font(AppFont.captionStrong)
                                .textCase(.uppercase)
                                .foregroundStyle(.secondary)
                                .padding(.leading, AppSpacing.xxs)
                            TextField("What needs to be done?", text: $title)
                                .font(.system(size: 16))
                                .padding(AppSpacing.base)
                                .background(Color.primary.opacity(AppOpacity.subtleFill),
                                            in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                        }

                        // Description
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description (optional)")
                                .font(AppFont.captionStrong)
                                .textCase(.uppercase)
                                .foregroundStyle(.secondary)
                                .padding(.leading, AppSpacing.xxs)
                            TextField("Add details…", text: $description, axis: .vertical)
                                .font(.system(size: 15))
                                .lineLimit(3...5)
                                .padding(AppSpacing.base)
                                .background(Color.primary.opacity(AppOpacity.subtleFill),
                                            in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                        }

                        // Category
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Category")
                                .font(AppFont.captionStrong)
                                .textCase(.uppercase)
                                .foregroundStyle(.secondary)
                                .padding(.leading, AppSpacing.xxs)
                            TextField("E.g. Plumbing, Safety, Custom…", text: $category)
                                .font(.system(size: 15))
                                .padding(AppSpacing.base)
                                .background(Color.primary.opacity(AppOpacity.subtleFill),
                                            in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))

                            // Quick picks
                            if !existingCategories.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(existingCategories, id: \.self) { cat in
                                            Button {
                                                withAnimation { category = cat }
                                            } label: {
                                                Text(LocalizedStringKey(cat))
                                                    .font(.system(size: 12, weight: category == cat ? .semibold : .regular))
                                                    .foregroundStyle(category == cat ? .white : Color.primary.opacity(AppOpacity.emphasis))
                                                    .padding(.horizontal, AppSpacing.md).padding(.vertical, AppSpacing.xs)
                                                    .background(category == cat ? season.color : Color.primary.opacity(0.08),
                                                                in: Capsule())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }

                        // Save button
                        Button {
                            let trimTitle = title.trimmingCharacters(in: .whitespaces)
                            let cat = category.trimmingCharacters(in: .whitespaces).isEmpty ? "Custom" : category.trimmingCharacters(in: .whitespaces)
                            if isEditing, let existing = editingItem {
                                var updated = existing
                                updated.title = trimTitle
                                updated.description = description.trimmingCharacters(in: .whitespaces)
                                updated.category = cat
                                onSave(updated)
                            } else {
                                let item = CustomSeasonalItem(
                                    title: trimTitle,
                                    description: description.trimmingCharacters(in: .whitespaces),
                                    category: cat,
                                    season: season
                                )
                                onSave(item)
                            }
                            HapticFeedback.impact(.medium)
                            dismiss()
                        } label: {
                            Text(isEditing ? "Save Changes" : "Add Item")
                                .font(AppFont.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppSpacing.lg)
                                .background(canSave ? season.color : Color.primary.opacity(0.3),
                                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .foregroundStyle(canSave ? .white : Color.primary.opacity(0.4))
                        }
                        .disabled(!canSave)
                        .buttonStyle(.plain)

                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.lg)
                }
            }
            .navigationTitle(isEditing ? "Edit Item" : "New Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if let item = editingItem {
                    title = item.title
                    description = item.description
                    category = item.category
                }
            }
        }
    }
}
