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

// MARK: - Unified expense-category display
//
// The finances tab aggregates TWO ledgers: manual financial records
// ("groceries", "utilities", … — AddFinancialView's vocabulary) and scanned
// receipts ("food", "cleaning", … — ReceiptCategory's vocabulary). Receipt
// keys that name the same concept as a financial key fold into it, the
// receipt-native rest localize through their own `expense_cat_*` entries,
// and everything else goes through the capitalized catalog key the
// transaction rows already display ("groceries" → "Groceries" → "Alimente").

enum AnalyticsCategoryDisplay {
    /// Receipt-vocabulary keys folded into the financial vocabulary.
    private static let folds: [String: String] = [
        "food":   "groceries",
        "health": "healthcare",
    ]

    /// Receipt-native keys and their existing catalog entries.
    private static let receiptKeys: [String: String.LocalizationValue] = [
        "cleaning":    "expense_cat_cleaning",
        "bathroom":    "expense_cat_bathroom",
        "garden":      "expense_cat_garden",
        "diy":         "expense_cat_diy",
        "electronics": "expense_cat_electronics",
        "clothing":    "expense_cat_clothing",
    ]

    /// Canonical lowercase key for any stored category value (either ledger).
    static func normalize(_ raw: String) -> String {
        let key = raw.isEmpty ? "other" : raw.lowercased()
        return folds[key] ?? key
    }

    /// Localized display name for a canonical key.
    static func label(_ key: String) -> String {
        if let receiptKey = receiptKeys[key] { return String(localized: receiptKey) }
        return String(localized: String.LocalizationValue(key.capitalized))
    }
}

// MARK: - Category stat helper

struct CategoryStat: Identifiable {
    /// Canonical category keys aggregated into this slice — several for the
    /// "other categories" remainder bucket, exactly one otherwise.
    let keys: [String]
    /// Localized display name.
    let name: String
    let amount: Double
    /// Share of the month's total expenses, 0…1.
    let share: Double
    let color: Color

    var id: String { keys.joined(separator: "+") }

    /// Slice palette assigned by rank. The old mapping hashed the name
    /// (`name.hashValue % palette.count`), which reshuffled every launch
    /// (SipHash is seed-randomized) and let two categories collide on the
    /// same color; rank order is stable and collision-free.
    static let palette: [Color] = [
        .brandPrimaryBlue, .brandWarning, .brandSuccess,
        .brandPurple, .brandSkyBlue, .brandDanger,
    ]
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

                // The month-over-month delta, only when the previous month can
                // back it. The old fallback rendered the label here, so every
                // card without a trend printed its own title twice.
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
                    // Reserve the line so the three cards keep equal height.
                    Color.clear.frame(height: 12)
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
