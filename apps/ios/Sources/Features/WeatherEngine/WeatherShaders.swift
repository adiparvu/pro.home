import SwiftUI

// MARK: - Weather Engine · Metal shader wrappers
//
// Typed Swift entry points for the three `[[ stitchable ]]` functions in
// WeatherShaders.metal. Each builder mirrors its Metal signature EXACTLY (the
// arguments after the runtime-supplied `position`/`color`/`layer`); if the two
// drift, the effect silently no-ops, so they are kept side by side on purpose.
//
// COMPILE RISK (flagged): the `Shader` API is iOS 17+ (the app targets 17.1,
// so no availability guard is needed), but the argument marshalling here
// CANNOT be verified without a Metal toolchain + device. Specifically
// unverified: that `.color(_:)` lands as a usable `half4`, that `.float2`
// from a `CGSize`/`UnitPoint` maps to the shader's `float2`, and that
// `.blendMode(.plusLighter)` composites the additive layers as intended.
// These are the first shaders in the app — treat as reference until proven on
// device.
//
// FALLBACK POLICY: all three effects ARE expressible with the `Shader` API, so
// none ships a Canvas fallback here. If a shader fails to build/load on device,
// the layer draws nothing (it is always additive over a complete sky), so the
// scene degrades to "no god rays / no lens beads / no bloom" — never to a
// broken frame. The god-ray and lightning layers are also strength-gated in
// their scenes, so a zero strength never mounts them at all.

// MARK: - God-ray (volumetric light shaft) layer

/// Additive volumetric light shafts streaming from `sun` (in unit space).
/// Renders a `plusLighter` rectangle so it lifts whatever sky sits behind it.
/// Mounts nothing when `strength <= 0`.
struct GodRayLayer: View {
    /// Sun / shaft origin in unit space (0...1).
    let sun: UnitPoint
    /// 0...1 master intensity (WeatherParameters.godRayStrength).
    let strength: Double
    /// Warm shaft tint.
    let warmth: Color
    /// Seconds from the stage's single TimelineView clock.
    let time: TimeInterval
    /// The view size in points (the shader normalises against it).
    let size: CGSize

    var body: some View {
        if strength > 0.001, size.width > 1 {
            Rectangle()
                .fill(.clear)
                .colorEffect(
                    ShaderLibrary.wx_volumetricLightShaft(
                        .float2(size),
                        .float2(CGPoint(x: sun.x, y: sun.y)),
                        .float(Float(time)),
                        .float(Float(strength)),
                        .color(warmth)))
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Lightning illumination layer

/// Additive flash bloom biased to `origin` (unit space, near the top edge),
/// scaled by the engine's live `flash`. `plusLighter` over the cloud field.
/// Costs a full-screen shader pass only while `flash > 0`; a settled storm
/// between strikes sits at flash 0 and this draws nothing perceptible (still a
/// pass — the scene keeps it mounted only while the storm is on screen).
struct LightningIlluminationLayer: View {
    let origin: UnitPoint
    /// 0...1 live brightness (WeatherEngine.flashLevel).
    let flash: Double
    /// Flash color — a cool storm white/blue.
    let tint: Color
    let size: CGSize

    var body: some View {
        if size.width > 1 {
            Rectangle()
                .fill(.clear)
                .colorEffect(
                    ShaderLibrary.wx_lightningIllumination(
                        .float2(size),
                        .float2(CGPoint(x: origin.x, y: origin.y)),
                        .float(Float(flash)),
                        .color(tint)))
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Lens-rain refraction modifier

extension View {
    /// Refracts THIS view through drifting lens droplets (`.layerEffect`).
    /// Apply to the content being looked "through" (the sky/scene). `intensity`
    /// 0...1 scales droplet density and refraction; `maxSampleOffset` bounds
    /// how far the refraction can reach, so it is sized to the droplet radius.
    ///
    /// The stage only applies this on rain/heavyRain, and only while the
    /// policy allows motion — a still frame (Reduce Motion / Low Power) passes
    /// `time` frozen, so the droplets hold instead of drifting.
    @ViewBuilder
    func weatherLensRain(time: TimeInterval, intensity: Double, size: CGSize) -> some View {
        if intensity > 0.001, size.width > 1 {
            self.layerEffect(
                ShaderLibrary.wx_lensRain(
                    .float2(size),
                    .float(Float(time)),
                    .float(Float(intensity))),
                maxSampleOffset: CGSize(width: 26, height: 26))
        } else {
            self
        }
    }
}
