import Foundation

// MARK: - Pantry merge engine (pure, tested)
//
// Decides how a batch of scanned receipt items lands in the pantry: existing
// stock (matched by normalized name) grows, unknown products become new
// stock rows, and a unit conflict (pantry counts pieces, receipt weighs
// kilos) is SKIPPED and reported rather than guessed — stock numbers the
// household relies on must never be invented.

enum PantryMerge {

    /// A receipt item reduced to what the pantry needs.
    struct Addition: Equatable {
        var name: String
        var normalizedName: String
        var quantity: Double
        var unit: String        // receipt units: "buc", "kg", "g", "l", "ml"
    }

    struct Plan: Equatable {
        struct Increment: Equatable {
            var itemId: UUID
            var add: Double            // in the PANTRY item's unit
        }
        struct Insert: Equatable {
            var name: String
            var normalizedName: String
            var quantity: Double
            var unit: String           // coarse: "buc" | "kg" | "l"
        }
        var increments: [Increment] = []
        var inserts: [Insert] = []
        var skippedNames: [String] = []
    }

    /// Folds receipt units into the pantry's coarse vocabulary.
    static func coarse(quantity: Double, unit: String) -> (value: Double, unit: String) {
        switch unit.lowercased() {
        case "kg":       return (quantity, "kg")
        case "g", "gr":  return (quantity / 1000, "kg")
        case "l":        return (quantity, "l")
        case "ml":       return (quantity / 1000, "l")
        default:         return (quantity, "buc")
        }
    }

    static func plan(additions: [Addition], existing: [PantryItem]) -> Plan {
        var plan = Plan()
        // Merge duplicates within the receipt itself first (two "Lapte" rows).
        var merged: [String: Addition] = [:]
        var order: [String] = []
        for raw in additions {
            let (value, unit) = coarse(quantity: max(raw.quantity, 0), unit: raw.unit)
            guard value > 0, !raw.normalizedName.isEmpty else { continue }
            let key = raw.normalizedName.lowercased()
            if var already = merged[key] {
                if already.unit == unit {
                    already.quantity += value
                    merged[key] = already
                }
                // Same product in two dimensions on one receipt: keep the first.
            } else {
                merged[key] = Addition(name: raw.name, normalizedName: raw.normalizedName,
                                       quantity: value, unit: unit)
                order.append(key)
            }
        }

        let byNorm = Dictionary(grouping: existing) { $0.normalizedName.lowercased() }
        for key in order {
            guard let addition = merged[key] else { continue }
            if let item = byNorm[key]?.first {
                if item.unit == addition.unit {
                    plan.increments.append(.init(itemId: item.id, add: addition.quantity))
                } else {
                    plan.skippedNames.append(addition.name)
                }
            } else {
                plan.inserts.append(.init(name: addition.name,
                                          normalizedName: addition.normalizedName,
                                          quantity: addition.quantity,
                                          unit: addition.unit))
            }
        }
        return plan
    }
}
