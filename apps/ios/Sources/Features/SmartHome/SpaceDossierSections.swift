import SwiftUI

// MARK: - Space dossier (Estate OS E3) — the zone's own history
//
// Everything the household already recorded ABOUT this space, gathered on
// its page: journal photos (id-linked via zone_id), paint colors (the
// app-wide name match — roomName is free text by design), expenses tagged
// to the space (`"zone:<uuid>"` in FinancialRecord.tags — the exact
// convention the appliance service book already uses, so no migration),
// open maintenance tasks and documents whose free text mentions the space
// (the SpaceCardModel name link in its "contains" form — tasks and
// documents carry the space only inside typed text), and a header card of
// REAL numbers (mapped elements + average health, matched open tasks,
// tagged expense total). Every section renders ONLY with real content; the
// expense section carries an honest caption that it lists tagged expenses,
// not a guessed total; a stat with nothing real behind it simply isn't
// drawn — and with no stats at all there is no card.
//
// `SpaceDossierModel` is the one pure filter authority — the page and any
// future surface (cards, search) read the same functions and can't drift.

@MainActor
enum SpaceDossierModel {
    static func journalEntries(for zone: PropertyZone,
                               in service: PhotoJournalService) -> [PhotoJournalEntry] {
        service.entries.filter { $0.zoneId == zone.id }
    }

