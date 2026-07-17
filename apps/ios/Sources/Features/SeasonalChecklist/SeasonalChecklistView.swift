import SwiftUI

// MARK: - SeasonalChecklistView
//
// Seasonal home checks: a compiled-in template personalized through a local,
// per-property overlay (own items, hidden checks, edited wording, item→task
// links) — see SeasonalChecklistService for the storage design. Opens on the
// actual current season; check states are keyed per (season, cycle year), so
// each year starts fresh and past years remain as history rows.

struct SeasonalChecklistView: View {
    @Environment(PropertyService.self) private var propertyService
    @Environment(TaskService.self) private var taskService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // The SHARED checklist service (injected in MainTabView) — the
    // dashboard's seasonal widget reads the same overlay, so a check here
    // moves the widget's progress instantly.
    @Environment(SeasonalChecklistService.self) private var service
    @State private var zoneService = PropertyZoneService()
    @State var selectedSeason: Season = .current
    @State private var showAddSheet = false
    @State private var editingRow: SeasonalRow?
    @State private var taskError: String?
    @State private var sealBloomed = false

    // MARK: Derived state

    /// The home's honesty context: property type + mapped Digital Twin zones.
    private var context: SeasonalPropertyContext {
        SeasonalPropertyContext(
            kind: propertyService.primary.flatMap { PropertyKind(rawValue: $0.propertyType) },
            mappedSpaceKinds: Set(zoneService.zones.map(\.resolvedSpaceKind)),
            hasMappedZones: !zoneService.zones.isEmpty)
    }

    private var allRows: [SeasonalRow] { service.rows(for: selectedSeason, context: context) }
    private var visibleRows: [SeasonalRow] { allRows.filter(\.isVisible) }
    private var displayedRows: [SeasonalRow] { service.showAllChecks ? allRows : visibleRows }
    private var hiddenCount: Int { allRows.count - visibleRows.count }

    private var completedCount: Int {
        visibleRows.filter { service.isCompleted($0.id, season: selectedSeason) }.count
    }
    private var totalCount: Int { visibleRows.count }
    private var isAllDone: Bool { totalCount > 0 && completedCount == totalCount }

    private var groupedRows: [String: [SeasonalRow]] {
        Dictionary(grouping: displayedRows, by: \.category)
    }
    private var sortedCategories: [String] {
        var seen = Set<String>()
        return displayedRows.map(\.category).filter { seen.insert($0).inserted }
    }
    private var existingCategories: [String] {
        var seen = Set<String>()
        return allRows.map(\.category).filter { seen.insert($0).inserted }
    }
    private var historyEntries: [SeasonHistoryEntry] { service.history() }

