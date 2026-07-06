import SwiftUI

// MARK: - Hero zoom transitions (iOS 18+, graceful no-op on 17)
//
// The app's motion signature: tapping a photo grows it out of its cell into
// the detail view and shrinks it back on dismiss — the Photos-app gesture,
// via the system zoom transition. On iOS 17 these are no-ops and the
// standard sheet presentation plays instead, so nothing is gated off.

extension View {
    /// Marks this view as the zoom source for `id` in `namespace`.
    @ViewBuilder
    func zoomTransitionSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// Applies the system zoom transition to presented content, growing it
    /// from the source marked with the same `sourceID`.
    @ViewBuilder
    func zoomTransition(sourceID: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
    }
}
