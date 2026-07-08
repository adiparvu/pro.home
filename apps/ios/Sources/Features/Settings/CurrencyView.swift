import SwiftUI

// MARK: - Currency & rates (Settings › Appearance › Currency)
//
// Currency is a financial preference, not a visual one — it earns its own
// page instead of a list buried under theme toggles. The page leads with the
// chosen currency and its live rate, proves the rates work with an inline
// converter, and states its data source honestly: BNR's official daily
// fixing first, the ECB feed as fallback, named accordingly.

struct CurrencyView: View {
    @Environment(AppSettings.self) private var appSettings
    @Environment(CurrencyService.self) private var currencyService
    @Environment(AuthService.self) private var auth

    @State private var amountText = "100"
    @State private var reversed = false
    @FocusState private var amountFocused: Bool

    private var code: String { appSettings.preferredCurrency }

    /// The converter pairs the chosen currency with RON; when RON itself is
    /// chosen, it pairs with EUR so the tool never converts a currency into
    /// itself.
    private var pairCode: String { code == "RON" ? "EUR" : code }
    private var fromCode: String { reversed ? "RON" : pairCode }
    private var toCode: String { reversed ? pairCode : "RON" }

    private var amountValue: Double {
        Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }
    private var convertedDisplay: String {
        CurrencyService.money(currencyService.convert(amountValue, from: fromCode, to: toCode),
                              code: toCode)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                PageHeader(titleKey: "currency_row_label")
                heroCard
                converterCard
                currencyList
                footer
                Spacer(minLength: 100)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .task { await currencyService.refresh() }
    }

    // MARK: - Hero (the chosen currency, live)

    private var heroCard: some View {
        VStack(spacing: 12) {
            Text(CurrencyService.symbol(for: code))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 72, height: 72)
                .glassCircle()
            VStack(spacing: 3) {
                (Text(verbatim: "\(code) — ") + Text(LocalizedStringKey(currencyName(code))))
                    .font(AppFont.headline)
                    .foregroundStyle(.primary)
                Text(currencyService.rateDisplay(for: code))
                    .font(AppFont.subheadline)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    .contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xl)
        .liquidGlass(cornerRadius: AppRadius.xl, thick: true)
        .animation(.smooth(duration: 0.3), value: code)
    }

    // MARK: - Converter (live proof the rates are real)

    private var converterCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("currency_converter")
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    TextField(String(localized: "currency_amount"), text: $amountText)
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .frame(minWidth: 60)
                        .fixedSize(horizontal: true, vertical: false)
                    Text(fromCode)
                        .font(AppFont.captionEmphasis)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                }
                .padding(.horizontal, AppSpacing.base)
                .padding(.vertical, 10)
                .glassCapsule()

                Button {
                    HapticFeedback.selection()
                    withAnimation(.snappy(duration: 0.25)) { reversed.toggle() }
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(AppFont.captionEmphasis)
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .glassCircle()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("currency_swap"))

                Text(convertedDisplay)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.brandSuccess)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .animation(.smooth(duration: 0.2), value: convertedDisplay)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(AppSpacing.lg)
            .liquidGlass(cornerRadius: AppRadius.lg)
        }
    }

    // MARK: - Currency list (every rate visible, not only the selected one)

    private var currencyList: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Currency")
            VStack(spacing: 0) {
                ForEach(CurrencyService.supported, id: \.code) { cur in
                    currencyRow(cur)
                    if cur.code != CurrencyService.supported.last?.code {
                        Rectangle().fill(Color.primary.opacity(0.05))
                            .frame(height: 0.5).padding(.leading, 68)
                    }
                }
            }
            .liquidGlass(cornerRadius: AppRadius.lg)
        }
    }

    private func currencyRow(_ cur: (code: String, name: String, symbol: String)) -> some View {
        let isSelected = code == cur.code
        return Button {
            HapticFeedback.selection()
            withAnimation(.spring(response: 0.3)) {
                appSettings.preferredCurrency = cur.code
            }
            if let uid = auth.session?.user.id {
                appSettings.syncToProfile(userId: uid)
            }
        } label: {
            HStack(spacing: 14) {
                Text(cur.symbol)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(AppOpacity.mediumText))
                    .frame(width: 40, height: 40)
                    .glassCircle()

                VStack(alignment: .leading, spacing: 2) {
                    (Text(verbatim: "\(cur.code) — ") + Text(LocalizedStringKey(cur.name)))
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                    Text(currencyService.rateDisplay(for: cur.code))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.4))
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.tint)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Footer (honest source + honest refresh)

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: "building.columns")
                    .font(.system(size: 10))
                Text(verbatim: "\(currencyService.sourceDisplay) · "
                     + String(format: String(localized: "currency_updated"), currencyService.lastUpdatedDisplay))
                    .font(.system(size: 11))
            }
            .foregroundStyle(Color.primary.opacity(0.3))

            Button {
                Task { await currencyService.refreshNow() }
            } label: {
                HStack(spacing: 6) {
                    if currencyService.isLoading {
                        ProgressView().scaleEffect(0.6)
                    } else {
                        Image(systemName: "arrow.clockwise").font(AppFont.caption)
                    }
                    Text("Refresh rates now").font(AppFont.caption)
                }
                .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .disabled(currencyService.isLoading)

            Text("currency_impact_note")
                .font(.system(size: 11))
                .foregroundStyle(Color.primary.opacity(0.3))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, AppSpacing.xxs)
    }

    // MARK: - Helpers

    private func currencyName(_ code: String) -> String {
        CurrencyService.supported.first { $0.code == code }?.name ?? code
    }

    private func sectionLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(AppFont.label)
            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
            .padding(.leading, AppSpacing.xxs)
    }
}
