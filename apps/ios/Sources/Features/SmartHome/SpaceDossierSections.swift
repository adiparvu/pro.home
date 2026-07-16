import SwiftUI

// MARK: - Space dossier (Estate OS E3) — the zone's own history
//
// Everything the household already recorded ABOUT this space, gathered on
// its page: journal photos (id-linked via zone_id), paint colors (the
// app-wide name match — roomName is free text by design), and expenses
// tagged to the space (`"zone:<uuid>"` in FinancialRecord.tags — the exact
// convention the appliance service book already uses, so no migration).
// Every section renders ONLY with real content; the expense section carries
// an honest caption that it lists tagged expenses, not a guessed total.
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
}

// MARK: - The page sections

struct SpaceDossierSections: View {
    let zone: PropertyZone

    @Environment(PhotoJournalService.self) private var photoJournalService
    @Environment(PaintColorService.self) private var paintColorService
    @Environment(FinancialService.self) private var financialService
    @Environment(AppRouter.self) private var router

    @State private var showAddExpense = false

    var body: some View {
        let entries = SpaceDossierModel.journalEntries(for: zone, in: photoJournalService)
        let paints = SpaceDossierModel.paints(for: zone, in: paintColorService)
        let records = SpaceDossierModel.records(for: zone, in: financialService)

        Group {
            if !entries.isEmpty {
                journalSection(Array(entries.prefix(6)), total: entries.count)
            }
            if !paints.isEmpty {
                paintsSection(paints)
            }
            expensesSection(Array(records.prefix(5)))
        }
        .sheet(isPresented: $showAddExpense) {
            AddFinancialView(presetTags: [SpaceDossierModel.zoneTag(zone)]) {
                await financialService.load()
            }
        }
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
            .kerning(1.1)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}
