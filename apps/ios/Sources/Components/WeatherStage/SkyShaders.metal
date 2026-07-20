#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// MARK: - WeatherStage sky (F1–F4) — one full-screen pass, everything procedural
//
// Physically-INSPIRED, honestly stated: a Rayleigh-flavoured gradient by sun
// elevation (not a spectral scattering solve), fBM value-noise clouds in two
// parallax layers, hash stars, a phase-correct cosmetic moon, screen-space
// procedural rain/snow (the layered-streak technique), and a storm exposure
// flash driven by hashing absolute time — rare and never repeating, because
// its seed is the wall clock itself.
//
// F2 adds a real WIND field (magnitude+direction from the cached WeatherKit
// summary, gusted by low-frequency noise) shearing the rain, driving the
// snow and hurrying the cloud deck; a fourth NEAR rain sheet; and
// gyroscope-parallax LENS DROPLETS clinging to the "camera glass" in rain.
// F3 adds a BRANCHING LIGHTNING channel (a segment chain seeded by the same
// absolute-time hash as the exposure flash — no two bolts can ever repeat),
// BLIZZARD (wind-owned horizontal snow + white-out) and a volumetric-FEEL
// fog: two parallax layers, ground-hugging density, sun diffusion.
// F4 adds the after-rain RAINBOW (spectral band on the antisolar circle),
// SANDSTORM (ochre flow + airborne grain), summer-night FIREFLIES and cloud
// SHADOWS crossing the lower ground band.
//
// Runs as a SwiftUI colorEffect at the display's cadence; the Swift side
// throttles for Low Power / Reduce Motion. Every added effect is gated on
// its own intensity, so a clear day still costs only the F1 base pass.

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

static inline float segDist(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-5), 0.0, 1.0);
    return length(pa - ba * h);
}

// Screen-space precipitation: angled streak field in parallax sheets.
// Streaks are hash-seeded per column+time cell, so density and placement
// drift continuously — organic, never a tiled loop. `wind` (signed) shears
// the whole field and slants the fall; layer 0 is the F2 NEAR sheet —
// sparser, thicker, fastest.
static inline float rainField(float2 uv, float t, float intensity, float wind) {
    // Shear the space so streaks lean with the wind instead of sliding.
    float2 suv = float2(uv.x + uv.y * wind * 0.35, uv.y);
    float acc = 0.0;
    for (int i = 0; i < 4; i++) {
        float depth = 0.55 + float(i) * 0.9;         // near → far
        float2 p = suv * float2(i == 0 ? 16.0 : 38.0, 4.5) * depth;
        p.y += t * (11.0 - float(i) * 2.4) * depth;  // near falls fastest
        p.x += t * (0.15 + wind * 2.6) * depth;
        float2 cell = floor(p);
        float thresh = i == 0 ? 0.994 - intensity * 0.006
                              : 0.985 - intensity * 0.012;
        float drop = step(thresh, hash12(cell));
        // Per-drop brightness variety — a real shower never falls uniform.
        drop *= 0.55 + 0.45 * hash12(cell + 7.7);
        float width = i == 0 ? 0.34 : 0.42;
        float core = smoothstep(width, 0.0, abs(fract(p.x) - 0.5));
        acc += drop * core * (i == 0 ? 0.30 : 0.20 - float(i) * 0.045);
    }
    return acc * intensity;
}

static inline float snowField(float2 uv, float t, float intensity, float wind) {
    float acc = 0.0;
    for (int i = 0; i < 3; i++) {
        float depth = 1.0 + float(i) * 0.8;
        float2 p = uv * 22.0 * depth;
        p.y += t * (0.9 + float(i) * 0.35) * depth;
        p.x += sin(t * 0.7 + float(i) * 2.1 + uv.y * 6.0) * 0.35; // waft
        p.x += t * wind * (1.6 + float(i) * 0.5) * depth;          // driven
        float2 cell = floor(p);
        float flake = step(0.986 - intensity * 0.010, hash12(cell));
        float2 c = fract(p) - 0.5;
        float dot2 = smoothstep(0.18 - float(i) * 0.04, 0.0, length(c));
        acc += flake * dot2 * (0.55 - float(i) * 0.14);
    }
    return acc * intensity;
}

