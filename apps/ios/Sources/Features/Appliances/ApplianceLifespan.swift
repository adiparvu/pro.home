import Foundation

// MARK: - Curated typical lifespans (honesty law)
//
// One small, category-level table with its source documented here — never a
// per-model promise. The backbone values come from the NAHB / Bank of America
// Home Equity "Study of Life Expectancy of Home Components" (2007), collapsed
// to PRVIO's appliance categories and kept as RANGES. The UI must always
// render them with the "~" prefix ("~10–15 ani") and pair them with the
// disclaimer footnote — an orientation, not a precision.
enum ApplianceLifespan {

    /// Typical service life in whole years for a category, or nil when the
    /// category is too heterogeneous to state a number honestly.
    static func typicalYears(for category: ApplianceCategory) -> ClosedRange<Int>? {
        switch category {
        case .hvac:
            // NAHB 2007: central AC 10–15, heat pumps ~16, furnaces 15–20.
            // Collapsed to the conservative common band.
            return 10...15
        case .kitchen:
            // NAHB 2007: dishwashers ~9, refrigerators ~13, ranges/ovens 13–15.
            return 9...15
        case .laundry:
            // NAHB 2007: washing machines ~10, dryers ~13.
            return 10...13
        case .bathroom:
            // NAHB 2007: electric/gas water heaters 10–11, exhaust fans ~10.
            return 10...12
        case .security:
            // Assumption: consumer security electronics (panels, cameras,
            // video doorbells) are bounded by manufacturer support windows
            // rather than mechanics — industry consensus ~5–10 years. Not in
            // the NAHB study; kept deliberately wide.
            return 5...10
        case .entertainment:
            // Assumption: TVs/audio, usage-dependent industry consensus ~7–10
            // years. Not in the NAHB study; kept deliberately wide.
            return 7...10
        case .other:
            // A grab bag — no honest number exists, so the UI shows nothing.
            return nil
        }
    }
}
