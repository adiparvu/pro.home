import SwiftUI

// MARK: - All receipts
//
// The "see all" destination behind the dashboard's recent list: every
// stored receipt, grouped by month, each row opening the existing
// ReceiptDetailView. Real data only — months appear only when they
// contain receipts.

struct ReceiptListView: View {
    @Environment(ReceiptService.self) private var receiptService
    @Environment(PropertyService.self) private var propertyService
    @Environment(AppSettings.self) private var appSettings

    @State private var searchText = ""
    @State private var selectedReceipt: Receipt? = nil

    private var filtered: [Receipt] {
        receiptService.receipts.filter {
            searchText.isEmpty || $0.storeName.matchesSearch(searchText)
        }
    }

    /// Month key → receipts, newest month first, receipts newest first.
    private var byMonth: [(key: String, receipts: [Receipt])] {
        let grouped = Dictionary(grouping: filtered) { String($0.date.prefix(7)) }
        return grouped.keys.sorted(by: >).map { key in
            (key, grouped[key]!.sorted { $0.date > $1.date })
        }
    }

    var body: some View {
        Group {
            if receiptService.receipts.isEmpty {
                EmptyStateView(icon: "receipt", title: "expense_month_empty")
            } else if filtered.isEmpty {
                EmptyStateView(icon: "magnifyingglass", title: "No results")
            } else {
                list
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle(String(localized: "receipt_list_title"))
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: Text("Search…"))
        .sheet(item: $selectedReceipt) { receipt in
            ReceiptDetailView(receipt: receipt)
                .environment(receiptService)
                .environment(propertyService)
        }
    }

    private var list: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 20) {
                ForEach(byMonth, id: \.key) { month in
                    monthSection(month.key, receipts: month.receipts)
                }
                Spacer(minLength: 110)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.lg)
        }
    }

    private func monthSection(_ key: String, receipts: [Receipt]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(receiptService.monthDisplayName(key))
                    .font(AppFont.label)
                    .foregroundStyle(.secondary)
                Spacer()
                let total = receipts.reduce(0) { $0 + $1.total }
                Text(verbatim: CurrencyService.money(total,
                                                     code: appSettings.preferredCurrency))
                    .font(AppFont.label)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, AppSpacing.xxs)

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(receipts.enumerated()), id: \.element.id) { idx, receipt in
                        row(receipt, isLast: idx == receipts.count - 1)
                    }
                }
            }
        }
    }

    private func row(_ receipt: Receipt, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: receipt.categoryIcon)
                    .font(AppFont.headline)
                    .foregroundStyle(receipt.categoryColor)
                    .frame(width: 40, height: 40)
                    .glassRoundedRect(10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(receipt.storeName.isEmpty
                         ? String(localized: "expense_unknown_store")
                         : receipt.storeName)
                        .font(AppFont.footnote)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(receipt.formattedDate)
                        .font(AppFont.scaled(11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(verbatim: CurrencyService.money(receipt.total,
                                                     code: appSettings.preferredCurrency))
                    .font(AppFont.subheadline)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
            .padding(.horizontal, AppSpacing.base).padding(.vertical, 11)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedReceipt = receipt
                HapticFeedback.selection()
            }

            if !isLast {
                Rectangle().fill(Color.primary.opacity(0.05))
                    .frame(height: 0.5).padding(.leading, 66)
            }
        }
    }
}
