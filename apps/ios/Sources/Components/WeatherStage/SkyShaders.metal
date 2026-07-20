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
// F4 adds the after-rain RAINBOW (a PARTIAL antisolar arc segment — never
// a full hoop — additive, patchy, with a faint reversed secondary),
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

// Five-octave variant for the cloud deck only — the extra octave buys the
// crisp curling edges the 4-octave field smears. Paid ONLY when cloudy.
static inline float fbm5(float2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) {
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

    // ---- Sky v6 (brief "first-party Apple"): the base is a physically-
    // based SINGLE-SCATTERING solve in HDR, not painted color stops.
    //  · Rayleigh — wavelength-selective molecular scattering (βb>βg>βr)
    //    builds the deep blue zenith, the airmass-whitened horizon and,
    //    through the sun's own slanted transmittance, the entire sunset
    //    palette (orange horizon under a purple-blue upper sky) with no
    //    hand-placed gradient anywhere;
    //  · Mie — aerosol forward scattering (Henyey–Greenstein, g = 0.76):
    //    the warm aureole hugging the sun, the cinematic haze, the bloom.
    // Everything accumulates in HDR and is graded ONCE through the ACES
    // fit at the end of the pass; the hash dither below kills banding.
    float day = smoothstep(-0.12, 0.35, sunElev);       // 0 night → 1 day
    float dusk = exp(-pow(sunElev * 3.2, 2.0));         // horizon warmth band
    float night = 1.0 - day;

    // Composition (rule of thirds): the celestial bodies never sit on the
    // screen's center line — an azimuth wandering through the middle is
    // nudged to the nearest third, preserving the negative space the UI
    // lives in.
    float azOff = sunAz - 0.5;
    float sunAzC = 0.5 + (azOff >= 0.0 ? 1.0 : -1.0) * clamp(abs(azOff), 0.17, 0.42);

    // Geometry shared by the phase functions and both bodies: aspect-true
    // space (v5) keeps every disc and glow round on any screen.
    float aspect = bounds.w / max(bounds.z, 1.0);
    float2 sunPos = float2(sunAzC, 0.78 - clamp(sunElev, 0.0, 1.0) * 0.55);
    // Legacy anisotropic metric — kept for every directional TINT (cloud
    // rim, fog diffusion, shadow taps) tuned against it.
    float dSun = distance(uv * float2(1.0, 1.4), sunPos * float2(1.0, 1.4));
    float2 auv = float2(uv.x, uv.y * aspect);
    float2 sunA = float2(sunPos.x, sunPos.y * aspect);
    float dSunA = distance(auv, sunA);
    float lowSun = smoothstep(0.45, 0.05, sunElev);

    // Airmass along the view ray and along the sun's path (Kasten-shaped:
    // ~1 overhead, ~10 grazing the horizon).
    float sinView = sin(mix(1.35, 0.02, uv.y));
    float amView = 1.0 / (sinView + 0.09);
    float amSun  = 1.0 / (max(sunElev, 0.015) + 0.09);
    const float3 betaR = float3(0.115, 0.266, 0.650);   // relative Rayleigh β
    // Sunlight surviving its slanted path — golden then red, for free.
    float3 Tsun = exp(-betaR * amSun * 0.60);
    // Light feeding the air the eye looks THROUGH: horizon rays arrive
    // through reddened air, overhead rays barely any — sunset lives low
    // while the zenith keeps its cool blue-violet upper sky.
    float horizonness = clamp((amView - 1.0) * 0.14, 0.0, 1.0);
    float3 incident = exp(-betaR * amSun * 0.60 * mix(0.30, 1.05, horizonness));
    // In-scatter saturates with airmass: aerial perspective and the pale
    // horizon are consequences of the solve, not a bolted-on whiten.
    float3 inScatter = 1.0 - exp(-betaR * amView * 0.75);

    // Phase functions, from the screen-space angle to the sun.
    float cosTheta = cos(min(dSunA * 2.6, 3.14159));
    float phR = 0.64 * (1.0 + cosTheta * cosTheta);
    const float gHG = 0.76;
    float phM = (1.0 - gHG * gHG) / pow(1.0 + gHG * gHG - 2.0 * gHG * cosTheta, 1.5);

    // HDR assembly: the day solve ↔ a soft blue-gray night, sun-blended.
    float3 dayHDR = inScatter * incident * phR * 1.18;
    dayHDR += Tsun * phM * 0.020 * (1.0 + horizonness * 1.5)
            * (1.0 - cloudiness * 0.55);                // cinematic haze veil
    float3 nightHDR = float3(0.012, 0.018, 0.035)
                    + float3(0.028, 0.042, 0.070) * horizonness;
    float3 sky = mix(nightHDR, dayHDR, day);

    // Belt of Venus: with the sun just below the horizon, the sky OPPOSITE
    // it wears a rosy band over the rising blue-grey earth shadow — the
    // twilight signature real skies never skip.
    float below = smoothstep(0.02, -0.10, sunElev) * (1.0 - smoothstep(-0.10, -0.22, sunElev));
    if (below > 0.01) {
        float antiSide = smoothstep(0.2, 0.9, 1.0 - abs(uv.x - (1.0 - sunAzC)));
        float venusBand = exp(-pow((uv.y - 0.78) * 8.0, 2.0));
        float shadowBand = smoothstep(0.82, 1.0, uv.y);
        sky += float3(0.80, 0.42, 0.42) * venusBand * antiSide * below * (1.0 - cloudiness * 0.7) * 0.16;
        sky = mix(sky, float3(0.16, 0.19, 0.28), shadowBand * antiSide * below * 0.22);
    }

    // ---- Sun (v5 geometry, v6 light): the disc wears the PHYSICAL colour
    // of the surviving sunlight (Tsun), so it whitens high and reddens
    // into the horizon on the same curve as the sky around it. Low sun:
    // the glow flattens into a wide band hugging the horizon — never a
    // round blob sitting "on the ground".
    float2 gm = (auv - sunA) * float2(1.0 - lowSun * 0.45, 1.0 + lowSun * 1.3);
    float dGlow = length(gm);
    float3 sunCol = Tsun / max(max(Tsun.r, max(Tsun.g, Tsun.b)), 1e-3);
    // The DISC exists only above the horizon under a mostly-clear sky.
    float discVis = day * smoothstep(-0.04, 0.03, sunElev)
                  * (1.0 - smoothstep(0.30, 0.70, cloudiness));
    float sunCore = smoothstep(0.034, 0.023, dSunA);
    float limb = 1.0 - 0.30 * smoothstep(0.012, 0.032, dSunA);
    // Layered bloom accumulated in HDR — the ACES rolloff at the end
    // compresses it exactly the way a lens does (very subtle, per brief).
    float bloom = exp(-dGlow * dGlow * 160.0) * 1.00 + exp(-dGlow * dGlow * 20.0) * 0.36;
    sky += sunCol * (sunCore * limb * discVis * 1.30
                   + bloom * day * (1.0 - cloudiness * 0.55) * 0.60);
    // Through an overcast deck the sun survives as a broad diffuse patch.
    sky += sunCol * exp(-dGlow * dGlow * 9.0) * day
         * smoothstep(0.30, 0.85, cloudiness) * 0.12;

    // Light rays through the haze (brief): slow radial shafts carved by
    // noise in the ANGLE around a low sun — they breathe with the field's
    // own drift, never the spokes of a painted wheel.
    if (day > 0.02 && lowSun > 0.05) {
        float2 dirS = (auv - sunA) / max(dSunA, 1e-4);
        float shaft = fbm(dirS * 2.4 + float2(t * 0.010, -t * 0.007));
        shaft = smoothstep(0.52, 0.86, shaft);
        float rayAmt = shaft * exp(-dSunA * 2.4) * lowSun * day
                     * (0.30 + 0.70 * cloudiness)
                     * (1.0 - smoothstep(0.72, 1.0, cloudiness));
        sky += Tsun * rayAmt * 0.30;
    }

    // Floating dust in the beam (brief): sparse illuminated motes adrift
    // through the sunlit air — alive inside the bloom, subliminal
    // everywhere else.
    if (day > 0.3 && cloudiness < 0.6) {
        float2 mp = auv * 34.0 + float2(t * 0.045, t * 0.021);
        float2 mc = floor(mp);
        float mh = hash12(mc);
        float mote = step(0.986, mh);
        float md = length(fract(mp) - float2(0.30 + 0.40 * fract(mh * 17.0),
                                             0.30 + 0.40 * fract(mh * 29.0)));
        float dusty = mote * smoothstep(0.10, 0.0, md)
                    * (0.5 + 0.5 * sin(t * (0.5 + mh) + mh * 40.0));
        sky += Tsun * dusty * exp(-dSunA * 3.0) * day * (1.0 - cloudiness) * 0.10;
    }

    if (night > 0.01) {
        // Distant-glow warmth hugging the night horizon (v4) — inhabited
        // skies are never cold all the way to the ground.
        sky += float3(0.085, 0.065, 0.045) * night * pow(uv.y, 3.5) * 0.35;

        // Stars v3 (brief): round dots with per-star size, brightness and
        // a SLOW twinkle cadence — and they fade toward the horizon, where
        // the thicker air of the same solve swallows them.
        float starAlt = smoothstep(1.02, 0.50, uv.y);
        float2 sp = uv * float2(160.0, 260.0);
        float2 sc = floor(sp);
        float sh = hash12(sc);
        float s1 = step(0.9955, sh);
        float srad = 0.10 + 0.22 * fract(sh * 57.0);
        float sdot = smoothstep(srad, 0.0, length(fract(sp) - 0.5));
        float tw = 0.55 + 0.45 * sin(t * (0.55 + fract(sh * 91.0) * 1.5) + sh * 40.0);
        float2 sp2 = uv * float2(70.0, 120.0) + 31.7;
        float2 sc2 = floor(sp2);
        float sh2 = hash12(sc2);
        float s2 = step(0.997, sh2);
        float sdot2 = smoothstep(0.30, 0.0, length(fract(sp2) - 0.5));
        // Per-star colour temperature: real fields run blue-white → warm.
        float3 starTint = mix(float3(0.72, 0.83, 1.0), float3(1.0, 0.90, 0.72),
                              fract(sh * 23.0));
        sky += (starTint * s1 * sdot * 0.8 * tw
              + float3(0.9, 0.93, 1.0) * s2 * sdot2 * 1.0) * night
             * (1.0 - cloudiness) * starAlt;

        // The Milky Way: a faint tilted dust band, fBM-mottled.
        float mwBand = exp(-pow((uv.y - (0.55 - uv.x * 0.25)) * 6.0, 2.0));
        float mw = fbm(float2(uv.x * 3.0 + uv.y * 1.5, uv.y * 6.0 - uv.x * 2.0));
        sky += float3(0.55, 0.60, 0.75) * mw * mwBand * night * (1.0 - cloudiness) * 0.055 * starAlt;

        // Moon v3: round disc (aspect-true space), phase-correct
        // terminator, maria mottling, soft limb, faint earthshine — and it
        // HIDES behind an overcast deck instead of shining through it.
        // Rule of thirds: it rides the upper third, opposite the sun.
        float2 moonPos = float2(1.0 - sunAzC, 0.24);
        float2 moonA = float2(moonPos.x, moonPos.y * aspect);
        float dmA = distance(auv, moonA);
        float mR = 0.042;
        float disc = smoothstep(mR, mR * 0.90, dmA);
        float phaseOff = (moonPhase - 0.5) * 0.085;
        float dTerm = distance(auv, moonA + float2(phaseOff, 0.0));
        float lit = disc * smoothstep(mR * 0.84, mR * 1.0,
                                      dTerm + (moonPhase < 0.5 ? 0.003 : -0.003));
        float maria = 0.80 + 0.20 * smoothstep(0.25, 0.75, fbm((auv - moonA) * 90.0 + 3.3));
        float glowM = exp(-dmA * dmA * 220.0);
        float moonVis = night * (1.0 - smoothstep(0.20, 0.65, cloudiness));
        sky += (float3(0.93, 0.93, 0.89) * lit * maria
              + float3(0.30, 0.33, 0.40) * disc * (1.0 - lit) * 0.22
              + float3(0.60, 0.65, 0.78) * glowM * 0.28) * moonVis;

        // Scattering halo (brief): a broad ring of moonlight diffused by
        // the atmosphere, its brightness breathing almost imperceptibly —
        // the glow of air, never a sticker ring.
        float pulse = 1.0 + 0.07 * sin(t * 0.23);
        float halo = exp(-pow((dmA - 0.085) * 24.0, 2.0)) * 0.085
                   + exp(-dmA * dmA * 60.0) * 0.10;
        sky += float3(0.55, 0.62, 0.80) * halo * pulse * moonVis;

        // Thin atmospheric mist (brief): a cool veil breathing over the
        // night horizon on its own slow clock.
        float mist = fbm(float2(uv.x * 3.0 + t * 0.006, uv.y * 9.0 - t * 0.002));
        sky += float3(0.10, 0.13, 0.18) * mist
             * smoothstep(0.60, 1.0, uv.y) * night * (1.0 - cloudiness * 0.6) * 0.16;
    }

    // ---- Clouds v2: domain-warped fBM — billowing shapes instead of
    // static fuzz — with a vertical habitat band, horizon perspective and
    // a one-tap self-shadow lit from the sun's side. Fully skipped on a
    // clear sky (the expensive path costs nothing when there is nothing).
    float driftBoost = 1.0 + windAbs * 2.4;
    if (cloudiness > 0.02) {
        // Perspective: features compress toward the horizon (distance).
        float2 cuv = float2(uv.x * 1.6 * mix(1.0, 2.1, uv.y), uv.y * 3.2);
        // Advection carries a whisper of vertical drift — real decks never
        // slide on a perfectly horizontal rail.
        float2 flow = float2(t * 0.012 * driftBoost * driftSign, t * 0.0025);
        // Domain warp with its OWN slow clock, decoupled from the advection:
        // the warp field creeping at a different rate is what makes the
        // shapes continuously MORPH — grow, split, dissolve — instead of
        // translating rigidly like a printed drawing ("nu doar desene").
        float2 warpP = cuv * 1.9 + flow * 0.8 + float2(t * 0.006, -t * 0.004);
        float2 warp = float2(fbm(warpP), fbm(warpP + float2(5.2, 1.3))) - 0.5;
        float2 q = cuv * 2.2 + warp * 0.9 + flow;
        // Billowed detail: folding the octave (1-|2x-1|) turns smooth noise
        // into cauliflower lobes — the cumulus signature the plain sum lacks.
        // Counter-drifted on a third clock so the fine lobes churn against
        // the large forms the way real convection does.
        float billow = 1.0 - abs(2.0 * fbm(q * 2.1 + float2(7.0, 3.0)
                                           - flow * 0.35 + float2(-t * 0.004, t * 0.003)) - 1.0);
        float base = fbm5(q) * 0.70 + billow * 0.30;
        // Habitat band: densest mid-sky, thinner overhead and low.
        float bandV = smoothstep(0.02, 0.25, uv.y) * (1.0 - 0.5 * smoothstep(0.75, 1.0, uv.y));
        float deck = smoothstep(1.02 - cloudiness, 1.20 - cloudiness, base) * (0.55 + 0.45 * bandV);
        // Self-shadow: resample toward the sun — where the deck thickens
        // sunward, this pixel sits in its own cloud's shade.
        float toward = fbm(q + normalize(sunPos - uv + float2(1e-3, 1e-3)) * 0.25);
        float lit01 = clamp(0.5 + (base - toward) * 1.6, 0.0, 1.0);
        // Vertical light (v4): tops catch the sky, bases sit in their own
        // shade. Sampling the field BELOW this pixel — denser below means
        // we're near the sunlit crown of the form.
        float below = fbm(q + float2(0.0, 0.45));
        float topLight = clamp(0.5 + (below - base) * 1.3, 0.0, 1.0);
        lit01 = clamp(lit01 * 0.62 + topLight * 0.52, 0.0, 1.0);
        float3 cloudLit  = mix(float3(0.10, 0.11, 0.14), float3(0.99, 0.97, 0.95), day);
        cloudLit = mix(cloudLit, float3(1.0, 0.72, 0.5), dusk * 0.6);
        // Altitude grading: the high deck rides brighter, low scud dimmer —
        // the vertical depth cue flat decks lack.
        cloudLit *= 0.92 + 0.14 * (1.0 - uv.y);
        float3 cloudDark = cloudLit * (day > 0.5 ? 0.55 : 0.45);
        // Beer–Lambert cover (v4): opacity saturates exponentially with
        // optical depth — soft translucent fringes, dense solid cores,
        // never a linear "sticker" edge.
        float cover = 1.0 - exp(-deck * (1.7 + 1.3 * cloudiness));
        sky = mix(sky, mix(cloudDark, cloudLit, lit01), cover * 0.92);
        // Silver lining: cloud EDGES facing the sun catch its light — the
        // rim brightens where the deck thins toward the glow.
        float rim = smoothstep(0.02, 0.22, deck) * (1.0 - smoothstep(0.22, 0.55, deck));
        sky += float3(1.0, 0.95, 0.85) * rim * exp(-dSun * dSun * 14.0) * day * 0.30;
        // Dusk translucency: thin edges glow ember-warm when the sun sits
        // low behind them — sunset's signature made of scattering, not paint.
        sky += float3(1.0, 0.55, 0.35) * rim * dusk * 0.30;
        // Moonlit lining: at night the same edges catch the moon instead.
        float2 moonP = float2(1.0 - sunAzC, 0.24);
        float dMoonC = distance(uv * float2(1.0, 1.5), moonP * float2(1.0, 1.5));
        sky += float3(0.78, 0.84, 0.95) * rim * exp(-dMoonC * dMoonC * 10.0)
             * (1.0 - day) * 0.14;
    }
    // Low-sun flare: a warm horizontal scattering streak at golden hour.
    float flare = exp(-pow((uv.y - sunPos.y) * 22.0, 2.0)) * exp(-abs(uv.x - sunAzC) * 2.6);
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

    // ---- Rainbow v2 (F4, IMG feedback "nu peste tot"): a real bow is a
    // SEGMENT of the antisolar circle, not a full hoop painted across the
    // sky. This one is an off-crown partial arc whose ends dissolve into
    // the rain haze, ADDED as light (bows are scattered sunlight, they
    // never repaint the sky), patchy where the rain curtain thins, with
    // the faint reversed secondary and the brighter sky inside the
    // primary that real optics produce.
    if (rainbow > 0.005) {
        float2 arcC = float2(1.0 - sunAzC, 1.35);
        float2 rel = (uv - arcC) * float2(1.0, 1.2);
        float dArc = length(rel);
        if (dArc > 0.52 && dArc < 1.02) {
            // 0 at the arc's crown, ±π/2 at the horizon feet.
            float ang = atan2(rel.x, -rel.y);
            // Partial segment: one shoulder only (~a third of the hoop),
            // soft-edged; the side leans away from the sun's azimuth.
            float lean = (sunAzC - 0.5) * 0.9;
            float span = smoothstep(1.05, 0.30, abs(ang - lean * 1.2 - 0.28));
            // Ends fade harder near the ground — bows sink into the haze.
            float footFade = smoothstep(1.35, 0.55, abs(ang));
            // Patchiness: the bow lives only where the rain curtain does.
            float curtain = 0.55 + 0.45 * fbm(float2(ang * 2.2 + 3.7, dArc * 5.0 + t * 0.01));
            float gate = rainbow * day * (1.0 - cloudiness * 0.5)
                       * span * footFade * curtain;
            if (gate > 0.001) {
                // Primary bow.
                float band = (dArc - 0.72) / 0.055;
                if (band > 0.0 && band < 1.0) {
                    float3 spectral = 0.5 + 0.5 * cos(6.28318 * (band * 0.9 + float3(0.00, 0.33, 0.67)));
                    sky += spectral * sin(band * 3.14159) * gate * 0.16;
                }
                // Secondary bow: larger radius, reversed order, much fainter.
                float band2 = (dArc - 0.90) / 0.05;
                if (band2 > 0.0 && band2 < 1.0) {
                    float3 spectral2 = 0.5 + 0.5 * cos(6.28318 * ((1.0 - band2) * 0.9 + float3(0.00, 0.33, 0.67)));
                    sky += spectral2 * sin(band2 * 3.14159) * gate * 0.05;
                }
                // Inside the primary the sky brightens; Alexander's band
                // between the bows stays quietly darker.
                sky += float3(0.9, 0.92, 0.95) * smoothstep(0.72, 0.60, dArc) * gate * 0.05;
                sky *= 1.0 - smoothstep(0.755, 0.78, dArc) * smoothstep(0.92, 0.90, dArc) * gate * 0.10;
            }
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
        float2 px = auv;   // aspect-true space, shared with the sun/moon
        float2 drops = lensDrops(px, t, rain, float2(tiltX, tiltY));
        sky = sky * (1.0 - drops.x * 0.16) + float3(0.9, 0.94, 1.0) * drops.y * 0.35;
    }

    // Lens vignette — quiet cinematic edge falloff, static.
    float vig = 1.0 - 0.22 * pow(distance(uv, float2(0.5, 0.55)) * 1.3, 2.0);
    sky *= max(vig, 0.0);

    // Filmic rolloff (v4, cheap ACES fit): photographic highlight
    // compression and shadow depth — sun bloom, snow and lightning stop
    // clipping to flat white, mids gain the gentle contrast of a camera
    // curve instead of raw linear paint.
    float3 tx = sky * 1.04;
    sky = clamp((tx * (2.51 * tx + 0.03)) / (tx * (2.43 * tx + 0.59) + 0.14), 0.0, 1.0);

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
