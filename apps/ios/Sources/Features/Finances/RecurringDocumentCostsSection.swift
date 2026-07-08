import SwiftUI

// MARK: - Recurring costs derived from documents (Document Intelligence D5)
//
// A document that carries a `value` and a monthly/quarterly/yearly `recurrence`
// (an insurance premium, a subscription, a service contract) is an ongoing
// household cost. This section surfaces those in the Finances view as READ-ONLY,
// clearly-labelled derived line items — never real transactions.
//
// Honesty rules that shape this design:
//  - Nothing here is persisted. The items are computed at read time from the
//    already-loaded documents; there is no write into `financial_records`.
//  - They are shown in their own labelled section with their own subtotal, and
//    are deliberately NOT folded into the month's expense KPI: a user may also
//    have logged the actual payment as a transaction, and silently merging the
//    two would double-count. The caption states plainly what these are.
//  - Every value is normalised to a monthly equivalent (quarterly ÷ 3,
//    yearly ÷ 12) and converted to the household's preferred currency.

/// One recurring cost derived from a document, normalised to a monthly figure
/// in the preferred currency.
struct RecurringDocCostItem: Identifiable {
    let doc: DocumentModel
    let monthlyAmount: Double     // preferred currency, per month
    let recurrence: String        // monthly / quarterly / yearly

    var id: UUID { doc.id }
}

struct RecurringDocumentCostsSection: View {
    let items: [RecurringDocCostItem]
    /// Formats an amount in the preferred currency (FinancesView.fmt).
    let format: (Double) -> String

    @Environment(DocumentService.self) private var documentService

    private var monthlyTotal: Double { items.reduce(0) { $0 + $1.monthlyAmount } }

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(AppFont.scaled(13, weight: .semibold)).foregroundStyle(.blue)
                    Text("doc_cost_section_title")
                        .font(AppFont.captionStrong).textCase(.uppercase).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.leading, AppSpacing.sm)

                GlassCard {
                    VStack(spacing: 0) {
                        Text("doc_cost_caption")
                            .font(AppFont.scaled(11))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.bottom, AppSpacing.sm)

                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                            if idx > 0 { divider }
                            row(item)
                        }

                        divider
                        HStack {
                            Text("doc_cost_monthly_total")
                                .font(AppFont.footnoteEmphasis).foregroundStyle(.primary)
                            Spacer()
                            Text(format(monthlyTotal))
                                .font(AppFont.subheadline.weight(.semibold))
                                .foregroundStyle(.blue)
                        }
                        .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
                    }
                }
            }
        }
    }

    private func row(_ item: RecurringDocCostItem) -> some View {
        NavigationLink {
            DocumentDetailView(doc: item.doc).environment(documentService)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.doc.categoryIcon).font(AppFont.scaled(17))
                    .foregroundStyle(documentCategoryColor(item.doc.category)).frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.doc.name).font(AppFont.scaled(14)).foregroundStyle(.primary).lineLimit(1)
                    Text(DocRecurrence.label(item.recurrence))
                        .font(AppFont.scaled(11)).foregroundStyle(Color.primary.opacity(0.4))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(format(item.monthlyAmount))
                        .font(AppFont.subheadline).foregroundStyle(.primary)
                    Text("doc_cost_per_month")
                        .font(AppFont.scaled(10)).foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                }
                Image(systemName: "chevron.right").font(AppFont.scaled(11))
                    .foregroundStyle(Color.primary.opacity(0.25))
            }
            .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 46)
    }
}
