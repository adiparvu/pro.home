// Generic clamp helper. Lived in PropertyMapCanvas.swift until the map-era
// cluster was deleted (2026-07-21); voice-message progress (and any future
// numeric UI) depends on it, so it owns a Utils home now.

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
