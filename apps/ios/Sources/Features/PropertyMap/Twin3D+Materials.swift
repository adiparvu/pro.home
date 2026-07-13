import SwiftUI
import SceneKit
import UIKit

// MARK: - Twin 3D cinematic support (T1.5)
//
// Everything the cinematic pass needs that is NOT scene-graph assembly:
// the approximate sun model (honest, documented math), the mood palette,
// the once-generated sky/environment images, PBR material factories, the
// firefly particle system, and the highlight vocabulary that will later be
// driven by Pulsul device events.
//
// Honesty notes (constitution):
// - The sun position is a standard low-precision solar approximation from
//   the device clock (+ the property's stored latitude when it exists). The
//   aerial photo's rotation relative to true north is UNKNOWN, so azimuth
//   is scene-relative: the light moves plausibly through the day, it does
//   not claim surveyed shadow directions.
// - The RENDERED sun elevation is aesthetically clamped (18°–50°) while the
//   sun is up so the maquette always keeps readable shadows; the real
//   computed elevation still decides the mood (dawn/day/dusk/night).
// - Nothing here invents data: no fake windows, no imaginary alerts.

// MARK: - Highlight style (T1.5 → Pulsul bridge)

/// The zone-glow vocabulary `Twin3DCoordinator.highlight(zoneID:style:)`
/// accepts. Shipped now so device events (Pulsul) can drive it later; no
/// trigger is wired in-app yet because no threshold model exists — wiring a
/// fake one would violate the honesty law.
enum Twin3DHighlightStyle: Equatable {
    case none
    /// Amber pulsing emissive — "needs attention".
    case warning
    /// Red pulsing emissive — "act now".
    case alert

    var pulseColor: UIColor? {
        switch self {
        case .none:    return nil
        case .warning: return UIColor(Color.smartAmber)
        case .alert:   return UIColor(Color.brandDanger)
        }
    }
}

// MARK: - Sun model (approximate, honest)

/// Approximate solar position + the lighting mood derived from it.
///
/// Math (standard low-precision approximation, no dependency):
/// - declination δ = −23.44° · cos(2π(N+10)/365), N = day of year
/// - hour angle  H = 15°·(localHour − 12)   (equation of time and the
///   longitude/timezone offset are ignored — ±~20 min, irrelevant here)
/// - sin(el) = sinφ·sinδ + cosφ·cosδ·cosH, φ = property latitude or 45°
/// - cos(az) = (sinδ − sin(el)·sinφ) / (cos(el)·cosφ), mirrored after noon
struct Twin3DSunModel {
    enum Mood { case dawn, day, dusk, night }

    let mood: Mood
    /// True computed elevation in degrees (may be negative at night).
    let elevationDegrees: Double
    /// Compass-style azimuth in degrees, scene-relative (photo north unknown).
    let azimuthDegrees: Double

    static func compute(at date: Date = Date(), latitude: Double?) -> Twin3DSunModel {
        let calendar = Calendar.current
        let dayOfYear = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 172)
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = Double(parts.hour ?? 12) + Double(parts.minute ?? 0) / 60

        let phi = (latitude ?? 45) * .pi / 180        // 45° fallback: mid-latitude
        let declination = -23.44 * cos(2 * .pi * (dayOfYear + 10) / 365) * .pi / 180
        let hourAngle = (hour - 12) * 15 * .pi / 180

        let sinElevation = sin(phi) * sin(declination)
            + cos(phi) * cos(declination) * cos(hourAngle)
        let elevation = asin(min(max(sinElevation, -1), 1))
        let cosAzimuth = (sin(declination) - sinElevation * sin(phi))
            / max(cos(elevation) * cos(phi), 1e-6)
        var azimuth = acos(min(max(cosAzimuth, -1), 1))
        if hourAngle > 0 { azimuth = 2 * .pi - azimuth }   // afternoon → west

        let elevationDegrees = elevation * 180 / .pi
        let mood: Mood
        if elevationDegrees < -5 {
            mood = .night
        } else if elevationDegrees < 10 {
            mood = hourAngle < 0 ? .dawn : .dusk
        } else {
            mood = .day
        }
        return Twin3DSunModel(mood: mood,
                              elevationDegrees: elevationDegrees,
                              azimuthDegrees: azimuth * 180 / .pi)
    }

    /// Elevation the light actually renders at. Daytime is clamped to
    /// 18°–50° so the maquette always throws readable shadows (an aesthetic
    /// choice, documented — the honest elevation is `elevationDegrees`).
    /// At night the "sun" is the moon at a fixed pleasant 38°.
    var renderedElevationDegrees: Double {
        mood == .night ? 38 : min(max(elevationDegrees, 18), 50)
    }

    /// At night the moon rises roughly opposite the set sun — a mood choice,
    /// not an ephemeris claim.
    var renderedAzimuthDegrees: Double {
        mood == .night
            ? (azimuthDegrees + 180).truncatingRemainder(dividingBy: 360)
            : azimuthDegrees
    }
}

