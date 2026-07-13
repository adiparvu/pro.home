// Unreferenced since tab 2 became Spațiile casei (user decision) — safe to delete in a cleanup pass.
import UIKit

// MARK: - Aerial photo pyramid
//
// The drone photo can be enormous (a 12MP+ image decodes to hundreds of MB
// of texture). Rendering it full-res at zoom 1 wastes memory, GPU sampling
// and battery on every frame. Instead the canvas asks this pyramid for the
// smallest level that still looks crisp at the current zoom:
//
//   needed pixels = viewport pixels × zoom  →  1536 / 3072 / 6144 / native
//
// Levels are produced with UIKit's decode-efficient thumbnailing (no full
// bitmap inflation for the small levels) and cached for the app's lifetime,
// so the cost is paid once per level. The canvas upgrades levels when a
// pinch ends — never downgrades — which is why zooming feels like a map
// app: soft while the fingers move, crisp on release.

actor AerialImagePyramid {
    static let shared = AerialImagePyramid()

    private var cache: [Int: UIImage] = [:]
    private let steps: [CGFloat] = [1536, 3072, 6144]

    /// The smallest pyramid level with at least `pixels` width, or nil when
    /// the already-displayed image (`currentWidth`, in pixels) is enough —
    /// the canvas never swaps textures for nothing.
    func image(atLeast pixels: CGFloat, currentWidth: CGFloat?) async -> UIImage? {
        guard let base = UIImage(named: "aerial_property") else { return nil }
        let nativeW = base.size.width * base.scale
        let nativeH = base.size.height * base.scale
        let target = min(steps.first(where: { $0 >= pixels }) ?? nativeW, nativeW)

        if let currentWidth, currentWidth >= target - 1 { return nil }

        let key = Int(target)
        if let hit = cache[key] { return hit }

        let result: UIImage?
        if target >= nativeW {
            result = await base.byPreparingForDisplay() ?? base
        } else {
            let size = CGSize(width: target, height: nativeH * target / nativeW)
            result = await base.byPreparingThumbnail(ofSize: size)
        }
        if let result { cache[key] = result }
        return result
    }
}
