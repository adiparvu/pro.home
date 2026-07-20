import SwiftUI

// MARK: - StretchyHeroHeader
//
// The TestFlight-style edge-to-edge hero for detail pages: the media bleeds
// under the status bar, stretches on pull-down (top edge stays pinned to the
// screen top, no gap, no jitter), recedes at ~half speed behind the content
// on scroll-up, and dims under a quadratic scrim as it goes. Everything is
// derived from the header's own frame inside the host scroll view — one
// GeometryReader scoped to the header, zero timers, zero full-page geometry
// wrappers — so the effect stays pure layout math at 120Hz.
//
// Contract for hosts:
// 1. Place the header as the FIRST child of a `ScrollView` whose top content
//    inset is removed (`.ignoresSafeArea(edges: .top)` on the ScrollView),
//    so the header's rest position is the very top of the screen.
// 2. Name the ScrollView's coordinate space and pass that name as
//    `scrollSpace` — stretch/parallax are measured in it (rest minY == 0).
// 3. `media` is the stretchable photo layer (give it `scaledToFill`
//    content; the header sizes and clips it). `overlay` receives the hero's
//    resting bounds and is NEVER stretched, receded, or dimmed — pin
//    controls (camera button, edge gradients) inside it with your own
//    alignment; it stays glued to the hero's bottom edge.
// 4. The header publishes `StretchyHeroBottomEdgeKey` — the hero's resting
//    bottom edge in GLOBAL coordinates, rounded to the point. Hosts read it
//    with `onPreferenceChange` to drive a compact-bar fade; because the
//    value is layout-derived it updates during scroll, so hosts must write
//    state only when their derived value actually changes.
//
// Reduce Motion: stretch, parallax and the scroll scrim are disabled — the
// hero stays a static edge-to-edge photo that scrolls 1:1 and clips
// normally. The preference keeps publishing so bars still appear (hosts
// decide to step instead of fade).
struct StretchyHeroHeader<Media: View, Overlay: View>: View {
    /// Resting height of the hero, in points.
    var height: CGFloat = 280
    /// Name of the host ScrollView's `.coordinateSpace(name:)`.
    let scrollSpace: String
    /// How fast the media recedes while scrolling up (0 = pinned,
    /// 1 = scrolls 1:1). 0.5 is the TestFlight feel.
    var parallaxFactor: CGFloat = 0.5
    /// Peak darkness of the scroll-away scrim.
    var maxScrimOpacity: CGFloat = 0.35
    /// Scroll distance over which the scrim reaches its peak.
    var scrimDistance: CGFloat = 220
    @ViewBuilder let media: () -> Media
    @ViewBuilder let overlay: () -> Overlay

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .named(scrollSpace)).minY
            let stretch = reduceMotion ? 0 : max(0, minY)
            let recede = (reduceMotion || minY >= 0) ? 0 : -minY * parallaxFactor

            overlay()
                .frame(width: geo.size.width, height: height)
                .background(alignment: .top) {
                    // Layout: media grows by the overscroll below the hero's
                    // box, the inner offset slides it inside the stationary
                    // clip window for parallax, and the outer offset lifts
                    // clip + content together so the top edge stays pinned
                    // to the screen top while stretching. The clip's bottom
                    // edge never leaves the hero's resting bottom, so the
                    // photo-to-content seam stays hard in every phase.
                    media()
                        .frame(width: geo.size.width, height: height + stretch)
                        .offset(y: recede)
                        .clipped()
                        .overlay {
                            Color.black.opacity(scrimOpacity(for: minY))
                                .allowsHitTesting(false)
                        }
                        .offset(y: -stretch)
                }
                .preference(key: StretchyHeroBottomEdgeKey.self,
                            value: geo.frame(in: .global).maxY.rounded())
        }
        .frame(height: height)
    }

    /// Quadratic ease-in: imperceptible on small scrolls, settling at
    /// `maxScrimOpacity` once `scrimDistance` points have scrolled away.
    private func scrimOpacity(for minY: CGFloat) -> Double {
        guard !reduceMotion, minY < 0 else { return 0 }
        let progress = min(-minY / scrimDistance, 1)
        return maxScrimOpacity * progress * progress
    }
}

/// The hero's resting bottom edge in global coordinates (rounded to the
/// point). Hosts derive their compact-bar fade from it.
struct StretchyHeroBottomEdgeKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