// MARK: - Mood palette

extension Twin3DSunModel.Mood {
    /// Sky gradient stops: zenith → horizon → below-horizon dark.
    var skyTop: UIColor {
        switch self {
        case .dawn:  return UIColor(red: 0.14, green: 0.11, blue: 0.24, alpha: 1)
        case .day:   return UIColor(red: 0.19, green: 0.23, blue: 0.33, alpha: 1)
        case .dusk:  return UIColor(red: 0.17, green: 0.09, blue: 0.21, alpha: 1)
        case .night: return UIColor(red: 0.03, green: 0.03, blue: 0.09, alpha: 1)
        }
    }

    var skyHorizon: UIColor {
        switch self {
        case .dawn:  return UIColor(red: 0.74, green: 0.44, blue: 0.30, alpha: 1)
        case .day:   return UIColor(red: 0.56, green: 0.50, blue: 0.42, alpha: 1)
        case .dusk:  return UIColor(red: 0.68, green: 0.33, blue: 0.14, alpha: 1)
        case .night: return UIColor(red: 0.10, green: 0.11, blue: 0.22, alpha: 1)
        }
    }

    var skyBase: UIColor {
        switch self {
        case .dawn:  return UIColor(red: 0.05, green: 0.04, blue: 0.07, alpha: 1)
        case .day:   return UIColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1)
        case .dusk:  return UIColor(red: 0.05, green: 0.03, blue: 0.06, alpha: 1)
        case .night: return UIColor(red: 0.02, green: 0.02, blue: 0.04, alpha: 1)
        }
    }

    /// The directional light's color (moonlight when night).
    var sunColor: UIColor {
        switch self {
        case .dawn:  return UIColor(red: 1.00, green: 0.78, blue: 0.55, alpha: 1)
        case .day:   return UIColor(red: 1.00, green: 0.96, blue: 0.90, alpha: 1)
        case .dusk:  return UIColor(red: 1.00, green: 0.70, blue: 0.42, alpha: 1)
        case .night: return UIColor(red: 0.70, green: 0.78, blue: 0.95, alpha: 1)
        }
    }

    var sunIntensity: CGFloat {
        switch self {
        case .dawn:  return 820
        case .day:   return 1000
        case .dusk:  return 850
        case .night: return 320
        }
    }

    var ambientColor: UIColor {
        switch self {
        case .dawn:  return UIColor(red: 0.55, green: 0.50, blue: 0.55, alpha: 1)
        case .day:   return UIColor(red: 0.62, green: 0.60, blue: 0.58, alpha: 1)
        case .dusk:  return UIColor(red: 0.55, green: 0.44, blue: 0.40, alpha: 1)
        case .night: return UIColor(red: 0.35, green: 0.38, blue: 0.52, alpha: 1)
        }
    }

    var ambientIntensity: CGFloat {
        switch self {
        case .dawn:  return 300
        case .day:   return 380
        case .dusk:  return 300
        case .night: return 170
        }
    }

    /// `scene.lightingEnvironment.intensity` — the PBR fill strength.
    var environmentIntensity: CGFloat {
        switch self {
        case .dawn:  return 0.85
        case .day:   return 1.0
        case .dusk:  return 0.8
        case .night: return 0.45
        }
    }

    var shadowOpacity: CGFloat {
        switch self {
        case .dawn:  return 0.50
        case .day:   return 0.45
        case .dusk:  return 0.55
        case .night: return 0.60
        }
    }
}

// MARK: - Atmosphere assets + material factories

@MainActor
enum Twin3DAtmosphere {

    // MARK: Once-generated images (tiny, cached per mood)

    private static var skyCache: [Twin3DSunModel.Mood: UIImage] = [:]
    private static var environmentCache: [Twin3DSunModel.Mood: UIImage] = [:]

    /// The scene background: a vertical mood gradient, generated once and
    /// stretched by SceneKit across the view (a single non-cube image is
    /// drawn screen-space, which is exactly what a sky gradient wants).
    static func skyImage(for mood: Twin3DSunModel.Mood) -> UIImage {
        if let cached = skyCache[mood] { return cached }
        let image = verticalGradient(size: CGSize(width: 8, height: 512),
                                     colors: [mood.skyTop, mood.skyHorizon, mood.skyBase],
                                     locations: [0, 0.62, 1])
        skyCache[mood] = image
        return image
    }

    /// The PBR lighting environment: the same gradient as a small 2:1
    /// (equirectangular) image — zenith at the top row, horizon mid-frame —
    /// so physically-based materials get a soft, mood-correct ambient fill.
    static func environmentImage(for mood: Twin3DSunModel.Mood) -> UIImage {
        if let cached = environmentCache[mood] { return cached }
        let image = verticalGradient(size: CGSize(width: 64, height: 32),
                                     colors: [mood.skyTop, mood.skyHorizon, mood.skyBase],
                                     locations: [0, 0.5, 1])
        environmentCache[mood] = image
        return image
    }

