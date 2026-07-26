import SwiftUI

// MARK: - Total Cost of Ownership — section + full page
//
// "Cost real proprietate": the honest lifetime cost of owning the home, built
// only from expenses the household actually recorded plus the equipment it
// bought. Per-month and per-year are averaged over the observed span, so a
// short history never fakes a full year (honesty law).

// MARK: Shared build

extension View {
    func buildTCO(records: [FinancialRecord], appliances: [Appliance],
                  preferred: String, convert: (Double, String) -> Double) -> PropertyTCO {
        PropertyTCOBuilder.build(records: records, appliances: appliances, convert: convert)
    }
}

// MARK: Section (embedded on FinancesView)

struct PropertyTCOSection: View {
    @Environment(FinancialService.self) private var financialService
    @Environment(ApplianceService.self) private var applianceService
    @Environment(CurrencyService.self) private var currencyService
    @Environment(AppSettings.self) private var appSettings

    private var preferred: String { appSettings.preferredCurrency }

    private var tco: PropertyTCO {
        buildTCO(records: financialService.records, appliances: applianceService.appliances,
                 preferred: preferred,
                 convert: { currencyService.convert($0, from: $1, to: preferred) })
    }

    var body: some View {
        let t = tco
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            NavigationLink { PropertyTCOView() } label: {
                HStack(spacing: AppSpacing.xs) {
                    Text("tco_section_title")
                        .font(AppFont.scaled(20, weight: .bold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AppFont.scaled(13, weight: .semibold))
                        .foregroundStyle(Color.secondaryTextColor)
                }
            }
            .buttonStyle(.plain)

            if t.hasData {
                NavigationLink { PropertyTCOView() } label: {
                    TCOSummaryCard(tco: t, currency: preferred)
                }
                .buttonStyle(.plain)
            } else {
                EmptyStateView(icon: "sum",
                               title: "tco_empty_title",
                               message: "tco_empty_message")
            }
        }
    }
}

// MARK: Summary card

struct TCOSummaryCard: View {
    let tco: PropertyTCO
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.base) {
            VStack(alignment: .leading, spacing: 2) {
                Text("tco_total_label")
                    .font(AppFont.scaled(12)).foregroundStyle(Color.secondaryTextColor)
                Text(verbatim: CurrencyService.money(tco.grandTotal, code: currency, whole: true))
                    .font(AppFont.scaled(30, weight: .bold))
                    .foregroundStyle(.primary)
                    .monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
            }
            HStack {
                metric("tco_per_year", tco.perYear)
                Spacer()
                metric("tco_per_month", tco.perMonth)
            }
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: AppRadius.xl)
        .accessibilityElement(children: .combine)
    }

    private func metric(_ key: LocalizedStringKey, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(key).font(AppFont.scaled(12)).foregroundStyle(Color.secondaryTextColor)
            Text(verbatim: CurrencyService.money(value, code: currency, whole: true))
                .font(AppFont.scaled(16, weight: .bold)).foregroundStyle(.primary).monospacedDigit()
        }
    }
}

// MARK: Full page

struct PropertyTCOView: View {
    @Environment(FinancialService.self) private var financialService
    @Environment(ApplianceService.self) private var applianceService
    @Environment(CurrencyService.self) private var currencyService
    @Environment(AppSettings.self) private var appSettings

    private var preferred: String { appSettings.preferredCurrency }

    private var tco: PropertyTCO {
        buildTCO(records: financialService.records, appliances: applianceService.appliances,
                 preferred: preferred,
                 convert: { currencyService.convert($0, from: $1, to: preferred) })
    }

    var body: some View {
        let t = tco
        ScrollView(showsIndicators: false) {
            VStack(spacing: AppSpacing.lg) {
                if t.hasData {
                    TCOSummaryCard(tco: t, currency: preferred)
                    if let first = t.firstDate { observedFooter(first: first, months: t.monthsObserved) }
                    if !t.byCategory.isEmpty { categoryCard(t) }
                    if !t.capitalItems.isEmpty { capitalCard(t) }
                } else {
                    EmptyStateView(icon: "sum",
                                   title: "tco_empty_title",
                                   message: "tco_empty_message")
                        .padding(.top, AppSpacing.xxl)
                }
                Spacer(minLength: 80)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.md)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("tco_section_title")
        .navigationBarTitleDisplayMode(.large)
        .task { await financialService.load() }
    }

    private func observedFooter(first: Date, months: Int) -> some View {
        Text(String(format: String(localized: "tco_observed_fmt"),
                    AppDate.monthDayYear.string(from: first), months))
            .font(AppFont.scaled(12))
            .foregroundStyle(Color.secondaryTextColor)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func categoryCard(_ t: PropertyTCO) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("tco_by_category").font(AppFont.scaled(15, weight: .semibold)).foregroundStyle(.primary)
            ForEach(t.byCategory) { c in
                let style = catStyle(c.category)
                VStack(spacing: 4) {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: style.icon)
                            .font(AppFont.scaled(14, weight: .semibold))
                            .foregroundStyle(style.color).frame(width: 24)
                        Text(LocalizedStringKey(c.category.capitalized))
                            .font(AppFont.scaled(14)).foregroundStyle(.primary).lineLimit(1)
                        Spacer()
                        Text(verbatim: CurrencyService.money(c.amount, code: preferred, whole: true))
                            .font(AppFont.scaled(14, weight: .semibold)).foregroundStyle(.primary).monospacedDigit()
                    }
                    ProgressBar(fraction: c.share, tint: style.color)
                }
            }
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: AppRadius.xl)
    }

    private func capitalCard(_ t: PropertyTCO) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text("tco_capital").font(AppFont.scaled(15, weight: .semibold)).foregroundStyle(.primary)
                Spacer()
                Text(verbatim: CurrencyService.money(t.capitalTotal, code: preferred, whole: true))
                    .font(AppFont.scaled(14, weight: .bold)).foregroundStyle(.primary).monospacedDigit()
            }
            ForEach(t.capitalItems) { item in
                HStack {
                    Image(systemName: "shippingbox.fill")
                        .font(AppFont.scaled(13, weight: .semibold))
                        .foregroundStyle(Color.accentColor).frame(width: 24)
                    Text(verbatim: item.name).font(AppFont.scaled(14)).foregroundStyle(.primary).lineLimit(1)
                    Spacer()
                    Text(verbatim: CurrencyService.money(item.amount, code: preferred, whole: true))
                        .font(AppFont.scaled(14, weight: .semibold)).foregroundStyle(.primary).monospacedDigit()
                }
            }
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: AppRadius.xl)
    }
}
