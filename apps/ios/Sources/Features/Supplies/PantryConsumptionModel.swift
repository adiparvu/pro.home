import Foundation

// MARK: - Pantry consumption model (pure, tested)
//
// The pantry grows automatically from scanned receipts but only shrinks by
// manual taps — so between shops the stored numbers read higher than the
// shelf. This model infers the missing consumption from the repurchase
// rhythm: how much of a product the household buys, divided by how long it
// lasts until the next purchase. Everything here is DISPLAY-LAYER truth —
// stored quantities are never mutated, and with fewer than two distinct
// purchases there is no inference at all (the stored number passes through).

enum PantryConsumptionModel {

    /// One real purchase of a product, read off a stored receipt line.
    struct PurchaseEvent: Equatable {
        var date: Date
        var quantity: Double
    }

    /// What the model concluded for one pantry item.
    struct Estimate: Equatable {
        /// Units consumed per day, or nil when history is too thin to infer.
        var dailyPace: Double?
        /// Stored quantity minus inferred consumption since the last
        /// restock, floored at zero; equals the stored quantity when no
        /// pace is known.
        var effectiveQuantity: Double
        /// Whole days until the effective quantity hits zero (rounded up),
        /// or nil when the pace is unknown.
        var daysUntilEmpty: Int?
    }

    /// Sane pace bounds: slower than one unit per hundred days rounds to
    /// "doesn't deplete", faster than ten units a day is a parsing artifact,
    /// not a household.
    static let paceBounds: ClosedRange<Double> = 0.01...10.0

    private static let secondsPerDay: TimeInterval = 86_400

    // MARK: Pace

    /// Average daily consumption inferred from the repurchase rhythm: for
    /// each pair of consecutive purchase days, the quantity bought on the
    /// earlier day divided by the days until the next, averaged across all
    /// intervals and clamped to `paceBounds`. Purchases on the same day
    /// merge into one restock first; fewer than two distinct purchase days
    /// means nil — no guessing on thin history.
    static func dailyPace(for purchases: [PurchaseEvent]) -> Double? {
        let events = restocks(from: purchases)
        guard events.count >= 2 else { return nil }
        var rates: [Double] = []
        rates.reserveCapacity(events.count - 1)
        for i in 0..<(events.count - 1) {
            let days = events[i + 1].date.timeIntervalSince(events[i].date) / secondsPerDay
            guard days > 0 else { continue }
            rates.append(events[i].quantity / days)
        }
        guard !rates.isEmpty else { return nil }
        let average = rates.reduce(0, +) / Double(rates.count)
        return min(max(average, paceBounds.lowerBound), paceBounds.upperBound)
    }

    // MARK: Estimate

    /// The stock the household plausibly has left NOW: the stored quantity
    /// minus pace × days since the last restock, floored at zero. Pass
    /// `restockedAt` when something newer than the last purchase reset the
    /// clock — a manual correction outranks the model. Without a pace the
    /// stored quantity passes through untouched.
    static func estimate(storedQuantity: Double,
                         purchases: [PurchaseEvent],
                         asOf now: Date,
                         restockedAt: Date? = nil) -> Estimate {
        let stored = max(storedQuantity, 0)
        guard let pace = dailyPace(for: purchases),
              let lastPurchase = purchases.map(\.date).max() else {
            return Estimate(dailyPace: nil, effectiveQuantity: stored,
                            daysUntilEmpty: nil)
        }
        let anchor = max(lastPurchase, restockedAt ?? .distantPast)
        let elapsedDays = max(0, now.timeIntervalSince(anchor) / secondsPerDay)
        let effective = max(0, stored - pace * elapsedDays)
        return Estimate(dailyPace: pace,
                        effectiveQuantity: effective,
                        daysUntilEmpty: Int((effective / pace).rounded(.up)))
    }

    // MARK: Receipt-quantity folding

    /// Receipt lines lose their unit on the wire — "0.5" (kg) and "500" (g)
    /// both persist as bare numbers. On a weighed or poured pantry row a
    /// value this large can only be grams/millilitres, so fold it to the
    /// base unit the same way the merge engine's `coarse` did when the
    /// purchase stocked the row. Counted rows ("buc") pass through untouched.
    static func baseQuantity(_ quantity: Double, pantryUnit: String) -> Double {
        guard pantryUnit != "buc", quantity >= 20 else { return quantity }
        return quantity / 1000
    }

    // MARK: Same-day merge

    /// Purchases collapsed to one event per day (quantities summed, empty
    /// and negative lines dropped), sorted oldest first. Two receipts on
    /// one shop day are one restock, not a zero-day interval.
    private static func restocks(from purchases: [PurchaseEvent]) -> [PurchaseEvent] {
        var byDay: [Int: PurchaseEvent] = [:]
        for event in purchases where event.quantity > 0 {
            let bucket = Int((event.date.timeIntervalSinceReferenceDate / secondsPerDay)
                .rounded(.down))
            if var merged = byDay[bucket] {
                merged.quantity += event.quantity
                merged.date = min(merged.date, event.date)
                byDay[bucket] = merged
            } else {
                byDay[bucket] = event
            }
        }
        return byDay.values.sorted { $0.date < $1.date }
    }
}
