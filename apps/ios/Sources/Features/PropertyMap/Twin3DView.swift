import SwiftUI
import SceneKit
import UIKit

// MARK: - Twin 3D (T1.5) — the Digital Twin's primary face, cinematic pass
//
// A real-time SceneKit maquette built from the property's OWN data: the same
// bundled aerial photo the 2D canvas renders (via `AerialImagePyramid`)
// textured onto a physically-based ground slab, and every zone with a drawn
// `imagePolygon` extruded into a glass prism in the zone's own color, capped
// by a refined pin (torus ring + emissive orb) and a billboarded name label
// on a dark capsule. Tapping a zone opens its Estate OS space page
// (`SpaceDetailView`).
//
// T1.5 cinematic layer (all support types in `Twin3D+Materials.swift`):
// - A mood sky (dawn/day/dusk/night) from an approximate, documented sun
//   model — device clock + the property's stored latitude when available.
//   The same tiny gradient doubles as `lightingEnvironment` for PBR fill.
// - A low warm sun with soft deferred shadows so prisms and the plinth
//   throw long shadows across the photo; moonlight at night.
// - HDR + subtle bloom (emissives glow), gentle depth of field focused on
//   the slab center, light vignetting. Motion blur stays 0 — gestures crisp.
// - Fireflies/dust particles and a pond-prism shimmer, both OFF under
//   Reduce Motion or Low Power Mode.
// - `highlight(zoneID:style:)` — the Pulsul bridge (see the hook's docs).
//
// Honest by construction (honesty law):
// - Nothing here is invented: no fake terrain, no guessed elevations. The
//   ground is the real photo; prisms exist only for zones the user actually
//   drew in 2D; heights are uniform because the app knows no real heights.
// - The sun is an approximation and says so (`Twin3DSunModel` docs); the
//   photo's north is unknown, so light direction is scene-relative mood,
//   not a surveyed shadow claim.
// - No aerial photo decodable → an empty state that says so; no zones → the
//   photo slab alone plus a hint pointing at the 2D drawing flow.
// - No invented alerts: the highlight hook ships dormant until a real
//   threshold model exists.
//
// Performance:
// - The scene graph is rebuilt ONLY when the data signature changes (image
//   identity + zone geometry/colors + effects flag + lighting-mood bucket),
//   never per frame.
// - `rendersContinuously` stays false — SceneKit still redraws while a
//   CAAnimation (shimmer/highlight pulse) runs, then goes idle — EXCEPT
//   while the particle system is active, which needs a live simulation.
//   That power trade is gated: Reduce Motion or Low Power Mode → no
//   particles, no continuous rendering, idle twin costs ~0 GPU again.
// - Max 8 pin omni-lights (deterministic: first 8 zones); beyond that pins
//   keep the emissive orb but add no light, so the forward renderer's
//   per-object light budget is never blown.
// - 4× MSAA, the default Metal renderer, and a fixed medium pyramid level
//   (≥2048 px) as the ground texture — crisp without decoding the native
//   drone photo into hundreds of MB of texture.
// - No idle auto-orbit at all; the only camera animation is the one-shot
//   intro dolly, skipped under Reduce Motion.
//
// T1 scope note: only ZONES get 3D presence. Element/object pins, RoomPlan /
// LiDAR volumes, and real heights are deliberately out (T2+).

struct Twin3DView: View {
    /// Switches the twin back to the full legacy 2D experience.
    let onShow2D: () -> Void

    @Environment(PropertyService.self) private var propertyService
    @Environment(PropertyZoneService.self) private var zoneService
    @Environment(PropertyElementService.self) private var elementService
    @Environment(CurrencyService.self) private var currencyService
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var aerialImage: UIImage?
    @State private var aerialLoadFinished = false
    @State private var selectedZone: PropertyZone?
    @State private var showZonesList = false
    @State private var showObjectsList = false
    @State private var showInsights = false
    @State private var showHealth = false

    /// Value snapshots of every zone that has a drawn image polygon — the
    /// scene's one input besides the photo. Zones without an `imagePolygon`
    /// are honestly absent from 3D (they still live in the lists).
    private var zones3D: [Twin3DZone] {
        zoneService.zones.compactMap { zone in
            guard zone.hasImageShape else { return nil }
            return Twin3DZone(id: zone.id, name: zone.name,
                              colorHex: zone.colorHex, points: zone.imagePoints,
                              kind: zone.resolvedSpaceKind)
        }
    }

