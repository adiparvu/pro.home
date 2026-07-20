import SwiftUI
import Charts

// MARK: - Price history
//
// The module's differentiator: every scanned receipt line becomes a data
// point, so the household sees what a product actually cost, where, and
// when. Everything shown here is a stored receipt line — no interpolation,
// no estimates; without scans the pages say so honestly.

/// Identifiable wrapper so any view can present a product's history sheet.
struct PriceHistoryTarget: Identifiable {
    let name: String
    var id: String { name }
}

// MARK: - Overview page (all tracked products)

struct PriceHistoryView: View {
    @Environment(ReceiptService.self) private var receiptService
    @Environment(AppSettings.self) private var appSettings

    @State private var searchText = ""

    private var groups: [ProductPriceGroup] {
        let all = receiptService.productPriceGroups()
        guard !searchText.isEmpty else { return all }
        return all.filter { group in
            group.name.matchesSearch(searchText)
                || (group.entries.first.map {
                    CurrencyService.money($0.price, code: appSettings.preferredCurrency)
                } ?? "").matchesSearch(searchText)
        }
    }

    var body: some View {
        Group {
            if receiptService.receiptItems.isEmpty {
                emptyState
            } else if groups.isEmpty {
                EmptyStateView(icon: "magnifyingglass", title: "No results")
            } else {
                list
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle(String(localized: "price_history_title"))
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText,
                    prompt: Text("Search…"))
    }

    private var list: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                GlassCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(groups.enumerated()), id: \.element.id) { idx, group in
                            NavigationLink {
                                ProductPriceHistoryView(productName: group.name)
                            } label: {
                                productRow(group, isLast: idx == groups.count - 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.xl)
                Spacer(minLength: 110)
            }
            .padding(.top, AppSpacing.lg)
        }
    }

    private func productRow(_ group: ProductPriceGroup, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(AppFont.captionEmphasis)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .mediaGlass(in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(AppFont.footnote)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("price_history_purchases \(group.entries.count)")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let latest = group.entries.first {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(verbatim: CurrencyService.money(latest.price,
                                                             code: appSettings.preferredCurrency))
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                        if group.entries.count >= 2 {
                            deltaBadge(latest: latest.price, previous: group.entries[1].price)
                        }
                    }
                }

                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(11))
                    .foregroundStyle(Color.primary.opacity(0.25))
            }
            .padding(.horizontal, AppSpacing.base).padding(.vertical, 10)
            .contentShape(Rectangle())

            if !isLast {
                Rectangle().fill(Color.primary.opacity(0.05))
                    .frame(height: 0.5).padding(.leading, 62)
            }
        }
    }

    @ViewBuilder
    private func deltaBadge(latest: Double, previous: Double) -> some View {
        let delta = latest - previous
        if abs(delta) >= 0.005 {
            HStack(spacing: 2) {
                Image(systemName: delta > 0 ? "arrow.up" : "arrow.down")
                    .font(AppFont.scaled(8, weight: .bold))
                Text(verbatim: CurrencyService.money(abs(delta),
                                                     code: appSettings.preferredCurrency))
                    .font(AppFont.scaled(10, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(delta > 0 ? Color.brandDanger : Color.brandSuccess)
        }
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.base) {
            Spacer()
            EmptyStateView(icon: "chart.line.uptrend.xyaxis",
                           title: "price_history_empty_title")
            Text("price_history_empty_body")
                .font(AppFont.scaled(14))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xxl)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - One product's history

struct ProductPriceHistoryView: View {
    @Environment(ReceiptService.self) private var receiptService
    @Environment(AppSettings.self) private var appSettings

    let productName: String

    private var entries: [ProductPriceEntry] {
        receiptService.priceEntries(matching: productName)
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle(productName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                summaryCard
                if entries.count >= 2 { chartCard }
                entriesSection
                Spacer(minLength: 60)
            }
            .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.lg)
        }
    }

    // MARK: Summary (latest price + delta vs previous purchase)

    private var summaryCard: some View {
        GlassCard(padding: 18) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "price_history_latest"))
                        .font(AppFont.captionStrong)
                        .foregroundStyle(.secondary)
                        .tracking(0.8)
                    if let latest = entries.first {
                        Text(verbatim: CurrencyService.money(latest.price,
                                                             code: appSettings.preferredCurrency))
                            .font(AppFont.scaled(30, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                        Text(latest.receipt.formattedDate)
                            .font(AppFont.scaled(11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if entries.count >= 2, let latest = entries.first {
                    deltaSummary(latest: latest.price, previous: entries[1].price)
                }
            }
        }
    }

    @ViewBuilder
    private func deltaSummary(latest: Double, previous: Double) -> some View {
        let delta = latest - previous
        VStack(alignment: .trailing, spacing: 3) {
            if abs(delta) >= 0.005 {
                HStack(spacing: 4) {
                    Image(systemName: delta > 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(AppFont.scaled(12, weight: .bold))
                    Text(verbatim: CurrencyService.money(abs(delta),
                                                         code: appSettings.preferredCurrency))
                        .font(AppFont.scaled(15, weight: .semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(delta > 0 ? Color.brandDanger : Color.brandSuccess)
            } else {
                Image(systemName: "equal")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(String(localized: "price_history_vs_previous"))
                .font(AppFont.scaled(10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: Chart (≥2 real points only)

    private var chartCard: some View {
        let points = entries.sorted { $0.date < $1.date }
        return GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "price_history_title"))
                    .font(AppFont.captionStrong)
                    .foregroundStyle(.secondary)
                    .tracking(0.8)

                Chart(points) { entry in
                    LineMark(
                        x: .value("Date", entry.date),
                        y: .value("Price", entry.price)
                    )
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.monotone)
                    PointMark(
                        x: .value("Date", entry.date),
                        y: .value("Price", entry.price)
                    )
                    .foregroundStyle(Color.accentColor)
                    .symbolSize(28)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { val in
                        if let v = val.as(Double.self) {
                            AxisValueLabel {
                                Text(verbatim: CurrencyService.money(
                                    v, code: appSettings.preferredCurrency))
                                    .font(AppFont.scaled(9))
                            }
                        }
                        AxisGridLine().foregroundStyle(Color.primary.opacity(0.04))
                    }
                }
                .chartXAxis {
                    AxisMarks { val in
                        if let date = val.as(Date.self) {
                            AxisValueLabel {
                                Text(date, format: .dateTime.day().month(.abbreviated))
                                    .font(AppFont.scaled(9))
                            }
                        }
                    }
                }
                .frame(height: 130)
                .chartPlotStyle { plot in plot.background(Color.clear) }
            }
        }
    }

    // MARK: Entries (price – store – date, newest first)

    private var entriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("price_history_purchases \(entries.count)")
                .font(AppFont.captionStrong)
                .foregroundStyle(.secondary)
                .tracking(0.8)
                .padding(.leading, AppSpacing.xxs)

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.store.isEmpty
                                         ? String(localized: "expense_unknown_store")
                                         : entry.store)
                                        .font(AppFont.footnote)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(entry.receipt.formattedDate)
                                        .font(AppFont.scaled(11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(verbatim: CurrencyService.money(
                                    entry.price, code: appSettings.preferredCurrency))
                                    .font(AppFont.footnoteEmphasis)
                                    .foregroundStyle(.primary)
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, AppSpacing.base).padding(.vertical, 10)
                            if idx < entries.count - 1 {
                                Rectangle().fill(Color.primary.opacity(0.05))
                                    .frame(height: 0.5).padding(.leading, AppSpacing.base)
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.base) {
            Spacer()
            EmptyStateView(icon: "chart.line.uptrend.xyaxis",
                           title: "price_history_empty_title")
            Text("price_history_empty_body")
                .font(AppFont.scaled(14))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xxl)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Sheet wrapper (list & pantry entry points)

struct ProductPriceHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    let productName: String

    var body: some View {
        NavigationStack {
            ProductPriceHistoryView(productName: productName)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Done")) { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
        }
        .presentationDetents([.large, .medium])
        .presentationBackground(.thinMaterial)
    }
}
