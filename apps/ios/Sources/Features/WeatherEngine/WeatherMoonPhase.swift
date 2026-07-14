import Foundation

// MARK: - Weather Engine · Moon phase (real astronomy)
//
// A low-precision lunar phase for the night scene. It computes the Moon's age
// (days since the last new moon) from a fixed reference new moon and the mean
// synodic month, then the illuminated fraction and which limb is lit. This is
// the standard "mean phase" approximation, NOT a full ELP/Meeus solution — it
// ignores the Moon's orbital eccentricity, so the exact instant of each phase
// can be off by up to ~14 hours. That is far inside what the eye can judge
// from a drawn crescent, and it is honest to the constitution: good enough to
// draw tonight's moon, never presented as an ephemeris.
//
// SOURCE (documented per the honesty law):
//   - Synodic month  = 29.530588861 days (mean lunation; Jean Meeus,
//     "Astronomical Algorithms", 2nd ed., ch. 49).
//   - Reference new moon epoch = Julian Date 2451550.1, corresponding to
//     2000-01-06 18:14 UTC (the widely-used lunation-0 epoch; Meeus / NASA
//     eclipse tables). Ages are measured forward from it.
//   - Unix→JD:  JD = unixSeconds / 86400 + 2440587.5.
//
// The same family of approximation as the app's existing `SunWindow`
// (AppMood.swift) — declination/hour-angle level precision — so the two read
// as one honest astronomy layer.

/// Tonight's moon, distilled to what the night scene draws.
struct MoonPhase: Equatable {
    /// Age in days since the last new moon, 0 ..< 29.53.
    let ageDays: Double
    /// Illuminated fraction of the disc, 0 (new) ... 1 (full).
    let illuminatedFraction: Double
    /// Phase position on the cycle, 0 (new) → 0.5 (full) → 1 (next new).
    let phaseFraction: Double
    /// True while the Moon is waxing (illumination growing) — the RIGHT limb
    /// is lit in the northern hemisphere; waning lights the left limb.
    let isWaxing: Bool

    private static let synodicMonth = 29.530588861
    private static let referenceNewMoonJD = 2451550.1

    /// Compute the phase for a given moment (defaults to now).
    static func current(at date: Date = .now) -> MoonPhase {
        let julianDay = date.timeIntervalSince1970 / 86400.0 + 2440587.5
        var age = (julianDay - referenceNewMoonJD)
            .truncatingRemainder(dividingBy: synodicMonth)
        if age < 0 { age += synodicMonth } // keep it in [0, synodic)

        let phaseFraction = age / synodicMonth
        // Illuminated fraction from the phase angle: (1 − cos θ) / 2, where
        // θ sweeps 0→2π across the lunation. New = 0, full = 1, symmetric.
        let phaseAngle = 2 * Double.pi * phaseFraction
        let illuminated = (1 - cos(phaseAngle)) / 2

        return MoonPhase(ageDays: age,
                         illuminatedFraction: illuminated,
                         phaseFraction: phaseFraction,
                         isWaxing: phaseFraction < 0.5)
    }

    /// A localized name key for the nearest principal/intermediate phase —
    /// used by the night scene's accessibility label and the gallery caption.
    var nameKey: String {
        switch phaseFraction {
        case ..<0.03, 0.97...: return "weather_moon_new"
        case ..<0.22:          return "weather_moon_waxing_crescent"
        case ..<0.28:          return "weather_moon_first_quarter"
        case ..<0.47:          return "weather_moon_waxing_gibbous"
        case ..<0.53:          return "weather_moon_full"
        case ..<0.72:          return "weather_moon_waning_gibbous"
        case ..<0.78:          return "weather_moon_last_quarter"
        default:               return "weather_moon_waning_crescent"
        }
    }
}