    /// Ambient life (fireflies, pond shimmer) is a pure garnish — the first
    /// things to go when the user asked for less motion or the device asked
    /// for less power. Checked per SwiftUI update, so toggling Low Power
    /// Mode takes effect on the next re-render.
    private var ambientEffectsAllowed: Bool {
        !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var body: some View {
        ZStack {
            // The warm smart-home sky behind the transparent scene view.
            SmartHomeBackdrop(photoSource: propertyService.primary?.photoUrl)

            if propertyService.primary == nil {
                EmptyStateView(
                    icon: "photo.on.rectangle.angled",
                    title: "No property yet",
                    message: "Add a property to see its Digital Twin."
                )
                .environment(\.colorScheme, .dark)
            } else if let image = aerialImage {
                Twin3DSceneView(
                    aerialImage: image,
                    zones: zones3D,
                    animateIntro: !reduceMotion,
                    ambientEffects: ambientEffectsAllowed,
                    latitude: propertyService.primary?.latitude,
                    onZoneTap: { id in
                        guard let zone = zoneService.zones.first(where: { $0.id == id }) else { return }
                        HapticFeedback.impact(.light)
                        selectedZone = zone
                    }
                )
                .ignoresSafeArea(edges: .bottom)
                .accessibilityLabel("twin3d_scene_a11y")

                if zones3D.isEmpty {
                    noZonesHint
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .environment(\.colorScheme, .dark)
                }
            } else if aerialLoadFinished {
                // Honest: the twin is built from the aerial photo; without a
                // decodable photo there is no 3D ground to stand on. The 2D
                // view remains the place that owns the photo pipeline.
                EmptyStateView(
                    icon: "photo.on.rectangle.angled",
                    title: "twin3d_no_photo_title",
                    message: "twin3d_no_photo_message",
                    actionLabel: "twin3d_open_2d",
                    action: onShow2D
                )
                .environment(\.colorScheme, .dark)
            } else {
                ProgressView("twin3d_loading")
                    .tint(Color.smartAmber)
                    .foregroundStyle(Color.smartTextSecondary)
                    .environment(\.colorScheme, .dark)
            }

            if propertyService.primary != nil {
                topBar
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .environment(\.colorScheme, .dark)
            }
        }
        .navigationTitle("Digital Twin")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // The same pyramid the 2D canvas uses; a fixed medium level is
            // plenty for a ground texture and avoids the native-size decode.
            aerialImage = await AerialImagePyramid.shared.image(atLeast: 2048, currentWidth: nil)
            aerialLoadFinished = true
        }
        .sheet(item: $selectedZone) { zone in
            SpaceDetailView(zone: zone)
        }
        .sheet(isPresented: $showZonesList) {
            NavigationStack { ZonesListView() }
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showObjectsList) {
            NavigationStack { ObjectsListView() }
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showInsights) {
            TwinInsightsSheet()
                .environment(propertyService)
                .environment(zoneService)
                .environment(elementService)
                .environment(currencyService)
                .environment(appSettings)
        }
        .sheet(isPresented: $showHealth) {
            PropertyHealthDashboardView()
                .environment(elementService)
                .environment(currencyService)
                .environment(appSettings)
                .environment(propertyService)
        }
    }

    // MARK: - Chrome (warm glass, same vocabulary as the 2D twin)

    private var topBar: some View {
        HStack(spacing: 8) {
            // Back to the full 2D experience — nothing was deleted, the
            // twin just changed its face.
            Button {
                HapticFeedback.impact(.medium)
                onShow2D()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "map")
                        .font(AppFont.captionEmphasis)
                    Text(verbatim: "2D")
                        .font(AppFont.captionEmphasis)
                }
                .foregroundStyle(Color.smartTextPrimary)
                .padding(.horizontal, AppSpacing.base).padding(.vertical, 9)
                .background {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(Color.smartGlassFill)
                }
                .overlay(Capsule().strokeBorder(SmartHomeTheme.glassStrokeGradient, lineWidth: 1))
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("twin3d_mode_2d_a11y")

            Spacer()

            Menu {
                Button { showZonesList = true } label: {
                    Label("Zones list", systemImage: "square.stack.3d.up")
                }
                Button { showObjectsList = true } label: {
                    Label("Objects list", systemImage: "cube.box")
                }
            } label: {
                Image(systemName: "list.bullet")
                    .font(AppFont.headline)
                    .foregroundStyle(Color.smartTextPrimary)
                    .frame(width: 40, height: 40)
                    .glassCircle()
            }
            .accessibilityLabel("Lists")

            glassIconButton(icon: "heart.text.square.fill", tint: Color.smartAmber,
                            a11y: "twin3d_health") {
                showHealth = true
            }
            glassIconButton(icon: "sparkles", tint: Color.brandPurple,
                            a11y: "twin3d_insights") {
                showInsights = true
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.top, 10)
    }

    private func glassIconButton(icon: String, tint: Color,
                                 a11y: LocalizedStringKey,
                                 action: @escaping () -> Void) -> some View {
        Button {
            HapticFeedback.impact(.light)
            action()
        } label: {
            Image(systemName: icon)
                .font(AppFont.headline)
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .glassCircle()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a11y)
    }

