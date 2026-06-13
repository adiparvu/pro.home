import SwiftUI

struct AppearanceView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var currencyService: CurrencyService
    @EnvironmentObject private var auth: AuthService

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                themeSection
                currencySection
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.large)
        .task { await currencyService.refresh() }
    }

    // MARK: - Theme

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Theme")

            VStack(spacing: 12) {
                ForEach(AppSettings.themes, id: \.code) { theme in
                    ThemeOptionRow(
                        icon: theme.icon,
                        title: theme.label,
                        isSelected: appSettings.theme == theme.code
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            appSettings.theme = theme.code
                        }
                        if let uid = auth.session?.user.id {
                            appSettings.syncToProfile(userId: uid)
                        }
                    }
                }
            }
            .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.primary.opacity(0.07), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Currency

    private var currencySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Currency")

            VStack(spacing: 0) {
                ForEach(CurrencyService.supported, id: \.code) { cur in
                    let isSelected = appSettings.preferredCurrency == cur.code
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            appSettings.preferredCurrency = cur.code
                        }
                        if let uid = auth.session?.user.id {
                            appSettings.syncToProfile(userId: uid)
                        }
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSelected ? .primary.opacity(0.18) : .primary.opacity(0.07))
                                    .frame(width: 40, height: 40)
                                Text(cur.symbol)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(isSelected ? .white : .primary.opacity(0.5))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(cur.code) — \(cur.name)")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.primary)
                                if isSelected {
                                    Text(currencyService.rateDisplay(for: cur.code))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.primary.opacity(0.4))
                                        .transition(.opacity)
                                }
                            }

                            Spacer()

                            if currencyService.isLoading && isSelected {
                                ProgressView().scaleEffect(0.7).tint(.primary.opacity(0.5))
                            } else if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.blue)
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                Circle()
                                    .strokeBorder(.primary.opacity(0.2), lineWidth: 1.5)
                                    .frame(width: 20, height: 20)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)

                    if cur.code != CurrencyService.supported.last?.code {
                        Rectangle().fill(.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 68)
                    }
                }
            }
            .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.primary.opacity(0.07), lineWidth: 0.5))

            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10))
                Text("BNR rates · Updated \(currencyService.lastUpdatedDisplay)")
                    .font(.system(size: 11))
            }
            .foregroundStyle(.primary.opacity(0.3))
            .padding(.leading, 4)

            Button {
                Task { await forceFetch() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                    Text("Refresh rates now")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.blue)
                .padding(.leading, 4)
            }
            .buttonStyle(.plain)
            .disabled(currencyService.isLoading)
        }
    }

    private func forceFetch() async {
        UserDefaults.standard.removeObject(forKey: "prvhouse.bnr.ratesDate")
        await currencyService.refresh()
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.primary.opacity(0.35))
            .padding(.leading, 4)
    }
}

// MARK: - Theme Row

private struct ThemeOptionRow: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? .primary.opacity(0.18) : .primary.opacity(0.07))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isSelected ? .white : .primary.opacity(0.5))
                }

                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.blue)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Circle()
                        .strokeBorder(.primary.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

