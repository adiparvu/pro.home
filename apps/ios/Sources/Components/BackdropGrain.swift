import SwiftUI
import UIKit

// MARK: - BackdropGrain — the film layer under every mood backdrop
//
// Pure vector gradients band visibly on wide, slow color ramps — the exact
// "drawn, not photographed" tell. A whisper of monochrome grain composited
// with `.overlay` dithers those bands away and gives the backdrop the
// texture of a photograph. The tile is generated ONCE per process from a
// fixed seed (deterministic — every launch, every device renders the same
// grain), then tiled by the compositor: one small texture, one static
// layer, zero per-frame work.

/// One deterministic 144×144 grayscale noise tile centered on mid-gray
/// (neutral under `.overlay` blending), amplitude ±24/255.
enum BackdropGrain {
    static let tile: Image = Image(uiImage: makeTile(size: 144, seed: 0x5EED_1DEA))

    /// SplitMix64 — tiny, fast, and fully deterministic for a fixed seed.
    private struct SplitMix64 {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private static func makeTile(size: Int, seed: UInt64) -> UIImage {
        var rng = SplitMix64(state: seed)
        var pixels = [UInt8](repeating: 128, count: size * size)
        for index in pixels.indices {
            // Uniform in 128 ± 24 — quiet enough to disappear as texture,
            // strong enough to break gradient banding.
            pixels[index] = UInt8(104 + Int(rng.next() % 49))
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(width: size, height: size,
                                    bitsPerComponent: 8, bitsPerPixel: 8,
                                    bytesPerRow: size,
                                    space: CGColorSpaceCreateDeviceGray(),
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                    provider: provider, decode: nil,
                                    shouldInterpolate: false,
                                    intent: .defaultIntent)
        else {
            // Neutral fallback — an empty image simply renders nothing;
            // the backdrop stays correct, just without grain.
            return UIImage()
        }
        return UIImage(cgImage: cgImage)
    }
}

/// The composable overlay: tiles the grain across whatever it covers.
/// Opacity is tuned per ground — dark grounds hide more, so they can carry
/// a touch more texture before it reads as noise.
struct BackdropGrainOverlay: View {
    let scheme: ColorScheme

    var body: some View {
        BackdropGrain.tile
            .resizable(resizingMode: .tile)
            .blendMode(.overlay)
            .opacity(scheme == .dark ? 0.045 : 0.03)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
