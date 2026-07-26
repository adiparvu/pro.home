import SwiftUI

// MARK: - Net worth ("Avere netă gospodărie")
//
// A manually tracked asset or liability the household owns or owes — a bank
// balance, a car, an investment, a mortgage, a loan. These combine with the
// figures PRVIO already knows (the property's market value, the shared savings
// pot, the mortgage balance) into one honest net-worth number. Honesty law:
// every line is a real, entered figure — nothing is estimated or invented.

struct NetWorthAccount: Identifiable, Codable, Hashable {
    let id: UUID
    let propertyId: UUID
    var name: String
    var category: String          // "asset" | "liability"
    var kind: String              // token (see NetWorthKind)
    var balance: Double
    var currency: String
    var icon: String?
    var notes: String?
    var sharedMemberIds: [String]
    var createdBy: UUID?
    let createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, category, kind, balance, currency, icon, notes
        case propertyId      = "property_id"
        case sharedMemberIds = "shared_member_ids"
        case createdBy        = "created_by"
        case createdAt        = "created_at"
        case updatedAt        = "updated_at"
    }

    var isAsset: Bool { category == "asset" }
    var iconName: String { icon?.isEmpty == false ? icon! : NetWorthKind(rawValue: kind)?.icon ?? "banknote.fill" }
    var tint: Color { isAsset ? .brandSuccess : .brandDanger }
}

/// The kinds a manual account can be — each with a default icon and the side
/// of the ledger it belongs to. The picker offers assets and liabilities
/// separately, so the category is derived from the chosen kind.
enum NetWorthKind: String, CaseIterable, Identifiable {
    // Assets
    case cash, bank, investment, vehicle, valuables, otherAsset
    // Liabilities
    case mortgage, loan, credit, otherLiability

    var id: String { rawValue }

    var isAsset: Bool {
        switch self {
        case .cash, .bank, .investment, .vehicle, .valuables, .otherAsset: return true
        case .mortgage, .loan, .credit, .otherLiability: return false
        }
    }

    var icon: String {
        switch self {
        case .cash:           return "banknote.fill"
        case .bank:           return "building.columns.fill"
        case .investment:     return "chart.line.uptrend.xyaxis"
        case .vehicle:        return "car.fill"
        case .valuables:      return "diamond.fill"
        case .otherAsset:     return "plus.circle.fill"
        case .mortgage:       return "house.fill"
        case .loan:           return "creditcard.fill"
        case .credit:         return "creditcard.and.123"
        case .otherLiability: return "minus.circle.fill"
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .cash:           return "nw_kind_cash"
        case .bank:           return "nw_kind_bank"
        case .investment:     return "nw_kind_investment"
        case .vehicle:        return "nw_kind_vehicle"
        case .valuables:      return "nw_kind_valuables"
        case .otherAsset:     return "nw_kind_other_asset"
        case .mortgage:       return "nw_kind_mortgage"
        case .loan:           return "nw_kind_loan"
        case .credit:         return "nw_kind_credit"
        case .otherLiability: return "nw_kind_other_liability"
        }
    }

    static var assetKinds: [NetWorthKind] { allCases.filter(\.isAsset) }
    static var liabilityKinds: [NetWorthKind] { allCases.filter { !$0.isAsset } }
}

// MARK: - Composition (pure)

/// One row in the net-worth breakdown — either a manual account or a figure
/// PRVIO already tracks (`isDerived`). Amounts here are ALWAYS in the
/// household's preferred currency (the composer converts before building).
struct NetWorthLine: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let amount: Double     // positive magnitude, in preferred currency
    let isAsset: Bool
    let isDerived: Bool    // true = auto (not editable here)
    let account: NetWorthAccount?
}

/// The whole picture: total assets, total liabilities, the net, and the lines
/// that produced them. Built by `NetWorthComposition.build` — a pure function,
/// so it is trivially testable and never touches the network.
struct NetWorthSnapshot {
    let assets: Double
    let liabilities: Double
    let lines: [NetWorthLine]

    var net: Double { assets - liabilities }
    var hasData: Bool { !lines.isEmpty }

    /// Assets' share of the (assets + liabilities) bar — powers the split
    /// visual. 1 when there are no liabilities, 0.5 as a neutral default.
    var assetFraction: Double {
        let denom = assets + liabilities
        return denom > 0 ? assets / denom : 0.5
    }

    var assetLines: [NetWorthLine] { lines.filter { $0.isAsset } }
    var liabilityLines: [NetWorthLine] { lines.filter { !$0.isAsset } }
}

// MARK: - Mortgage bridge (device-local @AppStorage → derived liability)

/// The mortgage lives in `MortgageView`'s @AppStorage. This mirrors its
/// remaining-balance amortization so net worth can fold it in as a derived
/// liability without depending on the view. Entered in the household currency,
/// so the composer treats it as already in the preferred currency.
enum MortgageSnapshot {
    static var remainingBalance: Double {
        let d = UserDefaults.standard
        let loan = d.double(forKey: "prvio.mortgage.loanAmount")
        guard loan > 0 else { return 0 }
        let rate = d.double(forKey: "prvio.mortgage.interestRate")
        let term = d.double(forKey: "prvio.mortgage.termYears")
        guard rate > 0, term > 0 else { return loan }
        let n = term * 12
        let r = rate / 100 / 12
        var paid = 0
        if let startStr = d.string(forKey: "prvio.mortgage.startDate"), !startStr.isEmpty,
           let start = ISO8601DateFormatter().date(from: startStr) {
            paid = max(0, Calendar.current.dateComponents([.month], from: start, to: Date()).month ?? 0)
        }
        guard paid > 0 else { return loan }
        let denom = pow(1 + r, n) - 1
        guard denom != 0 else { return loan }
        return loan * (pow(1 + r, n) - pow(1 + r, Double(paid))) / denom
    }
}

enum NetWorthComposition {
    /// Builds the snapshot from the manual accounts plus the derived figures.
    /// Every amount must already be converted to the preferred currency by the
    /// caller (it owns the CurrencyService); this keeps the function pure.
    static func build(accounts: [NetWorthLine], derived: [NetWorthLine]) -> NetWorthSnapshot {
        let lines = derived + accounts
        let assets = lines.filter { $0.isAsset }.reduce(0) { $0 + $1.amount }
        let liabilities = lines.filter { !$0.isAsset }.reduce(0) { $0 + $1.amount }
        return NetWorthSnapshot(assets: assets, liabilities: liabilities, lines: lines)
    }
}