    static func paints(for zone: PropertyZone,
                       in service: PaintColorService) -> [PaintColor] {
        service.colors.filter {
            $0.roomName.trimmingCharacters(in: .whitespacesAndNewlines)
                .compare(zone.name.trimmingCharacters(in: .whitespacesAndNewlines),
                         options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    static func zoneTag(_ zone: PropertyZone) -> String { "zone:\(zone.id.uuidString)" }

    static func records(for zone: PropertyZone,
                        in service: FinancialService) -> [FinancialRecord] {
        let tag = zoneTag(zone)
        return service.records.filter { $0.tags.contains(tag) }
    }

    // MARK: World → space, by free text
    //
    // The app-wide name link (SpaceCardModel's trimmed, case- and
    // diacritic-insensitive comparison) in its "mentions" form: tasks and
    // documents carry the space only inside typed text, so the link is
    // containment of the zone's name rather than whole-field equality.
    // Single-character names are excluded — one letter contained anywhere
    // would claim the whole world, the opposite of an honest link.

    static func mentions(_ text: String?, zoneName: String) -> Bool {
        guard let text, !text.isEmpty else { return false }
        return text.range(of: zoneName,
                          options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// The trimmed zone name when it is substantial enough to be a
    /// free-text link — nil otherwise (empty / single character).
    private static func linkableName(of zone: PropertyZone) -> String? {
        let name = zone.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.count >= 2 ? name : nil
    }

    /// Open maintenance tasks (pending / in progress / overdue) whose title
    /// or notes mention this space — soonest due first, undated last, so
    /// the five visible rows are the five that matter.
    static func openTasks(for zone: PropertyZone,
                          in service: TaskService) -> [MaintenanceTask] {
        guard let name = linkableName(of: zone) else { return [] }
        return service.tasks
            .filter { task in
                !task.isCompleted && task.status != "cancelled"
                    && (mentions(task.title, zoneName: name)
                        || mentions(task.notes, zoneName: name))
            }
            .sorted { a, b in
                switch (a.dueDate.flatMap(MaintenanceTask.parseDate),
                        b.dueDate.flatMap(MaintenanceTask.parseDate)) {
                case let (x?, y?): x < y
                case (.some, nil): true
                case (nil, .some): false
                default: a.title.localizedCompare(b.title) == .orderedAscending
                }
            }
    }

    /// Documents whose name mentions this space — the same free-text link.
    static func documents(for zone: PropertyZone,
                          in service: DocumentService) -> [DocumentModel] {
        guard let name = linkableName(of: zone) else { return [] }
        return service.documents.filter { mentions($0.name, zoneName: name) }
    }
}

/// One real number on the dossier's header card — a formatted value, its
/// label's localization key, and an optional semantic tint.
private struct DossierStat: Identifiable {
    let value: String
    let label: String
    let tint: Color?
    var id: String { label }
}

// MARK: - The page sections

struct SpaceDossierSections: View {
    let zone: PropertyZone

    @Environment(PhotoJournalService.self) private var photoJournalService
    @Environment(PaintColorService.self) private var paintColorService
    @Environment(FinancialService.self) private var financialService
    // App-injected at the MainTabView root, like every service above —
    // the dossier reads the world without touching its call site.
    @Environment(TaskService.self) private var taskService
    @Environment(DocumentService.self) private var documentService
    @Environment(PropertyElementService.self) private var elementService
    @Environment(AppRouter.self) private var router

    @State private var showAddExpense = false

    var body: some View {
        let entries = SpaceDossierModel.journalEntries(for: zone, in: photoJournalService)
        let paints = SpaceDossierModel.paints(for: zone, in: paintColorService)
        let records = SpaceDossierModel.records(for: zone, in: financialService)
        let tasks = SpaceDossierModel.openTasks(for: zone, in: taskService)
        let documents = SpaceDossierModel.documents(for: zone, in: documentService)
        let stats = dossierStats(elements: elementService.elements(inZone: zone.id),
                                 openTaskCount: tasks.count,
                                 records: records)

        Group {
            if !stats.isEmpty {
                statsCard(stats)
            }
            if !entries.isEmpty {
                journalSection(Array(entries.prefix(6)), total: entries.count)
            }
            if !paints.isEmpty {
                paintsSection(paints)
            }
            if !tasks.isEmpty {
                tasksSection(Array(tasks.prefix(5)), total: tasks.count)
            }
            if !documents.isEmpty {
                documentsSection(Array(documents.prefix(5)), total: documents.count)
            }
            expensesSection(Array(records.prefix(5)))
        }
        .sheet(isPresented: $showAddExpense) {
            AddFinancialView(presetTags: [SpaceDossierModel.zoneTag(zone)]) {
                await financialService.load()
            }
        }
    }

    // MARK: Stats header — a compact row of REAL numbers only

    /// The header card's stats, each present only when its number is real:
    /// mapped elements (id-linked via zone_id) with their average health,
    /// open tasks mentioning the space, and the tagged-expense total (the
    /// same records the expense section lists — one source, no drift).
    private func dossierStats(elements: [PropertyElement],
                              openTaskCount: Int,
                              records: [FinancialRecord]) -> [DossierStat] {
        var stats: [DossierStat] = []
        if !elements.isEmpty {
            stats.append(DossierStat(value: "\(elements.count)",
                                     label: "est_dossier_stat_elements",
                                     tint: nil))
            let average = elements.reduce(0) { $0 + $1.healthScore } / elements.count
            stats.append(DossierStat(value: "\(average)%",
                                     label: "est_dossier_stat_health",
                                     tint: healthTint(average)))
        }
        if openTaskCount > 0 {
            stats.append(DossierStat(value: "\(openTaskCount)",
                                     label: "est_dossier_stat_tasks",
                                     tint: nil))
        }
        let expenseTotal = records.lazy
            .filter { $0.type != "income" }
            .reduce(0.0) { $0 + $1.amount }
        if expenseTotal > 0 {
            stats.append(DossierStat(value: financialService.moneyDisplay(expenseTotal),
                                     label: "est_dossier_stat_expenses",
                                     tint: nil))
        }
        return stats
    }

    /// PropertyZone.healthColor's tiers, spoken in design tokens.
    private func healthTint(_ score: Int) -> Color {
        switch score {
        case 80...:   .brandSuccess
        case 50..<80: .brandWarning
        default:      .brandDanger
        }
    }

    private func statsCard(_ stats: [DossierStat]) -> some View {
        HStack(spacing: AppSpacing.md) {
            ForEach(stats) { stat in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: stat.value)
                        .font(AppFont.scaled(17, weight: .semibold))
                        .foregroundStyle(stat.tint ?? Color.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(LocalizedStringKey(stat.label))
                        .font(AppFont.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
        .liquidGlass(cornerRadius: AppRadius.lg)
        .accessibilityElement(children: .combine)
    }

    // MARK: Journal — photo strip

    private func journalSection(_ entries: [PhotoJournalEntry], total: Int) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                dossierLabel("est_dossier_journal")
                Spacer()
                if total > entries.count {
                    Button {
                        HapticFeedback.impact(.light)
                        router.navigate(to: .photoJournal)
                    } label: {
                        Text("View all")
                            .font(AppFont.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.sm) {
                    ForEach(entries) { entry in
                        StorageImage(source: entry.photoUrl, targetSize: 160) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFill()
                            } else {
                                Color.subtleFill
                            }
                        }
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                .strokeBorder(Color.hairline, lineWidth: 1)
                        }
                        .accessibilityLabel(Text(verbatim: entry.title))
                    }
                }
                .padding(.horizontal, AppSpacing.xxs)
            }
        }
    }

    // MARK: Paints — chips with the real swatch

    private func paintsSection(_ paints: [PaintColor]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            dossierLabel("est_dossier_paints")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.sm) {
                    ForEach(paints) { paint in
                        HStack(spacing: AppSpacing.xs) {
                            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                                .fill(paint.hexColor.flatMap { Color(hex: $0) } ?? Color.subtleFill)
                                .frame(width: 22, height: 22)
                                .overlay {
                                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                                        .strokeBorder(Color.hairline, lineWidth: 1)
                                }
                            VStack(alignment: .leading, spacing: 0) {
                                Text(verbatim: paint.colorName)
                                    .font(AppFont.scaled(12, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if let code = paint.code, !code.isEmpty {
                                    Text(verbatim: code)
                                        .font(AppFont.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding(.horizontal, AppSpacing.base)
                        .padding(.vertical, AppSpacing.sm)
                        .liquidGlass(cornerRadius: AppRadius.md)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, AppSpacing.xxs)
            }
        }
    }

    // MARK: Open tasks — mentioning this space, soonest first

    private func tasksSection(_ tasks: [MaintenanceTask], total: Int) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            dossierLabel("est_dossier_tasks")
            VStack(spacing: AppSpacing.sm) {
                ForEach(tasks) { task in
                    HStack(spacing: AppSpacing.md) {
                        Image(systemName: taskGlyph(task))
                            .font(AppFont.headline)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(taskColor(task))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: task.title)
                                .font(AppFont.scaled(14, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            // Only a REAL due date earns a subline — never
                            // the "No date" placeholder.
                            if task.dueDate != nil {
                                Text(verbatim: task.dueDateDisplay)
                                    .font(AppFont.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: AppSpacing.xs)
                    }
                    .padding(.horizontal, AppSpacing.base)
                    .padding(.vertical, AppSpacing.md)
                    .spaceGlassRow()
                    .accessibilityElement(children: .combine)
                }
            }
            if total > tasks.count {
                Text("est_dossier_more \(total - tasks.count)")
                    .font(AppFont.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Status glyph for an OPEN task (completed/cancelled never reach the
    /// dossier): overdue shouts, in-progress works, pending waits.
    private func taskGlyph(_ task: MaintenanceTask) -> String {
        if task.isOverdue || task.status == "overdue" { return "exclamationmark.circle.fill" }
        return task.status == "in_progress" ? "hammer.circle.fill" : "circle.dashed"
    }

    /// TaskDetailView's status colors, restricted to the open states.
    private func taskColor(_ task: MaintenanceTask) -> Color {
        (task.isOverdue || task.status == "overdue") ? .brandDanger : .brandPurple
    }

    // MARK: Documents — named after this space

    private func documentsSection(_ documents: [DocumentModel], total: Int) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            dossierLabel("est_dossier_docs")
            VStack(spacing: AppSpacing.sm) {
                ForEach(documents) { doc in
                    HStack(spacing: AppSpacing.md) {
                        Image(systemName: doc.categoryIcon)
                            .font(AppFont.headline)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                        Text(verbatim: doc.name)
                            .font(AppFont.scaled(14, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: AppSpacing.xs)
                        if let expires = doc.expiresDisplay {
                            Text(verbatim: expires)
                                .font(AppFont.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .padding(.horizontal, AppSpacing.base)
                    .padding(.vertical, AppSpacing.md)
                    .spaceGlassRow()
                    .accessibilityElement(children: .combine)
                }
            }
            if total > documents.count {
                Text("est_dossier_more \(total - documents.count)")
                    .font(AppFont.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Expenses — tagged to this space, honest caption + real writer

    private func expensesSection(_ records: [FinancialRecord]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                dossierLabel("est_dossier_expenses")
                Spacer()
                Button {
                    HapticFeedback.impact(.light)
                    showAddExpense = true
                } label: {
                    Image(systemName: "plus")
                        .font(AppFont.captionEmphasis)
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .glassCircle()
                .accessibilityLabel(Text("est_dossier_add_expense"))
            }
            if records.isEmpty {
                Text("est_dossier_no_expenses")
                    .font(AppFont.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, AppSpacing.xs)
            } else {
                VStack(spacing: AppSpacing.sm) {
                    ForEach(records) { record in
                        HStack(spacing: AppSpacing.md) {
                            Image(systemName: record.type == "income"
                                  ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                                .font(AppFont.headline)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(record.type == "income"
                                                 ? Color.brandSuccess : Color.brandWarning)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: record.title)
                                    .font(AppFont.scaled(14, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(verbatim: record.dateFormatted)
                                    .font(AppFont.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: AppSpacing.xs)
                            Text(verbatim: financialService.moneyDisplay(record.amount))
                                .font(AppFont.scaled(14, weight: .semibold))
                                .foregroundStyle(.primary)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, AppSpacing.base)
                        .padding(.vertical, AppSpacing.md)
                        .spaceGlassRow()
                        .accessibilityElement(children: .combine)
                    }
                }
                Text("est_dossier_expenses_caption")
                    .font(AppFont.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func dossierLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(AppFont.label)
            .foregroundStyle(.secondary)
    }
}