    /// Honest no-zones state: the maquette is just the photo slab, and this
    /// chip explains why and where zones are born (the 2D drawing flow).
    private var noZonesHint: some View {
        Button {
            HapticFeedback.impact(.light)
            onShow2D()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "pentagon")
                    .font(AppFont.captionEmphasis)
                Text("twin3d_no_zones_hint")
                    .font(AppFont.captionEmphasis)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(Color.smartTextPrimary)
            .padding(.horizontal, AppSpacing.base).padding(.vertical, 10)
            .background {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(Color.smartGlassFill)
            }
            .overlay(Capsule().strokeBorder(SmartHomeTheme.glassStrokeGradient, lineWidth: 1))
            .shadow(color: .black.opacity(SmartHomeTheme.cardShadowOpacity),
                    radius: SmartHomeTheme.cardShadowRadius, y: SmartHomeTheme.cardShadowY)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AppSpacing.xl)
        .padding(.bottom, 40)
    }
}

// MARK: - Scene input snapshot

/// The value snapshot the scene is built from — `Hashable` so the
/// coordinator can cheaply detect "nothing changed, don't rebuild".
struct Twin3DZone: Equatable, Hashable {
    let id: UUID
    let name: String
    let colorHex: String
    /// Normalized 0–1 image coordinates (top-left origin), exactly as the
    /// 2D canvas draws them via `NormPolygon`.
    let points: [ImagePoint]
    /// The zone's resolved Estate OS kind — drives honest garnish only
    /// (pond prisms shimmer), never invented geometry.
    let kind: SpaceKind
}

// MARK: - SceneKit view (UIViewRepresentable)

private struct Twin3DSceneView: UIViewRepresentable {
    let aerialImage: UIImage
    let zones: [Twin3DZone]
    let animateIntro: Bool
    let ambientEffects: Bool
    let latitude: Double?
    let onZoneTap: (UUID) -> Void

    func makeCoordinator() -> Twin3DCoordinator {
        Twin3DCoordinator(onZoneTap: onZoneTap)
    }

    func makeUIView(context: Context) -> SCNView {
        // Default init → Metal renderer wherever Metal exists.
        let view = SCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = false      // custom, clamped gestures below
        view.rendersContinuously = false      // redraw only on change
        view.autoenablesDefaultLighting = false
        view.isOpaque = false

        context.coordinator.attach(to: view)
        context.coordinator.rebuildIfNeeded(image: aerialImage, zones: zones,
                                            animateIntro: animateIntro,
                                            ambientEffects: ambientEffects,
                                            latitude: latitude)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.onZoneTap = onZoneTap
        context.coordinator.rebuildIfNeeded(image: aerialImage, zones: zones,
                                            animateIntro: animateIntro,
                                            ambientEffects: ambientEffects,
                                            latitude: latitude)
    }
}

// MARK: - Coordinator: scene builder + camera rig + gestures

@MainActor
final class Twin3DCoordinator: NSObject {
    var onZoneTap: (UUID) -> Void

    private weak var scnView: SCNView?
    /// Hash of (image identity + zone snapshots + effects flag + lighting
    /// mood bucket): the scene rebuilds only when this changes — never per
    /// frame, never per SwiftUI render.
    private var sceneSignature: Int?
    private var hasBuiltOnce = false

    // T1.5 cinematic state ---------------------------------------------------

    /// Firefly particles need a live simulation loop, so while they exist
    /// the view renders continuously — the ONE deliberate power trade of the
    /// cinematic pass. Gated hard: Reduce Motion or Low Power Mode disables
    /// the particles AND restores pure on-demand rendering. CAAnimations
    /// (shimmer, highlight pulses) do NOT need this flag — SceneKit already
    /// redraws on-demand while an animation is running.
    private static let particlesRequireContinuousRendering = true

    /// Max pins that carry a real omni light. SceneKit's forward renderer
    /// evaluates every light hitting an object per draw; 8 tiny falloff-
    /// limited omnis + sun + ambient stays comfortably inside the budget.
    /// Zones beyond the cap keep the emissive orb (bloom still glows) but
    /// add no light — deterministic, first-come by zone order.
    private static let maxPinLights = 8

    private static let highlightAnimationKey = "twin3d.highlight"
    private static let shimmerAnimationKey = "twin3d.pondShimmer"

    #if DEBUG
    /// Preview switch for the Pulsul highlight pipeline: flip to true to see
    /// the FIRST zone pulse `.warning` on launch. OFF by default and DEBUG-
    /// only — there is no threshold model yet, so shipping any live trigger
    /// would invent an alert (honesty law). Real wiring lands with Pulsul.
    private static let debugHighlightPreview = false
    #endif

    /// Whether ambient garnish (particles, shimmer, pulsing) is allowed for
    /// the current build — false under Reduce Motion / Low Power Mode.
    private var effectsEnabled = false
    /// Zone tint + kind by id, kept so highlights can restore the honest
    /// material and ponds re-arm their shimmer after a highlight clears.
    private var zoneMeta: [UUID: (tint: UIColor, kind: SpaceKind)] = [:]
    /// The highlight each zone is currently asked to show; survives scene
    /// rebuilds (reapplied after construction).
    private var activeHighlights: [UUID: Twin3DHighlightStyle] = [:]

    // Camera rig: target (pans) → yaw (orbits around Y) → pitch (tilts) →
    // camera (dollies along local Z). Gestures mutate angles/distance and
    // write node transforms once — SceneKit re-renders on graph mutation.
    private let targetNode = SCNNode()
    private let yawNode = SCNNode()
    private let pitchNode = SCNNode()
    private let cameraNode = SCNNode()