// F3 — the branching bolt: a 7-segment main channel walked down from the
// deck plus two 3-segment branches peeling off at the forks. Every offset
// is hashed from `seed` (= the absolute-time flash cell), so the geometry
// of each strike exists exactly once in history.
static inline float boltGlow(float2 uv, float seed) {
    float glow = 0.0;
    float2 prev = float2(0.2 + 0.6 * hash12(float2(seed, 1.0)), 0.04);
    float2 forkA = prev, forkB = prev;
    for (int i = 1; i <= 7; i++) {
        float jitter = (hash12(float2(seed, float(i) * 7.31)) - 0.5) * 0.16;
        float2 next = float2(clamp(prev.x + jitter, 0.05, 0.95),
                             0.04 + 0.10 * float(i));
        glow += exp(-segDist(uv, prev, next) * 90.0);
        if (i == 2) { forkA = next; }
        if (i == 4) { forkB = next; }
        prev = next;
    }
    float dirA = hash12(float2(seed, 31.7)) > 0.5 ? 1.0 : -1.0;
    float2 pa = forkA;
    for (int i = 1; i <= 3; i++) {
        float2 next = pa + float2(dirA * (0.03 + 0.05 * hash12(float2(seed, float(i) * 13.7))), 0.06);
        glow += 0.6 * exp(-segDist(uv, pa, next) * 110.0);
        pa = next;
    }
    float dirB = hash12(float2(seed, 57.3)) > 0.5 ? -1.0 : 1.0;
    float2 pb = forkB;
    for (int i = 1; i <= 3; i++) {
        float2 next = pb + float2(dirB * (0.03 + 0.05 * hash12(float2(seed, float(i) * 19.1))), 0.055);
        glow += 0.6 * exp(-segDist(uv, pb, next) * 110.0);
        pb = next;
    }
    return glow;
}

// F2 — lens droplets: two depth layers of hash-seeded drops clinging to the
// glass. Each cell may hold one drop that grows in, creeps down and
// evaporates on its own hashed clock; the gyroscope tilt shifts the layers
// at different rates — the parallax of real water on a real lens. Purely
// cosmetic refraction (a colorEffect cannot sample neighbours): a soft
// darkened body + a specular bead toward the light.
static inline float2 lensDrops(float2 px, float t, float density, float2 tilt) {
    float darken = 0.0, spec = 0.0;
    for (int layer = 0; layer < 2; layer++) {
        float scale = layer == 0 ? 7.0 : 12.0;
        float2 g = px * scale + float2(31.7 * float(layer), 7.9);
        g.x += tilt.x * (layer == 0 ? 0.55 : 0.95);
        g.y -= tilt.y * (layer == 0 ? 0.35 : 0.65);
        float2 cell = floor(g);
        float h = hash12(cell);
        float has = step(1.0 - density * 0.42, h);
        if (has < 0.5) { continue; }
        float h2 = hash12(cell + 11.1);
        float life = fract(t * (0.035 + 0.045 * h2) + h * 9.0);
        float grow = smoothstep(0.0, 0.12, life) * (1.0 - smoothstep(0.72, 1.0, life));
        float2 c = float2(0.25 + 0.5 * h2,
                          0.20 + 0.45 * fract(h * 13.0) + life * (0.16 + max(tilt.y, 0.0) * 0.10));
        float r = (layer == 0 ? 0.17 : 0.11) * (0.6 + 0.4 * fract(h * 29.0)) * grow;
        float d = length(fract(g) - c);
        float disc = smoothstep(r, r * 0.55, d);
        darken += disc * (layer == 0 ? 0.55 : 0.4);
        float ds = length(fract(g) - c + float2(r * 0.35, r * 0.35));
        spec += smoothstep(r * 0.45, 0.0, ds) * grow * (layer == 0 ? 1.0 : 0.7);
    }
    return float2(min(darken, 1.0), spec);
}

// F4 — fireflies: sparse wandering embers over the lower field, each with
// its own hashed blink cadence. Two layers for depth.
static inline float fireflyGlow(float2 uv, float t, float amount) {
    float acc = 0.0;
    for (int i = 0; i < 2; i++) {
        float2 g = uv * float2(9.0 + 4.0 * float(i), 7.0) + float2(3.1 * float(i), 1.7);
        float2 cell = floor(g);
        float h = hash12(cell);
        if (h > amount * 0.22) { continue; }
        float2 wander = float2(sin(t * (0.4 + h) + h * 40.0),
                               cos(t * (0.3 + h * 0.7) + h * 20.0));
        float2 c = 0.5 + wander * 0.18;
        float d = length(fract(g) - c);
        float blink = pow(0.5 + 0.5 * sin(t * (0.8 + 2.0 * h) + h * 50.0), 6.0);
        acc += exp(-d * d * 300.0) * blink;
    }
    return acc;
}

