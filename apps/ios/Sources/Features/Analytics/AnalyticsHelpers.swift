import SwiftUI
import Charts

// MARK: - Chart range

enum ChartRange: String, CaseIterable {
    case day = "1D", week = "1W", month = "1M"
    case threeMonths = "3M", sixMonths = "6M", year = "1Y", custom = "↔"

    var menuLabel: String {
        switch self {
        case .day:          return String(localized: "1 Day")
        case .week:         return String(localized: "1 Week")
        case .month:        return String(localized: "1 Month")
        case .threeMonths:  return String(localized: "3 Months")
        case .sixMonths:    return String(localized: "6 Months")
        case .year:         return String(localized: "1 Year")
        case .custom:       return String(localized: "Custom…")
        }
    }
}

// MARK: - Category stat helper

struct CategoryStat: Identifiable {
    let id = UUID()
    let name: String
    let amount: Double

    var color: Color {
        let palette: [Color] = [
            Color.brandPrimaryBlue,
            Color.brandWarning,
            Color.brandSuccess,
            Color(red: 0.7, green: 0.3, blue: 0.9),
            Color(red: 1.0, green: 0.75, blue: 0.1),
            Color.brandDanger
        ]
        let idx = abs(name.hashValue) % palette.count
        return palette[idx]
    }
}

// MARK: - TrendKPICard

struct TrendKPICard: View {
    let label: LocalizedStringKey
    let value: String
    let icon: String
    let trendPct: Double?
    let trendPositive: Bool
    var highlightValue: Bool = false
    var positiveValue: Bool = true

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)

                Text(value)
                    .font(AppFont.scaled(17, weight: .bold))
                    .foregroundStyle(highlightValue
                        ? (positiveValue ? Color.brandSuccess : .red)
                        : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .contentTransition(.numericText())

                if let pct = trendPct {
                    HStack(spacing: 2) {
                        Image(systemName: pct >= 0 ? "arrow.up" : "arrow.down")
                            .font(AppFont.scaled(8, weight: .bold))
                        Text(String(format: "%.0f%%", abs(pct)))
                            .font(AppFont.scaled(10, weight: .semibold))
                    }
                    .foregroundStyle(trendPositive
                        ? Color.brandSuccess
                        : .red)
                } else {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(label)
                    .font(AppFont.scaled(10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Calendar extension

extension Calendar {
    func startOfMonth(_ date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }
}