    private var yaw: Float = -.pi / 10
    private var pitch: Float = -.pi / 4          // the cinematic ~45° opener
    private var distance: Float = 16
    private var minDistance: Float = 6
    private var maxDistance: Float = 40
    /// Half-extents the pan target is clamped to (keeps the slab framed).
    private var panLimit = SIMD2<Float>(7, 7)

    private let minPitch: Float = -1.32          // ~-76°, near top-down
    private let maxPitch: Float = -0.30          // ~-17°, near grazing

    init(onZoneTap: @escaping (UUID) -> Void) {
        self.onZoneTap = onZoneTap
    }

    func attach(to view: SCNView) {
        scnView = view

        let orbit = UIPanGestureRecognizer(target: self, action: #selector(handleOrbit(_:)))
        orbit.minimumNumberOfTouches = 1
        orbit.maximumNumberOfTouches = 1
        view.addGestureRecognizer(orbit)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(pinch)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tap)
    }

    // MARK: Rebuild gate

    func rebuildIfNeeded(image: UIImage, zones: [Twin3DZone], animateIntro: Bool,
                         ambientEffects: Bool, latitude: Double?) {
        // The sun model is a handful of trig calls — cheap enough to compute
        // per update; only a changed MOOD BUCKET (mood + 5° elevation step)
        // triggers a rebuild, so the lighting tracks the clock across
        // re-renders without ever rebuilding per frame.
        let sun = Twin3DSunModel.compute(latitude: latitude)
        var hasher = Hasher()
        hasher.combine(ObjectIdentifier(image))   // pyramid levels are cached & stable
        hasher.combine(zones)
        hasher.combine(ambientEffects)
        hasher.combine(sun.mood)
        hasher.combine(Int(sun.renderedElevationDegrees / 5))
        let signature = hasher.finalize()
        guard signature != sceneSignature else { return }
        sceneSignature = signature
        buildScene(image: image, zones: zones,
                   animateIntro: animateIntro && !hasBuiltOnce,
                   ambientEffects: ambientEffects, sun: sun)
        hasBuiltOnce = true
    }

    // MARK: Scene construction (once per data change)

    private func buildScene(image: UIImage, zones: [Twin3DZone], animateIntro: Bool,
                            ambientEffects: Bool, sun: Twin3DSunModel) {
        guard let scnView else { return }
        let scene = SCNScene()
        effectsEnabled = ambientEffects

        // World scale: the photo's width is 12 units; height follows its
        // aspect so normalized zone coordinates land on real pixels.
        let width: CGFloat = 12
        let aspect = image.size.height / max(image.size.width, 1)
        let height = width * aspect
        let maxDim = Float(max(width, height))

        // Atmosphere: the mood sky as screen-space background, the same
        // low-res gradient as the PBR lighting environment (soft ambience).
        scene.background.contents = Twin3DAtmosphere.skyImage(for: sun.mood)
        scene.lightingEnvironment.contents = Twin3DAtmosphere.environmentImage(for: sun.mood)
        scene.lightingEnvironment.intensity = sun.mood.environmentIntensity

        scene.rootNode.addChildNode(groundNode(image: image, width: width, height: height))
        scene.rootNode.addChildNode(plinthNode(width: width, height: height))
        scene.rootNode.addChildNode(plinthRimNode(width: width, height: height))
        zoneMeta.removeAll(keepingCapacity: true)
        for (index, zone) in zones.enumerated() {
            scene.rootNode.addChildNode(
                zoneNode(zone, width: width, height: height,
                         withPinLight: index < Self.maxPinLights)
            )
        }
        addLights(to: scene, sun: sun, maxDim: maxDim)

        if ambientEffects {
            scene.rootNode.addChildNode(firefliesNode(width: width, height: height))
        }
        // Continuous rendering ONLY while particles are alive — see the
        // `particlesRequireContinuousRendering` doc for the power policy.
        scnView.rendersContinuously = ambientEffects && Self.particlesRequireContinuousRendering

        // Camera rig (nodes are re-parented into each new scene).
        targetNode.position = SCNVector3Zero
        targetNode.addChildNode(yawNode)
        yawNode.addChildNode(pitchNode)
        pitchNode.addChildNode(cameraNode)
        if cameraNode.camera == nil {
            cameraNode.camera = makeCinematicCamera()
        }
        scene.rootNode.addChildNode(targetNode)

        minDistance = maxDim * 0.45
        maxDistance = maxDim * 3.0
        distance = maxDim * 1.5                  // frames the whole slab at 45°
        panLimit = SIMD2(Float(width) * 0.55, Float(height) * 0.55)
        applyCamera()

        scnView.scene = scene
        scnView.pointOfView = cameraNode

        // Re-arm per-zone material states on the fresh graph: persisted
        // highlights first (they survive rebuilds), pond shimmer otherwise.
        activeHighlights = activeHighlights.filter { zoneMeta[$0.key] != nil }
        for id in zoneMeta.keys { applyHighlight(zoneID: id) }
        #if DEBUG
        if Self.debugHighlightPreview, let first = zones.first {
            highlight(zoneID: first.id, style: .warning)
        }
        #endif

        if animateIntro {
            // One-shot cinematic dolly-in; skipped under Reduce Motion.
            cameraNode.position = SCNVector3(0, 0, distance * 1.3)
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 1.1
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
            cameraNode.position = SCNVector3(0, 0, distance)
            SCNTransaction.commit()
        }
    }