[[ stitchable ]] half4 weatherSky(float2 position, half4 color, float4 bounds,
                                  float time, float sunElev, float sunAz,
                                  float cloudiness, float rain, float snow,
                                  float fog, float storm, float moonPhase,
                                  float darkScheme, float wind, float sand,
                                  float rainbow, float fireflies,
                                  float tiltX, float tiltY) {
    float2 uv = (position - bounds.xy) / max(bounds.zw, float2(1.0, 1.0));
    float t = time;

    // Gusts: the reported wind, breathing on a slow noise — never a constant.
    float gust = wind * (0.75 + 0.25 * vnoise(float2(t * 0.11, 7.7)));
    float windAbs = abs(gust);
    float driftSign = gust >= 0.0 ? 1.0 : -1.0;

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
    // A low warm ember band deepens golden hour near the ground.
    sky += float3(0.90, 0.40, 0.20) * dusk * pow(uv.y, 3.0) * 0.15;
    // Atmospheric haze: a soft bright band above the horizon by day —
    // the depth cue real skies always carry.
    float haze = smoothstep(0.55, 0.95, uv.y) * day * (1.0 - cloudiness * 0.5);
    sky = mix(sky, float3(0.85, 0.88, 0.92), haze * 0.10);

    // ---- Sun disc + bloom (day), moon + stars (night) ----
    float2 sunPos = float2(sunAz, 0.78 - clamp(sunElev, 0.0, 1.0) * 0.55);
    float dSun = distance(uv * float2(1.0, 1.4), sunPos * float2(1.0, 1.4));
    float sunGlow = exp(-dSun * dSun * 55.0) * day;
    float sunDisc = smoothstep(0.030, 0.022, dSun) * day;
    sky += (float3(1.0, 0.92, 0.78) * sunGlow * 0.55 + float3(1.0, 0.98, 0.92) * sunDisc)
         * (1.0 - cloudiness * 0.7);

    float night = 1.0 - day;
    if (night > 0.01) {
        // Airglow: real night skies are never pure black — a faint cool
        // lift near the horizon keeps depth (and text contrast) alive.
        sky += float3(0.045, 0.07, 0.11) * night * smoothstep(0.55, 1.0, uv.y) * 0.55;

        // Stars v2: ROUND dots with per-star size, brightness and twinkle
        // cadence — no more square grid pixels.
        float2 sp = uv * float2(160.0, 260.0);
        float2 sc = floor(sp);
        float sh = hash12(sc);
        float s1 = step(0.9955, sh);
        float srad = 0.10 + 0.22 * fract(sh * 57.0);
        float sdot = smoothstep(srad, 0.0, length(fract(sp) - 0.5));
        float tw = 0.55 + 0.45 * sin(t * (1.0 + fract(sh * 91.0) * 2.4) + sh * 40.0);
        float2 sp2 = uv * float2(70.0, 120.0) + 31.7;
        float2 sc2 = floor(sp2);
        float sh2 = hash12(sc2);
        float s2 = step(0.997, sh2);
        float sdot2 = smoothstep(0.30, 0.0, length(fract(sp2) - 0.5));
        sky += float3(0.9, 0.93, 1.0) * (s1 * sdot * 0.8 * tw + s2 * sdot2 * 1.0) * night
             * (1.0 - cloudiness);

        // The Milky Way: a faint tilted dust band, fBM-mottled.
        float mwBand = exp(-pow((uv.y - (0.55 - uv.x * 0.25)) * 6.0, 2.0));
        float mw = fbm(float2(uv.x * 3.0 + uv.y * 1.5, uv.y * 6.0 - uv.x * 2.0));
        sky += float3(0.55, 0.60, 0.75) * mw * mwBand * night * (1.0 - cloudiness) * 0.055;

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

    // ---- Clouds v2: domain-warped fBM — billowing shapes instead of
    // static fuzz — with a vertical habitat band, horizon perspective and
    // a one-tap self-shadow lit from the sun's side. Fully skipped on a
    // clear sky (the expensive path costs nothing when there is nothing).
    float driftBoost = 1.0 + windAbs * 2.4;
    if (cloudiness > 0.02) {
        // Perspective: features compress toward the horizon (distance).
        float2 cuv = float2(uv.x * 1.6 * mix(1.0, 2.1, uv.y), uv.y * 3.2);
        float2 flow = float2(t * 0.016 * driftBoost * driftSign, 0.0);
        // Domain warp: bend the sampling space with a second fBM so the
        // deck billows and curls instead of tiling.
        float2 warpP = cuv * 1.9 + flow * 0.8;
        float2 warp = float2(fbm(warpP), fbm(warpP + float2(5.2, 1.3))) - 0.5;
        float2 q = cuv * 2.2 + warp * 0.9 + flow;
        float base = fbm(q) * 0.72 + fbm(q * 2.1 + float2(7.0, 3.0)) * 0.28;
        // Habitat band: densest mid-sky, thinner overhead and low.
        float bandV = smoothstep(0.02, 0.25, uv.y) * (1.0 - 0.5 * smoothstep(0.75, 1.0, uv.y));
        float deck = smoothstep(1.0 - cloudiness, 1.18 - cloudiness, base) * (0.55 + 0.45 * bandV);
        // Self-shadow: resample toward the sun — where the deck thickens
        // sunward, this pixel sits in its own cloud's shade.
        float toward = fbm(q + normalize(sunPos - uv + float2(1e-3, 1e-3)) * 0.25);
        float lit01 = clamp(0.5 + (base - toward) * 1.6, 0.0, 1.0);
        float3 cloudLit  = mix(float3(0.10, 0.11, 0.14), float3(0.99, 0.97, 0.95), day);
        cloudLit = mix(cloudLit, float3(1.0, 0.72, 0.5), dusk * 0.6);
        float3 cloudDark = cloudLit * (day > 0.5 ? 0.55 : 0.45);
        sky = mix(sky, mix(cloudDark, cloudLit, lit01), deck * (0.60 + 0.40 * cloudiness));
        // Silver lining: cloud EDGES facing the sun catch its light — the
        // rim brightens where the deck thins toward the glow.
        float rim = smoothstep(0.02, 0.22, deck) * (1.0 - smoothstep(0.22, 0.55, deck));
        sky += float3(1.0, 0.95, 0.85) * rim * exp(-dSun * dSun * 14.0) * day * 0.30;
    }
    // Low-sun flare: a warm horizontal scattering streak at golden hour.
    float flare = exp(-pow((uv.y - sunPos.y) * 22.0, 2.0)) * exp(-abs(uv.x - sunAz) * 2.6);
    sky += float3(1.0, 0.62, 0.30) * flare * dusk * day * (1.0 - cloudiness * 0.6) * 0.22;

    // F4 — cloud shadows crossing the lower ground band: the deck's own
    // shade projected as slow darker patches under a sunlit sky.
    float ground = smoothstep(0.72, 1.0, uv.y);
    if (ground > 0.001 && cloudiness > 0.05) {
        float shadowDeck = fbm(float2(uv.x * 2.4 + t * 0.02 * driftBoost * driftSign, 9.3));
        sky *= 1.0 - ground * day * cloudiness * 0.14 * smoothstep(0.35, 0.8, shadowDeck);
    }

    // ---- Precipitation ----
    if (rain > 0.005) {
        sky *= 1.0 - rain * 0.18;                          // wet-air dimming
        float r = rainField(uv, t, rain, gust);
        sky += float3(0.75, 0.82, 0.92) * r;
    }
    if (snow > 0.005) {
        sky = mix(sky, sky * 0.9 + float3(0.06, 0.07, 0.09), snow * 0.4);
        float s = snowField(uv, t, snow, gust);
        sky += float3(0.96, 0.97, 1.0) * s;

        // F3 — blizzard: once the wind owns the snowfall, near-horizontal
        // streaks tear across and the air whites out.
        float blizzard = snow * smoothstep(0.45, 0.8, windAbs);
        if (blizzard > 0.01) {
            float2 p = float2(uv.y * 34.0, uv.x * 4.0 - t * (3.0 + 4.0 * windAbs) * driftSign);
            float2 cellb = floor(p);
            float fl = step(0.975 - blizzard * 0.015, hash12(cellb));
            float core = smoothstep(0.45, 0.0, abs(fract(p.x) - 0.5));
            sky += float3(0.9, 0.93, 0.97) * fl * core * 0.5 * blizzard;
            sky = mix(sky, float3(0.75, 0.78, 0.84), blizzard * 0.25);
        }
    }

    // ---- Fog (F3 volumetric-feel): two parallax layers, ground-hugging
    // density, and the sun diffusing through as a soft bright core.
    if (fog > 0.005) {
        float v1 = fbm(uv * float2(2.6, 3.4) + float2(t * (0.010 + windAbs * 0.02), t * 0.004));
        float v2 = fbm(uv * float2(5.2, 6.0) + float2(-t * (0.016 + windAbs * 0.03), 5.0));
        float depthMix = v1 * 0.65 + v2 * 0.35;
        float vertical = 0.55 + 0.5 * smoothstep(0.25, 1.0, uv.y);
        float3 fogCol = mix(float3(0.09, 0.10, 0.12), float3(0.82, 0.84, 0.87), day);
        fogCol += float3(1.0, 0.9, 0.75) * exp(-dSun * dSun * 9.0) * day * 0.22;
        float density = fog * vertical * (0.45 + 0.45 * depthMix);
        sky = mix(sky, fogCol, min(density, 0.95));
    }

    // ---- Sandstorm (F4): ochre flow driven by the wind + airborne grain ----
    if (sand > 0.005) {
        float flow = fbm(float2(uv.x * 3.0 - t * (0.25 + windAbs * 0.6) * driftSign,
                                uv.y * 8.0 + t * 0.05));
        float3 ochre = mix(float3(0.42, 0.32, 0.20), float3(0.80, 0.64, 0.42), day);
        float grain = hash12(uv * 700.0 + fract(t) * 37.0) * 0.08;
        float density = sand * (0.55 + 0.4 * flow);
        sky = mix(sky, ochre + grain, min(density, 0.92));
    }

    // ---- Storm: absolute-time hashed exposure flash + branching bolt ----
    // The seed is the wall clock, so neither the flash rhythm nor any
    // bolt's geometry can ever repeat.
    if (storm > 0.5) {
        float cell = floor(t * 0.5);                        // 2s windows
        float gate = step(0.93, hash12(float2(cell, 17.3))); // ~7% of windows
        float ph = fract(t * 0.5);
        float burst = exp(-ph * 18.0) + 0.6 * exp(-fract(ph * 3.0 + hash12(float2(cell, 3.7))) * 26.0);
        sky += float3(0.9, 0.92, 1.0) * gate * burst * 0.55;
        if (gate > 0.5 && ph < 0.16) {
            float seed = cell + 0.37;
            float g = boltGlow(uv, seed);
            float flicker = 0.7 + 0.3 * sin(t * 90.0 + hash12(float2(cell, 5.5)) * 20.0);
            sky += float3(0.85, 0.88, 1.0) * min(g, 2.5) * (1.0 - ph / 0.16) * flicker * 0.9;
        }
    }

    // ---- Rainbow (F4): spectral band on the antisolar circle, sun up only.
    if (rainbow > 0.005) {
        float2 arcC = float2(1.0 - sunAz, 1.35);
        float dArc = distance(uv * float2(1.0, 1.2), arcC * float2(1.0, 1.2));
        float band = (dArc - 0.72) / 0.07;
        if (band > 0.0 && band < 1.0) {
            float3 spectral = 0.5 + 0.5 * cos(6.28318 * (band * 0.9 + float3(0.00, 0.33, 0.67)));
            float fade = sin(band * 3.14159);
            sky = mix(sky, spectral, fade * rainbow * 0.25 * day * (1.0 - cloudiness * 0.5));
        }
    }

    // ---- Fireflies (F4): warm summer nights only (Swift gates the season,
    // temperature and clear sky — the shader just glows).
    if (fireflies > 0.005) {
        float f = fireflyGlow(uv, t, fireflies) * smoothstep(0.4, 0.78, uv.y) * night;
        sky += float3(0.75, 0.95, 0.35) * f * 0.8;
    }

    // ---- Lens droplets (F2): rain on the camera glass, tilt-parallax ----
    if (rain > 0.03) {
        float aspect = bounds.w / max(bounds.z, 1.0);
        float2 px = float2(uv.x, uv.y * aspect);
        float2 drops = lensDrops(px, t, rain, float2(tiltX, tiltY));
        sky = sky * (1.0 - drops.x * 0.16) + float3(0.9, 0.94, 1.0) * drops.y * 0.35;
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

    // Dither: ±1/255 of hash noise breaks the banding OLED panels reveal
    // in slow dark gradients — invisible as grain, decisive as smoothness.
    sky += (hash12(position) - 0.5) * (2.0 / 255.0);

    return half4(half3(clamp(sky, 0.0, 1.0)), color.a);
}
