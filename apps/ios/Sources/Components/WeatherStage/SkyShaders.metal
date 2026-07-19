#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// MARK: - WeatherStage sky (F1) — one full-screen pass, everything procedural
//
// Physically-INSPIRED, honestly stated: a Rayleigh-flavoured gradient by sun
// elevation (not a spectral scattering solve), fBM value-noise clouds in two
// parallax layers, hash stars, a phase-correct cosmetic moon, screen-space
// procedural rain/snow (the layered-streak technique), and a storm exposure
// flash driven by hashing absolute time — rare and never repeating, because
// its seed is the wall clock itself. Runs as a SwiftUI colorEffect at the
// display's cadence; the Swift side throttles for Low Power / Reduce Motion.

static inline float hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 443.8975);
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.x + p3.y) * p3.z);
}

static inline float vnoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash12(i);
    float b = hash12(i + float2(1, 0));
    float c = hash12(i + float2(0, 1));
    float d = hash12(i + float2(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static inline float fbm(float2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * vnoise(p);
        p = p * 2.03 + float2(17.1, 9.2);
        a *= 0.5;
    }
    return v;
}

// Screen-space precipitation: angled streak field in `layers` parallax
// sheets. Streaks are hash-seeded per column+time cell, so density and
// placement drift continuously — organic, never a tiled loop.
static inline float rainField(float2 uv, float t, float intensity) {
    float acc = 0.0;
    for (int i = 0; i < 3; i++) {
        float depth = 1.0 + float(i) * 0.9;          // near → far
        float2 p = uv * float2(38.0, 4.5) * depth;
        p.y += t * (9.0 - float(i) * 2.6) * depth;   // near falls fastest
        p.x += t * 0.55 * depth;                     // wind slant
        float2 cell = floor(p);
        float drop = step(0.985 - intensity * 0.012, hash12(cell));
        float core = smoothstep(0.42, 0.0, abs(fract(p.x) - 0.5));
        acc += drop * core * (0.20 - float(i) * 0.05);
    }
    return acc * intensity;
}

static inline float snowField(float2 uv, float t, float intensity) {
    float acc = 0.0;
    for (int i = 0; i < 3; i++) {
        float depth = 1.0 + float(i) * 0.8;
        float2 p = uv * 22.0 * depth;
        p.y += t * (0.9 + float(i) * 0.35) * depth;
        p.x += sin(t * 0.7 + float(i) * 2.1 + uv.y * 6.0) * 0.35; // waft
        float2 cell = floor(p);
        float flake = step(0.986 - intensity * 0.010, hash12(cell));
        float2 c = fract(p) - 0.5;
        float dot2 = smoothstep(0.18 - float(i) * 0.04, 0.0, length(c));
        acc += flake * dot2 * (0.55 - float(i) * 0.14);
    }
    return acc * intensity;
}

[[ stitchable ]] half4 weatherSky(float2 position, half4 color, float4 bounds,
                                  float time, float sunElev, float sunAz,
                                  float cloudiness, float rain, float snow,
                                  float fog, float storm, float moonPhase,
                                  float darkScheme) {
    float2 uv = (position - bounds.xy) / max(bounds.zw, float2(1.0, 1.0));
    float t = time;

    // ---- Sky gradient by sun elevation (day ↔ golden hour ↔ night) ----
    float day = smoothstep(-0.12, 0.35, sunElev);       // 0 night → 1 day
    float dusk = exp(-pow(sunElev * 3.2, 2.0));         // horizon warmth band

    float3 zenithDay   = float3(0.16, 0.38, 0.72);
    float3 horizonDay  = float3(0.62, 0.78, 0.92);
    float3 zenithNight = float3(0.010, 0.016, 0.042);
    float3 horizonNight = float3(0.045, 0.06, 0.11);
    float3 zenith  = mix(zenithNight,  zenithDay,  day);
    float3 horizon = mix(horizonNight, horizonDay, day);
    // Golden-hour injection, weighted toward the sun's side of the sky.
    float sunSide = 1.0 - abs(uv.x - sunAz);
    horizon = mix(horizon, float3(0.98, 0.55, 0.26), dusk * (0.45 + 0.45 * sunSide));
    zenith  = mix(zenith,  float3(0.42, 0.27, 0.45), dusk * 0.35);

    float3 sky = mix(zenith, horizon, pow(uv.y, 1.35));

    // ---- Sun disc + bloom (day), moon + stars (night) ----
    float2 sunPos = float2(sunAz, 0.78 - clamp(sunElev, 0.0, 1.0) * 0.55);
    float dSun = distance(uv * float2(1.0, 1.4), sunPos * float2(1.0, 1.4));
    float sunGlow = exp(-dSun * dSun * 55.0) * day;
    float sunDisc = smoothstep(0.030, 0.022, dSun) * day;
    sky += (float3(1.0, 0.92, 0.78) * sunGlow * 0.55 + float3(1.0, 0.98, 0.92) * sunDisc)
         * (1.0 - cloudiness * 0.7);

    float night = 1.0 - day;
    if (night > 0.01) {
        // Stars: two hash densities, gentle per-star twinkle.
        float2 sp = uv * float2(160.0, 260.0);
        float s1 = step(0.9965, hash12(floor(sp)));
        float tw = 0.6 + 0.4 * sin(t * 1.7 + hash12(floor(sp)) * 40.0);
        float2 sp2 = uv * float2(70.0, 120.0) + 31.7;
        float s2 = step(0.997, hash12(floor(sp2)));
        sky += float3(0.9, 0.93, 1.0) * (s1 * 0.55 * tw + s2 * 0.8) * night
             * (1.0 - cloudiness);

        // Moon with a cosmetic phase terminator.
        float2 moonPos = float2(1.0 - sunAz, 0.24);
        float dm = distance(uv * float2(1.0, 1.5), moonPos * float2(1.0, 1.5));
        float disc = smoothstep(0.052, 0.046, dm);
        float phaseOff = (moonPhase - 0.5) * 0.10;
        float dTerm = distance(uv * float2(1.0, 1.5),
                               (moonPos + float2(phaseOff, 0.0)) * float2(1.0, 1.5));
        float lit = disc * smoothstep(0.044, 0.052, dTerm + (moonPhase < 0.5 ? 0.004 : -0.004));
        float glowM = exp(-dm * dm * 160.0);
        sky += (float3(0.92, 0.94, 0.98) * max(lit, disc * 0.12)
              + float3(0.55, 0.6, 0.75) * glowM * 0.35) * night * (1.0 - cloudiness * 0.8);
    }

    // ---- Clouds: two fBM layers with parallax drift ----
    float2 cuv = float2(uv.x * 1.6, uv.y * 3.2);
    float c1 = fbm(cuv * 2.2 + float2(t * 0.016, 0.0));
    float c2 = fbm(cuv * 4.6 + float2(t * 0.031, 7.0));
    float deck = smoothstep(1.0 - cloudiness, 1.15 - cloudiness, c1 * 0.72 + c2 * 0.28);
    float3 cloudLit  = mix(float3(0.10, 0.11, 0.14), float3(0.97, 0.95, 0.94), day);
    cloudLit = mix(cloudLit, float3(1.0, 0.72, 0.5), dusk * 0.6);
    float3 cloudDark = cloudLit * (day > 0.5 ? 0.62 : 0.5);
    float shade = fbm(cuv * 3.1 + float2(t * 0.02, 3.0));
    sky = mix(sky, mix(cloudDark, cloudLit, shade), deck * (0.55 + 0.45 * cloudiness));

    // ---- Precipitation ----
    if (rain > 0.005) {
        sky *= 1.0 - rain * 0.18;                          // wet-air dimming
        float r = rainField(uv, t, rain);
        sky += float3(0.75, 0.82, 0.92) * r;
    }
    if (snow > 0.005) {
        sky = mix(sky, sky * 0.9 + float3(0.06, 0.07, 0.09), snow * 0.4);
        float s = snowField(uv, t, snow);
        sky += float3(0.96, 0.97, 1.0) * s;
    }

    // ---- Fog: contrast collapse + a slow moving veil ----
    if (fog > 0.005) {
        float veil = fbm(uv * 3.0 + float2(t * 0.008, t * 0.004));
        float3 fogCol = mix(float3(0.09, 0.10, 0.12), float3(0.82, 0.84, 0.87), day);
        sky = mix(sky, fogCol, fog * (0.55 + 0.35 * veil));
    }

    // ---- Storm flash: absolute-time hash → rare, NEVER-repeating ----
    if (storm > 0.5) {
        float cell = floor(t * 0.5);                        // 2s windows
        float gate = step(0.93, hash12(float2(cell, 17.3))); // ~7% of windows
        float ph = fract(t * 0.5);
        float burst = exp(-ph * 18.0) + 0.6 * exp(-fract(ph * 3.0 + hash12(float2(cell, 3.7))) * 26.0);
        sky += float3(0.9, 0.92, 1.0) * gate * burst * 0.8;
    }

    // Lens vignette — quiet cinematic edge falloff, static.
    float vig = 1.0 - 0.22 * pow(distance(uv, float2(0.5, 0.55)) * 1.3, 2.0);
    sky *= max(vig, 0.0);

    // Readability grade (Glass law: the backdrop never fights the text).
    // Dark theme tempers a bright day sky; light theme floors a black
    // night so near-black text keeps contrast. The look bends, never lies.
    if (darkScheme > 0.5) {
        sky *= mix(1.0, 0.52, smoothstep(0.45, 0.9, dot(sky, float3(0.299, 0.587, 0.114))));
    } else {
        float luma = dot(sky, float3(0.299, 0.587, 0.114));
        sky = mix(sky, sky * 0.4 + float3(0.52, 0.55, 0.62), smoothstep(0.32, 0.05, luma) * 0.85);
    }

    return half4(half3(clamp(sky, 0.0, 1.0)), color.a);
}