    /// The cinematic camera: HDR with a soft bloom so the emissive orbs,
    /// rims and highlights genuinely glow, a subtle depth of field focused
    /// on the slab center (updated on every dolly in `applyCamera`), and a
    /// light vignette. Exposure adaptation is OFF — no brightness pumping
    /// while orbiting — and motion blur stays 0 so gestures render crisp.
    /// All of these are per-drawn-frame effects: they coexist with
    /// on-demand rendering (`rendersContinuously = false`) unchanged.
    private func makeCinematicCamera() -> SCNCamera {
        let camera = SCNCamera()
        camera.fieldOfView = 55
        camera.zNear = 0.1
        camera.zFar = 500

        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.bloomThreshold = 0.7
        camera.bloomIntensity = 0.6
        camera.bloomBlurRadius = 6

        camera.wantsDepthOfField = true
        camera.fStop = 5.6                       // subtle — context stays readable
        camera.focusDistance = CGFloat(distance) // kept in sync by applyCamera()

        camera.motionBlurIntensity = 0           // gestures must stay crisp
        camera.vignettingPower = 0.7
        camera.vignettingIntensity = 0.35
        return camera
    }

    /// The ground: the SAME aerial photo the 2D canvas shows, textured onto
    /// a plane laid flat in XZ. Mapping contract: normalized image (x, y)
    /// with top-left origin → world ((x−0.5)·W, 0, (y−0.5)·H).
    private func groundNode(image: UIImage, width: CGFloat, height: CGFloat) -> SCNNode {
        let plane = SCNPlane(width: width, height: height)
        // Physically based, rough and non-metallic: receives the sun's soft
        // shadow and the environment fill without turning glossy.
        plane.materials = [Twin3DAtmosphere.groundMaterial(image: image)]
        let node = SCNNode(geometry: plane)
        // Rotating the XY plane by −90° about X maps plane (px, py) →
        // world (px, 0, −py); with texture v=1 at the image top this puts
        // image-top at −Z, matching the zone mapping below.
        node.eulerAngles.x = -.pi / 2
        node.castsShadow = false
        return node
    }

    /// A thin slab under the photo — the "table maquette" edge, now with
    /// dark brushed-metal sides and a matte top (`plinthMaterials`).
    private func plinthNode(width: CGFloat, height: CGFloat) -> SCNNode {
        let box = SCNBox(width: width + 0.5, height: 0.4,
                         length: height + 0.5, chamferRadius: 0.08)
        box.materials = Twin3DAtmosphere.plinthMaterials()
        let node = SCNNode(geometry: box)
        node.position = SCNVector3(0, -0.21, 0)  // top face just under the photo
        return node
    }

    /// The warm emissive seam just under the plinth's top edge — a slightly
    /// wider, very thin box whose amber rim peeks out 0.05 on every side.
    /// Sits fully below the plinth top (no coplanar faces → no z-fighting).
    private func plinthRimNode(width: CGFloat, height: CGFloat) -> SCNNode {
        let box = SCNBox(width: width + 0.6, height: 0.03,
                         length: height + 0.6, chamferRadius: 0.015)
        box.materials = [Twin3DAtmosphere.rimMaterial()]
        let node = SCNNode(geometry: box)
        node.position = SCNVector3(0, -0.035, 0)
        node.castsShadow = false
        return node
    }

    /// Fireflies/dust drifting over the slab. ≤ ~40 alive at once; only
    /// added when ambient effects are allowed (see the power policy).
    private func firefliesNode(width: CGFloat, height: CGFloat) -> SCNNode {
        let node = SCNNode()
        node.position = SCNVector3(0, 0.9, 0)
        node.addParticleSystem(Twin3DAtmosphere.fireflies(spanX: width * 0.9,
                                                          spanZ: height * 0.9))
        return node
    }