    // MARK: Body

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    seasonPicker
                    progressCard
                    if isAllDone { allDoneBanner }
                    checklistContent
                    if hiddenCount > 0 { showAllToggle }
                    if !historyEntries.isEmpty { historySection }
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
                        .font(AppFont.scaled(17, weight: .semibold))
                }
                .tint(.accentColor)
                .accessibilityLabel("Add item")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            SeasonalItemEditorSheet(season: selectedSeason,
                                    existingCategories: existingCategories) { title, description, category in
                service.addCustomItem(CustomSeasonalItem(
                    title: title, description: description, category: category, season: selectedSeason))
            }
        }
        .sheet(item: $editingRow) { row in
            SeasonalItemEditorSheet(season: selectedSeason,
                                    existingCategories: existingCategories,
                                    initialTitle: row.title,
                                    initialDescription: row.description,
                                    initialCategory: row.category,
                                    isEditing: true) { title, description, category in
                if let custom = row.customItem {
                    var updated = custom
                    updated.title = title
                    updated.description = description
                    updated.category = category
                    service.updateCustomItem(updated)
                } else {
                    service.setOverride(
                        SeasonalTemplateOverride(title: title, description: description, category: category),
                        forTemplateId: row.id)
                }
            }
        }
        .alert("seasonal_task_error_title", isPresented: Binding(
            get: { taskError != nil }, set: { if !$0 { taskError = nil } })
        ) {
            Button("OK", role: .cancel) { taskError = nil }
        } message: {
            Text(taskError ?? "")
        }
        .task(id: propertyService.primary?.id) {
            service.configure(propertyId: propertyService.primary?.id)
            await SeasonalNudgeScheduler.armSeasonStartNudges()
            if let pid = propertyService.primary?.id {
                await zoneService.load(propertyId: pid)
            }
        }
    }

    // MARK: - Season Picker

    private var seasonPicker: some View {
        GlassCard(padding: 10) {
            HStack(spacing: 6) {
                ForEach([Season.spring, .summer, .fall, .winter], id: \.self) { season in
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedSeason = season
                        }
                        HapticFeedback.impact(.light)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: season.icon).font(AppFont.scaled(20))
                                .foregroundStyle(selectedSeason == season ? season.color : Color.primary.opacity(0.55))
                            Text(season.displayName)
                                .font(AppFont.scaled(11, weight: selectedSeason == season ? .semibold : .regular))
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
                        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8),
                                   value: completedCount)
                    Text(verbatim: "\(totalCount > 0 ? Int(CGFloat(completedCount) / CGFloat(totalCount) * 100) : 0)%")
                        .font(AppFont.scaled(12, weight: .bold)).foregroundStyle(.primary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(completedCount) of \(totalCount) done")
                        .font(AppFont.headline).foregroundStyle(.primary)
                    Text("\(selectedSeason.displayName) maintenance checklist")
                        .font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                }
                Spacer()
            }
        }
    }

    // MARK: - All Done Banner (checkmark bloom, silent under Reduce Motion)

    private var allDoneBanner: some View {
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(AppFont.scaled(30))
                    .foregroundStyle(selectedSeason.color)
                    .scaleEffect(sealBloomed ? 1 : 0.4)
                    .opacity(sealBloomed ? 1 : 0)
                VStack(alignment: .leading, spacing: 3) {
                    Text("All done!").font(AppFont.scaled(16, weight: .bold)).foregroundStyle(.primary)
                    Text("Your \(selectedSeason.displayName) checklist is complete.")
                        .font(AppFont.scaled(13)).foregroundStyle(Color.primary.opacity(0.55))
                }
                Spacer()
            }
        }
        .overlay(RoundedRectangle(cornerRadius: AppRadius.xxl, style: .continuous)
            .strokeBorder(selectedSeason.color.opacity(0.35), lineWidth: 1))
        .onAppear {
            if reduceMotion {
                sealBloomed = true
            } else {
                withAnimation(AppMotion.emphasis) { sealBloomed = true }
            }
        }
        .onDisappear { sealBloomed = false }
    }

    // MARK: - Checklist

    private var checklistContent: some View {
        LazyVStack(spacing: 16) {
            ForEach(sortedCategories, id: \.self) { category in
                categorySection(category: category, rows: groupedRows[category] ?? [])
            }
        }
    }

    private func categorySection(category: String, rows: [SeasonalRow]) -> some View {
        let visible = rows.filter(\.isVisible)
        let done = visible.filter { service.isCompleted($0.id, season: selectedSeason) }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(LocalizedStringKey(category))
                    .textCase(.uppercase)
                    .font(AppFont.label)
                    .foregroundStyle(.secondary)
                Spacer()
                if !visible.isEmpty {
                    if done == visible.count {
                        Image(systemName: "checkmark.circle.fill")
                            .font(AppFont.scaled(12))
                            .foregroundStyle(selectedSeason.color)
                            .accessibilityHidden(true)
                    }
                    Text(verbatim: "\(done)/\(visible.count)")
                        .font(AppFont.label)
                        .foregroundStyle(done == visible.count ? selectedSeason.color : .secondary)
                }
            }
            .padding(.horizontal, AppSpacing.xs)

            GlassCard(padding: 0) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        listItemRow(row)
                        if index < rows.count - 1 {
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

    // MARK: Row

    @ViewBuilder
    private func listItemRow(_ row: SeasonalRow) -> some View {
        let done = service.isCompleted(row.id, season: selectedSeason)
        Button {
            guard row.isVisible else { return }
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                service.toggleItem(row.id, season: selectedSeason, applicableTotal: totalCount)
            }
            HapticFeedback.impact(done ? .light : .medium)
        } label: {
            rowLabel(row, done: done)
        }
        .buttonStyle(.plain)
        .opacity(row.isVisible ? (done ? 0.7 : 1.0) : 0.45)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: done)
        .contextMenu { rowMenu(row) }
    }

    private func rowLabel(_ row: SeasonalRow, done: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(AppFont.scaled(22))
                .foregroundStyle(done ? selectedSeason.color : Color.primary.opacity(0.3))
                .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: done)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.title)
                        .font(AppFont.body)
                        .foregroundStyle(done ? Color.primary.opacity(AppOpacity.disabled) : .primary)
                        .strikethrough(done, color: Color.primary.opacity(AppOpacity.disabled))
                    if row.isCustom || row.isEditedTemplate {
                        Image(systemName: "pencil.circle.fill")
                            .font(AppFont.scaled(11))
                            .foregroundStyle(selectedSeason.color.opacity(0.6))
                            .accessibilityHidden(true)
                    }
                }
                if !row.description.isEmpty {
                    Text(row.description)
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(done ? 0.25 : 0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let reason = row.hiddenReason {
                    Text(reason == .byContext ? "seasonal_badge_not_applicable" : "seasonal_badge_hidden")
                        .font(AppFont.scaled(10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, AppSpacing.xs)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(AppOpacity.subtleFill), in: Capsule())
                } else if let taskId = service.linkedTaskId(for: row.id, season: selectedSeason),
                          taskService.tasks.contains(where: { $0.id == taskId }) {
                    // Only while the linked task still EXISTS — a deleted task
                    // must take its "Task creat" chip with it (IMG_8511), and
                    // the row menu regains "Creează task" below.
                    linkedTaskChip(taskId)
                }
            }
            Spacer()
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    /// "Task creat" states the fact of creation; it upgrades to "Task
    /// finalizat" only when the id resolves to a completed task in the
    /// already-loaded TaskService — never a faked live status.
    private func linkedTaskChip(_ taskId: UUID) -> some View {
        let live = taskService.tasks.first { $0.id == taskId }
        let isDone = live?.isCompleted == true
        return HStack(spacing: 3) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "link")
                .font(AppFont.scaled(9, weight: .semibold))
            Text(isDone ? "seasonal_task_done" : "seasonal_task_created")
                .font(AppFont.scaled(10, weight: .medium))
        }
        .foregroundStyle(isDone ? Color.brandSuccess : selectedSeason.color)
        .padding(.horizontal, AppSpacing.xs)
        .padding(.vertical, 2)
        .background((isDone ? Color.brandSuccess : selectedSeason.color).opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private func rowMenu(_ row: SeasonalRow) -> some View {
        if row.hiddenReason == .byUser {
            Button {
                withAnimation(reduceMotion ? nil : AppMotion.state) { service.restoreTemplateItem(row.id) }
            } label: {
                Label("seasonal_restore", systemImage: "arrow.uturn.backward")
            }
        } else if row.isVisible {
            Button { editingRow = row } label: {
                Label("Edit", systemImage: "pencil")
            }
            // Offer creation when there is no link OR the linked task was
            // deleted (the id no longer resolves) — creating again simply
            // overwrites the stale link.
            if service.linkedTaskId(for: row.id, season: selectedSeason)
                .flatMap({ id in taskService.tasks.first { $0.id == id } }) == nil {
                Button { createTask(for: row) } label: {
                    Label("seasonal_create_task", systemImage: "checklist")
                }
            }
            if row.isEditedTemplate {
                Button {
                    service.setOverride(nil, forTemplateId: row.id)
                } label: {
                    Label("seasonal_revert_original", systemImage: "arrow.counterclockwise")
                }
            }
            if let custom = row.customItem {
                Button(role: .destructive) {
                    withAnimation(reduceMotion ? nil : AppMotion.state) { service.deleteCustomItem(custom) }
                    HapticFeedback.warning()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } else {
                Button(role: .destructive) {
                    withAnimation(reduceMotion ? nil : AppMotion.state) { service.hideTemplateItem(row.id) }
                    HapticFeedback.warning()
                } label: {
                    Label("seasonal_hide_item", systemImage: "eye.slash")
                }
            }
        }
    }

    // MARK: - Item → task bridge

    private func createTask(for row: SeasonalRow) {
        guard let propertyId = propertyService.primary?.id else { return }
        let due = AppDate.dayString(from: selectedSeason.suggestedTaskDueDate())
        let payload = NewTaskPayload(
            propertyId: propertyId,
            title: row.title,
            description: row.description.isEmpty ? nil : row.description,
            dueDate: due,
            priority: "medium",
            category: "maintenance",
            assigneeIds: [],
            assigneeNames: [])
        Task {
            do {
                let created = try await taskService.addTask(payload)
                withAnimation(reduceMotion ? nil : AppMotion.state) {
                    service.linkTask(created.id, itemId: row.id, season: selectedSeason)
                }
                HapticFeedback.success()
            } catch {
                taskError = error.localizedDescription
            }
        }
    }

    // MARK: - Show-all toggle (reversible contextual hiding)

    private var showAllToggle: some View {
        GlassCard {
            Toggle(isOn: Binding(
                get: { service.showAllChecks },
                set: { newValue in
                    withAnimation(reduceMotion ? nil : AppMotion.state) { service.showAllChecks = newValue }
                    HapticFeedback.selection()
                })
            ) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("seasonal_show_all")
                        .font(AppFont.scaled(15, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(String(format: String(localized: "seasonal_hidden_caption"), hiddenCount))
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                }
            }
            .tint(selectedSeason.color)
        }
    }

    // MARK: - History (past season-years)

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("seasonal_history_title")
                .textCase(.uppercase)
                .font(AppFont.label)
                .foregroundStyle(.secondary)
                .padding(.leading, AppSpacing.xs)

            GlassCard(padding: 0) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(historyEntries.enumerated()), id: \.element.id) { index, entry in
                        historyRow(entry)
                        if index < historyEntries.count - 1 {
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

    private func historyRow(_ entry: SeasonHistoryEntry) -> some View {
        let text: String = {
            if let total = entry.total {
                return String(format: String(localized: "seasonal_history_entry"),
                              entry.season.definiteName, entry.year, entry.done, total)
            }
            return String(format: String(localized: "seasonal_history_entry_short"),
                          entry.season.definiteName, entry.year, entry.done)
        }()
        let complete = entry.total.map { entry.done >= $0 } ?? false
        return HStack(spacing: 12) {
            Image(systemName: entry.season.icon)
                .font(AppFont.scaled(16))
                .foregroundStyle(entry.season.color)
                .frame(width: 28)
            Text(text)
                .font(AppFont.scaled(14))
                .foregroundStyle(.primary)
            Spacer()
            if complete {
                Image(systemName: "checkmark.seal.fill")
                    .font(AppFont.scaled(14))
                    .foregroundStyle(entry.season.color)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, 11)
    }
}

// MARK: - Add / Edit Sheet
//
// One editor for all three flows: new custom item, edit custom item, edit a
// template item (which saves a SeasonalTemplateOverride instead).

struct SeasonalItemEditorSheet: View {
    let season: Season
    let existingCategories: [String]
    var initialTitle = ""
    var initialDescription = ""
    var initialCategory = ""
    var isEditing = false
    /// (title, description, category) — trimmed, category defaulted.
    let onSave: (String, String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var category = ""

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
                                .font(AppFont.scaled(16))
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
                                .font(AppFont.scaled(15))
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
                                .font(AppFont.scaled(15))
                                .padding(AppSpacing.base)
                                .background(Color.primary.opacity(AppOpacity.subtleFill),
                                            in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))

                            // Quick picks
                            if !existingCategories.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(existingCategories, id: \.self) { cat in
                                            Button {
                                                withAnimation(AppMotion.state) { category = cat }
                                            } label: {
                                                Text(LocalizedStringKey(cat))
                                                    .font(AppFont.scaled(12, weight: category == cat ? .semibold : .regular))
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
                            let trimCategory = category.trimmingCharacters(in: .whitespaces)
                            // "Custom" stays the raw catalog key (displayed
                            // localized) so new items group with legacy ones.
                            onSave(trimTitle,
                                   description.trimmingCharacters(in: .whitespaces),
                                   trimCategory.isEmpty ? "Custom" : trimCategory)
                            HapticFeedback.impact(.medium)
                            dismiss()
                        } label: {
                            Text(isEditing ? "Save Changes" : "Add Item")
                                .font(AppFont.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppSpacing.lg)
                                .background(canSave ? season.color : Color.primary.opacity(0.3),
                                            in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
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
                title = initialTitle
                description = initialDescription
                category = initialCategory
            }
        }
    }
}