    /// Soft radial dot for the firefly particles (generated once).
    static let particleGlowImage: UIImage = {
        let size = CGSize(width: 32, height: 32)
        return UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor.white.cgColor,
                          UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: colors, locations: [0, 1]) else { return }
            let center = CGPoint(x: 16, y: 16)
            context.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                                 endCenter: center, endRadius: 16, options: [])
        }
    }()

    private static func verticalGradient(size: CGSize, colors: [UIColor],
                                         locations: [CGFloat]) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            let cgColors = colors.map(\.cgColor) as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: cgColors, locations: locations) else { return }
            context.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: 0, y: size.height),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
    }

    // MARK: PBR materials

    /// The aerial photo as a matte, physically-based ground so it takes the
    /// sun's shadow and the environment fill honestly.
    static func groundMaterial(image: UIImage) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = image
        material.roughness.contents = 0.9
        material.metalness.contents = 0.0
        material.isDoubleSided = false
        return material
    }

    /// Plinth: dark brushed-metal sides, matte dark top/bottom.
    /// SCNBox material order: [front +Z, right +X, back −Z, left −X, top, bottom].
    static func plinthMaterials() -> [SCNMaterial] {
        let side = SCNMaterial()
        side.lightingModel = .physicallyBased
        side.diffuse.contents = UIColor(red: 0.16, green: 0.12, blue: 0.10, alpha: 1)
        side.metalness.contents = 0.55
        side.roughness.contents = 0.35

        let flat = SCNMaterial()
        flat.lightingModel = .physicallyBased
        flat.diffuse.contents = UIColor(red: 0.10, green: 0.08, blue: 0.07, alpha: 1)
        flat.metalness.contents = 0.2
        flat.roughness.contents = 0.6

        return [side, side, side, side, flat, flat]
    }

    /// The thin warm emissive seam under the plinth's top edge.
    static func rimMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(red: 0.12, green: 0.08, blue: 0.05, alpha: 1)
        material.metalness.contents = 0.3
        material.roughness.contents = 0.4
        material.emission.contents = UIColor(Color.smartAmber)
        material.emission.intensity = 0.45
        return material
    }

    /// Zone prism: glass-like PBR — fresnel falls out of the physically
    /// based model (no manual fresnelExponent needed), `.dualLayer` renders
    /// back faces then front faces so the volume reads as glass, and a soft
    /// emissive of the zone's own color keeps it legible at night.
    static func prismMaterial(tint: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = tint
        material.roughness.contents = 0.15
        material.metalness.contents = 0.08
        material.transparency = 0.65
        material.transparencyMode = .dualLayer
        material.isDoubleSided = false
        material.emission.contents = tint
        material.emission.intensity = 0.25
        return material
    }

    /// The flat base ring under a prism — SCNShape has no chamfer, so a
    /// slightly outset, 0.05-tall second outline approximates a bevel.
    static func ringMaterial(tint: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = tint
        material.metalness.contents = 0.3
        material.roughness.contents = 0.3
        material.emission.contents = tint
        material.emission.intensity = 0.5
        return material
    }

    // MARK: Fireflies / ambient dust

    /// ≤ ~40 concurrent particles (birthRate 4.5 × lifespan ~8 ≈ 36): tiny,
    /// warm, slow — dust by day, fireflies by night. Additive, unlit, so the
    /// GPU cost is a handful of blended quads.
    static func fireflies(spanX: CGFloat, spanZ: CGFloat) -> SCNParticleSystem {
        let system = SCNParticleSystem()
        system.birthRate = 4.5
        system.particleLifeSpan = 8
        system.particleLifeSpanVariation = 2
        system.emitterShape = SCNBox(width: spanX, height: 1.4, length: spanZ, chamferRadius: 0)
        system.birthLocation = .volume
        system.particleImage = particleGlowImage
        system.particleColor = UIColor(red: 1.0, green: 0.76, blue: 0.45, alpha: 1)
        system.particleColorVariation = SCNVector4(0.03, 0.05, 0.08, 0)
        system.particleSize = 0.045
        system.particleSizeVariation = 0.02
        system.particleIntensity = 0.75
        system.particleIntensityVariation = 0.35
        system.particleVelocity = 0.05
        system.particleVelocityVariation = 0.05
        system.emittingDirection = SCNVector3(0, 1, 0)
        system.spreadingAngle = 180
        system.acceleration = SCNVector3(0, 0.008, 0)
        system.dampingFactor = 0.3
        system.blendMode = .additive
        system.isLightingEnabled = false
        system.isAffectedByGravity = false
        return system
    }
}