    /// One zone: an extruded glass prism in the zone's color over a thin
    /// outset base ring (the SCNShape "bevel" — SCNShape has no chamfer, so
    /// a 0.05-tall, 5%-outset second outline reads as one), a refined pin
    /// above the centroid, and a billboarded name label on a dark capsule.
    /// The group node carries "zone-<uuid>" so a hit anywhere inside opens
    /// the zone's space page.
    private func zoneNode(_ zone: Twin3DZone, width: CGFloat, height: CGFloat,
                          withPinLight: Bool) -> SCNNode {
        let group = SCNNode()
        group.name = "zone-\(zone.id.uuidString)"

        // Normalized (x, y) → prism-local (px, py). The prism is built in
        // XY and rotated −90° about X, which maps (px, py) → (px, −py) in
        // XZ — so py must be (0.5 − y)·H for image-top to land at −Z,
        // identical to the 2D canvas's NormPolygon mapping.
        let planePoints = zone.points.map { point in
            CGPoint(x: (point.x - 0.5) * width, y: (0.5 - point.y) * height)
        }
        let path = polygonPath(planePoints)

        let prismHeight: CGFloat = 0.5
        let shape = SCNShape(path: path, extrusionDepth: prismHeight)
        let tint = UIColor(Color(hex: zone.colorHex) ?? Color.smartAmber)
        zoneMeta[zone.id] = (tint: tint, kind: zone.kind)
        shape.materials = [Twin3DAtmosphere.prismMaterial(tint: tint)]
        let prism = SCNNode(geometry: shape)
        prism.name = "prism"                     // highlight() finds it here
        prism.eulerAngles.x = -.pi / 2
        prism.position.y = Float(prismHeight / 2) + 0.005   // sits on the photo

        // Local centroid of the plane polygon, shared by the ring outset
        // and (converted to world XZ) the pin/label anchor.
        let count = CGFloat(zone.points.count)
        let centroid = CGPoint(x: planePoints.map(\.x).reduce(0, +) / count,
                               y: planePoints.map(\.y).reduce(0, +) / count)

        // Base ring: same outline, outset 5% around the centroid, 0.05 tall.
        let ringPoints = planePoints.map { point in
            CGPoint(x: centroid.x + (point.x - centroid.x) * 1.05,
                    y: centroid.y + (point.y - centroid.y) * 1.05)
        }
        let ringShape = SCNShape(path: polygonPath(ringPoints), extrusionDepth: 0.05)
        ringShape.materials = [Twin3DAtmosphere.ringMaterial(tint: tint)]
        let ring = SCNNode(geometry: ringShape)
        ring.eulerAngles.x = -.pi / 2
        ring.position.y = 0.030                  // 0.05-tall ring hugging the photo
        ring.castsShadow = false

        group.addChildNode(ring)
        group.addChildNode(prism)

        let cx = Float(centroid.x)
        let cz = Float(-centroid.y)              // plane py → world −Z
        group.addChildNode(pinNode(at: SIMD3(cx, Float(prismHeight), cz),
                                   withLight: withPinLight))
        group.addChildNode(labelNode(text: zone.name,
                                     at: SIMD3(cx, Float(prismHeight) + 1.05, cz)))
        return group
    }

