import Foundation

// MARK: - Total Cost of Ownership ("Cost real proprietate")
//
// The honest, all-time cost of owning the home: every expense the household
// has actually recorded, plus the equipment it has bought. No estimates, no
// national averages — only money that was really logged. The per-month and
// per-year figures are averaged over the observed span (first recorded expense
// to today), so a short history reads as a short history, never a fake yearly.

struct PropertyTCO {
    /// Sum of all recorded expenses, in the preferred currency.
    let lifetimeSpend: Double
    /// Expense categories, largest first, with each one's share of the spend.
    let byCategory: [Category]
    /// Earliest recorded expense — the anchor for the averages.
    let firstDate: Date?
    /// Whole months between `firstDate` and now (min 1), for the averages.
    let monthsObserved: Int
    /// Equipment purchases (appliance prices) — capital, shown separately so
    /// running costs and one-off buys never blur together.
    let capitalItems: [CapitalItem]
    let capitalTotal: Double

    struct Category: Identifiable, Hashable {
        let category: String
        let amount: Double
        let share: Double      // 0…1 of lifetimeSpend
        var id: String { category }
    }

    struct CapitalItem: Identifiable, Hashable {
        let id: UUID
        let name: String
        let amount: Double
    }

    var perMonth: Double { monthsObserved > 0 ? lifetimeSpend / Double(monthsObserved) : 0 }
    var perYear: Double { perMonth * 12 }
    var grandTotal: Double { lifetimeSpend + capitalTotal }
    var hasData: Bool { lifetimeSpend > 0 || capitalTotal > 0 }
}

enum PropertyTCOBuilder {
    /// Pure builder: `convert(amount, currency)` folds every figure into the
    /// preferred currency (the caller owns the CurrencyService). Passing an
    /// identity closure makes this trivially unit-testable.
    static func build(records: [FinancialRecord],
                      appliances: [Appliance],
                      convert: (Double, String) -> Double) -> PropertyTCO {
        let expenses = records.filter { $0.type == "expense" }

        var totals: [String: Double] = [:]
        var lifetime = 0.0
        var earliest: Date?
        for r in expenses {
            let v = convert(r.amount, r.currency)
            lifetime += v
            totals[r.category.lowercased(), default: 0] += v
            if let d = AppDate.day(from: r.date) {
                if earliest == nil || d < earliest! { earliest = d }
            }
        }

        let byCategory = totals.sorted { $0.value > $1.value }.map {
            PropertyTCO.Category(category: $0.key, amount: $0.value,
                                 share: lifetime > 0 ? $0.value / lifetime : 0)
        }

        let months: Int
        if let earliest {
            let comps = Calendar.current.dateComponents([.month], from: earliest, to: Date())
            months = max(1, (comps.month ?? 0) + 1)
        } else {
            months = 1
        }

        let capital = appliances.compactMap { a -> PropertyTCO.CapitalItem? in
            guard let price = a.purchasePrice, price > 0 else { return nil }
            return PropertyTCO.CapitalItem(id: a.id, name: a.name, amount: price)
        }.sorted { $0.amount > $1.amount }
        let capitalTotal = capital.reduce(0) { $0 + $1.amount }

        return PropertyTCO(lifetimeSpend: lifetime, byCategory: byCategory,
                           firstDate: earliest, monthsObserved: months,
                           capitalItems: capital, capitalTotal: capitalTotal)
    }
}
