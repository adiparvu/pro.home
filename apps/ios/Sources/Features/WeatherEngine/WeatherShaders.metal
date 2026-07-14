//  WeatherShaders.metal
//  Reference stitchable shaders for the Dynamic Weather Engine.
//
//  These are applied from SwiftUI via the `Shader` API (iOS 17+): a
//  `[[ stitchable ]]` function is referenced as `ShaderLibrary.<name>(...)`
//  and attached with `.colorEffect` / `.layerEffect` / `.distortionEffect`.
//  The .metal file compiles into the app's DEFAULT metal library
//  (`default.metallib`), which `ShaderLibrary.default` loads — no explicit
//  library handle is needed on the Swift side.
//
//  COORDINATE CONVENTION: SwiftUI passes `position` in the view's local
//  user-space (points). None of these shaders can know the view size on their
//  own, so every one takes an explicit `size` (points) and normalises
//  `uv = position / size` into 0...1. `layer.sample(p)` likewise expects
//  user-space points, so we sample with `uv * size`.
//
//  BUILD RISK (flagged to the lead): this is the FIRST .metal file in the
//  project. It cannot be compiled in this environment, and Metal has no
//  overload/type checking here — treat every function below as unverified
//  until it builds on a Metal toolchain. The Swift-side argument order/types
//  in WeatherShaders.swift must match these signatures EXACTLY or the effect
//  silently draws nothing (or asserts at runtime).

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// MARK: - Small helpers

// Cheap 2D hash → 0...1 per component. Deterministic per cell, so droplets and
// streaks are stable across frames (only the time term animates them).
static inline float2 wx_hash2(float2 p) {
    p = float2(dot(p, float2(127.1, 311.7)),
               dot(p, float2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453123);
}

// MARK: - 1. Volumetric light shaft (god rays)
//
// Additive radial shafts streaming from a sun point. Apply to a filled
// Rectangle with `.blendMode(.plusLighter)` over the sky: the function ignores
// the incoming `color` and RETURNS premultiplied light, so plusLighter adds
// the shafts onto whatever sky sits behind the rectangle.
//
// Uniforms:
//   size      view size in points (for uv normalisation)
//   sun       sun position in uv (0...1); the shaft origin
//   time      seconds; slowly rotates the streak phase so rays shimmer
//   strength  0...1 master intensity (WeatherParameters.godRayStrength)
//   warm      shaft tint (premultiplied out by the caller's Color)
[[ stitchable ]]
half4 wx_volumetricLightShaft(float2 position,
                              half4 color,
                              float2 size,
                              float2 sun,
                              float time,
                              float strength,
                              half4 warm) {
    float2 uv = position / size;
    float2 d = uv - sun;
    float dist = length(d);
    float ang = atan2(d.y, d.x);

    // High-frequency angular function → discrete shafts; two octaves,
    // counter-drifting, so the rays breathe instead of strobing.
    float s1 = 0.5 + 0.5 * sin(ang * 16.0 + time * 0.35);
    float s2 = 0.5 + 0.5 * sin(ang * 9.0 - time * 0.22 + 1.7);
    float streak = pow(s1 * 0.6 + s2 * 0.4, 3.0);

    float radial = smoothstep(1.15, 0.05, dist); // shafts fade with distance
    float core = smoothstep(0.42, 0.0, dist);     // soft bright sun core

    float intensity = clamp((streak * radial * 0.55 + core * 0.9) * strength,
                            0.0, 1.0);
    half3 rgb = warm.rgb * half(intensity);
    return half4(rgb, half(intensity)); // premultiplied for plusLighter
}

// MARK: - 2. Lens rain refraction
//
// Droplets on the "camera lens" that refract and magnify the scene behind
// them, with a slow downward drift and an occasional faster trickle. Apply
// with `.layerEffect` to the content being looked through; set
// `maxSampleOffset` to a few dozen points (the max refraction reach).
//
// Uniforms:
//   size       view size in points
//   time       seconds; drives drift + trickle
//   intensity  0...1 droplet density / refraction strength
[[ stitchable ]]
half4 wx_lensRain(float2 position,
                  SwiftUI::Layer layer,
                  float2 size,
                  float time,
                  float intensity) {
    float2 uv = position / size;

    // Droplet grid — denser and more refractive as intensity rises.
    float scale = mix(8.0, 15.0, intensity);
    float2 gv = uv * scale;
    float2 cell = floor(gv);
    float2 f = fract(gv) - 0.5; // -0.5...0.5 within the cell

    float2 h = wx_hash2(cell);
    float radius = mix(0.14, 0.32, h.x);

    // Slow settle for every droplet; a minority "trickle" faster (a runnel of
    // water sliding down the glass). h.y picks which droplets trickle.
    float trickle = step(0.82, h.y);
    float drift = fract(h.x + time * mix(0.03, 0.35, trickle)) - 0.5;
    float2 center = float2((h.x - 0.5) * 0.4, (h.y - 0.5) * 0.4 + drift * 0.9);

    float dd = length(f - center);
    if (dd < radius && intensity > 0.001) {
        // Lens magnification: pull the sample toward the droplet centre, more
        // strongly near the rim, so the droplet acts like a tiny magnifier.
        float k = (dd / radius);
        float2 localUV = (f - center) / scale;      // back to uv units
        float2 refractUV = uv - localUV * (0.6 + 0.8 * k * intensity);
        half4 refr = layer.sample(refractUV * size);
        // Bright meniscus at the rim + a dark base — reads as a wet bead.
        float rim = smoothstep(radius, radius * 0.72, dd);
        return refr + half4(half3(rim * 0.18), 0.0);
    }
    return layer.sample(position);
}

// MARK: - 3. Lightning sky illumination + bloom
//
// A flash gradient biased to a top-edge origin that brightens the cloud field
// below it, scaled by the engine's live `flash` (0...1). Apply to a filled
// Rectangle with `.blendMode(.plusLighter)` over the clouds; the function
// ignores the incoming `color` and returns premultiplied light.
//
// Uniforms:
//   size    view size in points
//   origin  strike origin in uv (near the top edge)
//   flash   0...1 live brightness (WeatherEngine.flashLevel)
//   tint    flash color (cool storm white/blue)
[[ stitchable ]]
half4 wx_lightningIllumination(float2 position,
                               half4 color,
                               float2 size,
                               float2 origin,
                               float flash,
                               half4 tint) {
    float2 uv = position / size;
    float2 d = uv - origin;
    float dist = length(d);

    // Radial bloom from the strike, plus a top-down wash so the whole upper
    // cloud field lifts (Apple's storms brighten the clouds, not the ground).
    float bloom = smoothstep(1.25, 0.0, dist);
    float topWash = smoothstep(1.0, 0.0, uv.y);
    float intensity = clamp(flash * (bloom * 0.85 + topWash * 0.35), 0.0, 1.0);

    half3 rgb = tint.rgb * half(intensity);
    return half4(rgb, half(intensity)); // premultiplied for plusLighter
}