    private func polygonPath(_ points: [CGPoint]) -> UIBezierPath {
        let path = UIBezierPath()
        for (index, point) in points.enumerated() {
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.close()
        return path
    }

    /// The refined space pin: a small metallic torus ring hovering over the
    /// prism with a floating emissive orb above it — the orb crosses the
    /// bloom threshold so it genuinely glows under HDR. The first
    /// `maxPinLights` pins also carry a tiny falloff-limited omni light so
    /// each marker warms its own patch of the maquette.
    private func pinNode(at base: SIMD3<Float>, withLight: Bool) -> SCNNode {
        let amber = UIColor(Color.smartAmber)
        let pin = SCNNode()

        let ringGeometry = SCNTorus(ringRadius: 0.15, pipeRadius: 0.02)
        let ringMaterial = SCNMaterial()
        ringMaterial.lightingModel = .physicallyBased
        ringMaterial.diffuse.contents = amber
        ringMaterial.metalness.contents = 0.6
        ringMaterial.roughness.contents = 0.3
        ringMaterial.emission.contents = amber
        ringMaterial.emission.intensity = 0.2
        ringGeometry.materials = [ringMaterial]
        let ring = SCNNode(geometry: ringGeometry)
        ring.position = SCNVector3(base.x, base.y + 0.22, base.z)
        ring.castsShadow = false
        pin.addChildNode(ring)

        let orbGeometry = SCNSphere(radius: 0.10)
        orbGeometry.segmentCount = 24
        let orbMaterial = SCNMaterial()
        orbMaterial.diffuse.contents = amber
        orbMaterial.emission.contents = amber
        orbMaterial.emission.intensity = 1.3     // above bloomThreshold → glows
        orbMaterial.lightingModel = .constant
        orbGeometry.materials = [orbMaterial]
        let orb = SCNNode(geometry: orbGeometry)
        orb.position = SCNVector3(base.x, base.y + 0.5, base.z)
        orb.castsShadow = false
        pin.addChildNode(orb)

        if withLight {
            // A genuinely lit pin: tiny warm omni, hard distance falloff,
            // no shadow — cheap, and capped at `maxPinLights` scene-wide.
            let glow = SCNLight()
            glow.type = .omni
            glow.color = amber
            glow.intensity = 140
            glow.attenuationStartDistance = 0.1
            glow.attenuationEndDistance = 2.4
            glow.castsShadow = false
            let glowNode = SCNNode()
            glowNode.light = glow
            glowNode.position = orb.position
            pin.addChildNode(glowNode)
        }

        return pin
    }

    /// Billboarded zone name — SF rounded, warm white — on a soft dark
    /// capsule (an `SCNPlane` with `cornerRadius`, no texture needed) so it
    /// stays readable over bright photo areas at any orbit angle.
    private func labelNode(text: String, at position: SIMD3<Float>) -> SCNNode {
        let textGeometry = SCNText(string: text, extrusionDepth: 0)
        let baseFont = UIFont.systemFont(ofSize: 4, weight: .semibold)
        if let rounded = baseFont.fontDescriptor.withDesign(.rounded) {
            textGeometry.font = UIFont(descriptor: rounded, size: 4)
        } else {
            textGeometry.font = baseFont
        }
        textGeometry.flatness = 0.25
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(Color.smartTextPrimary)
        material.lightingModel = .constant       // always readable, unlit
        textGeometry.materials = [material]

        let textNode = SCNNode(geometry: textGeometry)
        let (minBound, maxBound) = textNode.boundingBox
        let textWidth = maxBound.x - minBound.x
        let textHeight = maxBound.y - minBound.y
        // Pivot at bottom-center so the label floats centered above the pin.
        textNode.pivot = SCNMatrix4MakeTranslation(minBound.x + textWidth / 2, minBound.y, 0)
        textNode.position = SCNVector3(0, 0, 0.25)   // in front of the capsule
        textNode.castsShadow = false
        textNode.renderingOrder = 11

        let capsule = SCNPlane(width: CGFloat(textWidth) + 2.6,
                               height: CGFloat(textHeight) + 1.3)
        capsule.cornerRadius = capsule.height / 2
        let capsuleMaterial = SCNMaterial()
        capsuleMaterial.diffuse.contents = UIColor(white: 0, alpha: 0.5)
        capsuleMaterial.lightingModel = .constant
        capsuleMaterial.writesToDepthBuffer = false
        capsule.materials = [capsuleMaterial]
        let capsuleNode = SCNNode(geometry: capsule)
        capsuleNode.position = SCNVector3(0, textHeight / 2, 0)
        capsuleNode.castsShadow = false
        capsuleNode.renderingOrder = 10

        // Parent carries the billboard so capsule + text turn as one.
        let node = SCNNode()
        node.addChildNode(capsuleNode)
        node.addChildNode(textNode)
        node.scale = SCNVector3(0.2, 0.2, 0.2)
        node.position = SCNVector3(position.x, position.y, position.z)
        node.constraints = [SCNBillboardConstraint()]   // free on all axes
        return node
    }

    /// The mood lighting rig: one directional "sun" (moonlight at night)
    /// with soft deferred shadows at the model's rendered azimuth/elevation,
    /// plus a low ambient for the few non-PBR materials (pins, labels).
    /// PBR surfaces take their fill from `scene.lightingEnvironment`.
    private func addLights(to scene: SCNScene, sun model: Twin3DSunModel, maxDim: Float) {
        let mood = model.mood

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = mood.ambientColor
        ambient.intensity = mood.ambientIntensity
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let sun = SCNLight()
        sun.type = .directional
        sun.color = mood.sunColor
        sun.intensity = mood.sunIntensity
        sun.castsShadow = true
        sun.shadowMode = .deferred               // screen-space, contact-tight
        sun.shadowSampleCount = 8
        sun.shadowRadius = 4                     // soft penumbra
        sun.shadowMapSize = CGSize(width: 2048, height: 2048)
        sun.shadowColor = UIColor.black.withAlphaComponent(mood.shadowOpacity)
        sun.orthographicScale = CGFloat(maxDim)  // shadow frustum covers the slab
        sun.zNear = 1
        sun.zFar = CGFloat(maxDim * 6)

        // Scene-relative sun direction: azimuth measured from −Z (image
        // top), clockwise toward +X; `look(at:)` points the node's −Z at
        // the origin, which is exactly a directional light's beam axis.
        let azimuth = model.renderedAzimuthDegrees * .pi / 180
        let elevation = model.renderedElevationDegrees * .pi / 180
        let toSun = SIMD3<Float>(Float(sin(azimuth) * cos(elevation)),
                                 Float(sin(elevation)),
                                 Float(-cos(azimuth) * cos(elevation)))
        let sunNode = SCNNode()
        sunNode.light = sun
        sunNode.position = SCNVector3(toSun.x * maxDim * 2,
                                      toSun.y * maxDim * 2,
                                      toSun.z * maxDim * 2)
        scene.rootNode.addChildNode(sunNode)
        sunNode.look(at: SCNVector3Zero)
    }

    // MARK: Camera

    private func applyCamera() {
        yawNode.eulerAngles.y = yaw
        pitchNode.eulerAngles.x = pitch
        cameraNode.position = SCNVector3(0, 0, distance)
        // Depth of field tracks the orbit target (the slab center): the
        // camera-to-target distance IS the focus distance.
        cameraNode.camera?.focusDistance = CGFloat(distance)
        targetNode.position = SCNVector3(
            min(max(targetNode.position.x, -panLimit.x), panLimit.x),
            0,
            min(max(targetNode.position.z, -panLimit.y), panLimit.y)
        )
    }

    // MARK: State glow (T1.5 → Pulsul bridge)

    /// Puts a zone's prism into a highlight state — `.warning` (amber
    /// pulse), `.alert` (red pulse) or `.none` (back to the zone's honest
    /// tint, pond shimmer re-armed). Highlights survive scene rebuilds and
    /// unknown zone ids are ignored safely.
    ///
    /// Deliberately DORMANT for now: PRVIO has no sensor-threshold model
    /// yet, so no in-app source calls this — wiring a synthetic trigger
    /// would invent an alert the data can't back (honesty law). Pulsul will
    /// drive it from real device events; until then the only caller is the
    /// DEBUG-only `debugHighlightPreview` flag.
    func highlight(zoneID: UUID, style: Twin3DHighlightStyle) {
        if style == .none {
            activeHighlights.removeValue(forKey: zoneID)
        } else {
            activeHighlights[zoneID] = style
        }
        applyHighlight(zoneID: zoneID)
    }

    /// Applies the zone's current material state: highlight pulse when one
    /// is active, else the honest tint — with the pond shimmer (a 3s
    /// emission breath) as the resting state for pond zones when ambient
    /// effects are on. Pulses degrade to a static raised emission under
    /// Reduce Motion. Running CAAnimations trigger on-demand redraws, so
    /// none of this needs continuous rendering.
    private func applyHighlight(zoneID: UUID) {
        guard let scene = scnView?.scene, let meta = zoneMeta[zoneID],
              let group = scene.rootNode.childNode(withName: "zone-\(zoneID.uuidString)",
                                                   recursively: false),
              let material = group.childNode(withName: "prism", recursively: false)?
                  .geometry?.firstMaterial
        else { return }

        material.removeAnimation(forKey: Self.highlightAnimationKey)
        material.removeAnimation(forKey: Self.shimmerAnimationKey)

        if let pulseColor = (activeHighlights[zoneID] ?? .none).pulseColor {
            material.emission.contents = pulseColor
            if UIAccessibility.isReduceMotionEnabled {
                material.emission.intensity = 0.9
            } else {
                material.emission.intensity = 0.35
                material.addAnimation(Self.pulse(from: 0.35, to: 1.1, duration: 0.9),
                                      forKey: Self.highlightAnimationKey)
            }
        } else {
            material.emission.contents = meta.tint
            material.emission.intensity = 0.25
            if effectsEnabled, meta.kind == .pond {
                // Water hint: a slow emission breath — an honest "this is
                // water" wink on the zone's own color, nothing simulated.
                material.emission.intensity = 0.15
                material.addAnimation(Self.pulse(from: 0.15, to: 0.3, duration: 3),
                                      forKey: Self.shimmerAnimationKey)
            }
        }
    }

    private static func pulse(from: CGFloat, to: CGFloat,
                              duration: CFTimeInterval) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "emission.intensity")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return animation
    }

    // MARK: Gestures (clamped; each writes the rig once, no per-frame work)

    /// One-finger orbit: horizontal drag spins the maquette, vertical drag
    /// tilts between near-top-down and a grazing cinematic angle.
    @objc private func handleOrbit(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: gesture.view)
        gesture.setTranslation(.zero, in: gesture.view)
        yaw -= Float(translation.x) * 0.006
        pitch = min(max(pitch - Float(translation.y) * 0.005, minPitch), maxPitch)
        applyCamera()
    }

    /// Two-finger pan: slides the camera target across the ground plane,
    /// yaw-aware so "up" on screen is always "away" in the scene.
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: gesture.view)
        gesture.setTranslation(.zero, in: gesture.view)
        let step = distance * 0.0016
        let dx = Float(translation.x) * step
        let dy = Float(translation.y) * step
        // forward (toward screen top, on the ground) and right, in world XZ.
        let forward = SIMD2<Float>(-sin(yaw), -cos(yaw))
        let right = SIMD2<Float>(cos(yaw), -sin(yaw))
        targetNode.position.x += forward.x * dy - right.x * dx
        targetNode.position.z += forward.y * dy - right.y * dx
        applyCamera()
    }

    /// Pinch: dolly, clamped so the maquette never vanishes or clips.
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard gesture.state == .changed else { return }
        distance = min(max(distance / Float(gesture.scale), minDistance), maxDistance)
        gesture.scale = 1
        applyCamera()
    }

    /// Tap: SceneKit hit test → nearest ancestor named "zone-<uuid>" →
    /// the zone's Estate OS space page.
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let scnView else { return }
        let point = gesture.location(in: scnView)
        let hits = scnView.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
        for hit in hits {
            var node: SCNNode? = hit.node
            while let current = node {
                if let name = current.name, name.hasPrefix("zone-"),
                   let id = UUID(uuidString: String(name.dropFirst(5))) {
                    onZoneTap(id)
                    return
                }
                node = current.parent
            }
        }
    }
}
