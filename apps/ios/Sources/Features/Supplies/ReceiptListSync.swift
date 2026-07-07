import Foundation

// MARK: - ReceiptListSync
//
// Turns "what the receipt says was bought" into concrete shopping-list
// updates: items fully purchased get checked off, partially purchased items
// get their quantity decremented ("Lapte ×3" − bought 2 → "1"). Planning is
// pure and testable; `apply(_:via:)` performs the writes.
enum ReceiptListSync {

    // MARK: - Actions

    enum ListSyncAction: Identifiable {
        /// The list item is fully covered by this purchase — check it off.
        case complete(SupplyItem)
        /// Part of the listed quantity was bought — store the remainder.
        /// `purchased`/`remaining` are pre-formatted quantity strings for UI.
        case decrement(SupplyItem, newQuantityText: String, purchased: String, remaining: String)

        var listItem: SupplyItem {
            switch self {
            case .complete(let item): return item
            case .decrement(let item, _, _, _): return item
            }
        }

        var id: UUID { listItem.id }
    }

    struct SyncPlan {
        var actions: [ListSyncAction] = []
        var unmatchedReceiptItems: [ParsedItem] = []
    }

    // MARK: - Quantity text parsing

    /// Measurement dimension a quantity lives in. Counting ("3", "x2",
    /// "5 buc"), mass (kg/g) and volume (l/ml) never mix.
    enum Dimension { case count, mass, volume }

    struct Quantity {
        var value: Double
        var unit: String?       // normalized: nil/"buc", "kg", "g", "l", "ml"

        var dimension: Dimension {
            switch unit {
            case "kg", "g":  return .mass
            case "l", "ml":  return .volume
            default:         return .count
            }
        }

        /// Value in the dimension's base unit (kg for mass, l for volume).
        var baseValue: Double {
            switch unit {
            case "g":  return value / 1000
            case "ml": return value / 1000
            default:   return value
            }
        }
    }

    private static let quantityTextRegex =
        /^\s*[x×]?\s*(\d{1,5}(?:[.,]\d{1,3})?)\s*(buc|bucati|bucata|pcs|st|stuks|kg|gr|g|l|litri|lt|ml)?\.?\s*$/.ignoresCase()

    /// Parses the shopping list's free-text quantity ("3", "x3", "×3",
    /// "3 buc", "2kg", "1.5 l", "10") into a value + normalized unit.
    /// Returns nil for text that isn't a quantity ("câteva", "o plasă").
    static func parseQuantity(_ text: String?) -> Quantity? {
        guard let text, !text.isEmpty,
              let match = text.firstMatch(of: quantityTextRegex),
              let value = ReceiptIntelligence.number(from: match.1),
              value > 0 else { return nil }
        let unit: String?
        switch match.2?.lowercased() ?? "" {
        case "kg":                                   unit = "kg"
        case "g", "gr":                              unit = "g"
        case "l", "litri", "lt":                     unit = "l"
        case "ml":                                   unit = "ml"
        case "buc", "bucati", "bucata", "pcs", "st", "stuks": unit = "buc"
        default:                                     unit = nil
        }
        return Quantity(value: value, unit: unit)
    }

    /// Formats a quantity back into list text. Stored strings stay
    /// machine-parseable: dot decimals, at most one decimal ("1", "0.6 kg").
    static func formatQuantity(_ value: Double, unit: String?) -> String {
        let rounded = (value * 10).rounded() / 10
        let number: String
        if rounded == rounded.rounded() {
            number = String(format: "%.0f", rounded)
        } else {
            number = String(format: "%.1f", rounded)
        }
        if let unit, unit != "buc", !unit.isEmpty {
            return "\(number) \(unit)"
        }
        return number
    }

    // MARK: - Planning

    /// Matches receipt items against pending shopping-list items (greedy,
    /// best score first; one-to-one) and decides complete vs. decrement.
    static func plan(receiptItems: [ParsedItem], listItems: [SupplyItem]) -> SyncPlan {
        var plan = SyncPlan()
        let pending = listItems.filter { !$0.isCompleted }
        guard !receiptItems.isEmpty, !pending.isEmpty else {
            plan.unmatchedReceiptItems = receiptItems
            return plan
        }

        // Score every pair once, then assign greedily by best score.
        struct Pair { let receiptIndex: Int; let listIndex: Int; let score: Double }
        var pairs: [Pair] = []
        for (ri, receiptItem) in receiptItems.enumerated() {
            for (li, listItem) in pending.enumerated() {
                let score = max(
                    ReceiptProductLexicon.match(receiptItem.name, against: listItem.name),
                    ReceiptProductLexicon.match(receiptItem.normalizedName, against: listItem.name)
                )
                if score >= ReceiptProductLexicon.matchThreshold {
                    pairs.append(Pair(receiptIndex: ri, listIndex: li, score: score))
                }
            }
        }
        pairs.sort { $0.score > $1.score }

        var usedReceipt: Set<Int> = []
        var usedList: Set<Int> = []
        for pair in pairs {
            guard !usedReceipt.contains(pair.receiptIndex),
                  !usedList.contains(pair.listIndex) else { continue }
            usedReceipt.insert(pair.receiptIndex)
            usedList.insert(pair.listIndex)
            plan.actions.append(action(for: pending[pair.listIndex],
                                       purchased: receiptItems[pair.receiptIndex]))
        }

        plan.unmatchedReceiptItems = receiptItems.enumerated()
            .filter { !usedReceipt.contains($0.offset) }
            .map(\.element)
        return plan
    }

    /// Decides what buying `purchased` means for `listItem`. Decrement only
    /// when both quantities parse and live in the same dimension; anything
    /// ambiguous falls back to the honest, safe `.complete`.
    private static func action(for listItem: SupplyItem, purchased: ParsedItem) -> ListSyncAction {
        guard let wanted = parseQuantity(listItem.quantity) else {
            return .complete(listItem)
        }
        let bought = Quantity(value: purchased.quantity,
                              unit: purchased.unit == "buc" ? nil : purchased.unit)
        guard bought.dimension == wanted.dimension else {
            return .complete(listItem)
        }

        let remainingBase = wanted.baseValue - bought.baseValue
        if remainingBase <= 0.01 {
            return .complete(listItem)
        }

        // Express the remainder in the unit the list already used.
        let remainingInListUnit: Double
        switch wanted.unit {
        case "g":  remainingInListUnit = remainingBase * 1000
        case "ml": remainingInListUnit = remainingBase * 1000
        default:   remainingInListUnit = remainingBase
        }
        let newText = formatQuantity(remainingInListUnit, unit: wanted.unit)
        let purchasedText = formatQuantity(bought.value, unit: bought.unit)
        return .decrement(listItem,
                          newQuantityText: newText,
                          purchased: purchasedText,
                          remaining: newText)
    }

    // MARK: - Apply

    /// Executes the plan against the live shopping list.
    @MainActor
    static func apply(_ actions: [ListSyncAction], via service: SupplyService) async {
        for action in actions {
            switch action {
            case .complete(let item):
                // Re-read the latest copy; the item may have changed since planning.
                let current = service.items.first { $0.id == item.id } ?? item
                if !current.isCompleted {
                    await service.toggleComplete(current)
                }
            case .decrement(let item, let newQuantityText, _, _):
                var updated = service.items.first { $0.id == item.id } ?? item
                guard !updated.isCompleted else { continue }
                updated.quantity = newQuantityText
                await service.updateItem(updated)
            }
        }
    }
}
