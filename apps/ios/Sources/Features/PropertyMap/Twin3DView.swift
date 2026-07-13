import SwiftUI
import SceneKit
import UIKit

// MARK: - Twin 3D (T1) — the Digital Twin's primary face
//
// A real-time SceneKit maquette built from the property's OWN data: the same
// bundled aerial photo the 2D canvas renders (via `AerialImagePyramid`)
// textured onto a ground slab, and every zone with a drawn `imagePolygon`
// extruded into a translucent glass prism in the zone's own color, capped by
// a floating amber pin and a billboarded name label. Tapping a zone opens
// its Estate OS space page (`SpaceDetailView`).
//
// Honest by construction (honesty law):
// - Nothing here is invented: no fake terrain, no guessed elevations. The
//   ground is the real photo; prisms exist only for zones the user actually
//   drew in 2D; heights are uniform because the app knows no real heights.
// - No aerial photo decodable → an empty state that says so; no zones → the
//   photo slab alone plus a hint pointing at the 2D drawing flow.
//
// Performance:
// - The scene graph is rebuilt ONLY when the data signature changes (image
//   identity + zone geometry/colors), never per frame.
// - `rendersContinuously = false`: SceneKit redraws only when the camera or
//   graph mutates, so an idle twin costs ~0 GPU.
// - 4× MSAA, the default Metal renderer, and a fixed medium pyramid level
//   (≥2048 px) as the ground texture — crisp without decoding the native
//   drone photo into hundreds of MB of texture.
// - No idle auto-orbit at all, so Reduce Motion has nothing to switch off;
//   the only camera animation is the one-shot intro dolly, skipped under
//   Reduce Motion.
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
                              colorHex: zone.colorHex, points: zone.imagePoints)
        }
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
}

// MARK: - SceneKit view (UIViewRepresentable)

private struct Twin3DSceneView: UIViewRepresentable {
    let aerialImage: UIImage
    let zones: [Twin3DZone]
    let animateIntro: Bool
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
                                            animateIntro: animateIntro)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.onZoneTap = onZoneTap
        context.coordinator.rebuildIfNeeded(image: aerialImage, zones: zones,
                                            animateIntro: animateIntro)
    }
}

// MARK: - Coordinator: scene builder + camera rig + gestures

@MainActor
final class Twin3DCoordinator: NSObject {
    var onZoneTap: (UUID) -> Void

    private weak var scnView: SCNView?
    /// Hash of (image identity + zone snapshots): the scene rebuilds only
    /// when this changes — never per frame, never per SwiftUI render.
    private var sceneSignature: Int?
    private var hasBuiltOnce = false

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

    func rebuildIfNeeded(image: UIImage, zones: [Twin3DZone], animateIntro: Bool) {
        var hasher = Hasher()
        hasher.combine(ObjectIdentifier(image))   // pyramid levels are cached & stable
        hasher.combine(zones)
        let signature = hasher.finalize()
        guard signature != sceneSignature else { return }
        sceneSignature = signature
        buildScene(image: image, zones: zones,
                   animateIntro: animateIntro && !hasBuiltOnce)
        hasBuiltOnce = true
    }

    // MARK: Scene construction (once per data change)

    private func buildScene(image: UIImage, zones: [Twin3DZone], animateIntro: Bool) {
        guard let scnView else { return }
        let scene = SCNScene()

        // World scale: the photo's width is 12 units; height follows its
        // aspect so normalized zone coordinates land on real pixels.
        let width: CGFloat = 12
        let aspect = image.size.height / max(image.size.width, 1)
        let height = width * aspect
        let maxDim = Float(max(width, height))

        scene.rootNode.addChildNode(groundNode(image: image, width: width, height: height))
        scene.rootNode.addChildNode(plinthNode(width: width, height: height))
        for zone in zones {
            scene.rootNode.addChildNode(zoneNode(zone, width: width, height: height))
        }
        addLights(to: scene)

        // Camera rig (nodes are re-parented into each new scene).
        targetNode.position = SCNVector3Zero
        targetNode.addChildNode(yawNode)
        yawNode.addChildNode(pitchNode)
        pitchNode.addChildNode(cameraNode)
        if cameraNode.camera == nil {
            let camera = SCNCamera()
            camera.fieldOfView = 55
            camera.zNear = 0.1
            camera.zFar = 500
            cameraNode.camera = camera
        }
        scene.rootNode.addChildNode(targetNode)

        minDistance = maxDim * 0.45
        maxDistance = maxDim * 3.0
        distance = maxDim * 1.5                  // frames the whole slab at 45°
        panLimit = SIMD2(Float(width) * 0.55, Float(height) * 0.55)
        applyCamera()

        scnView.scene = scene
        scnView.pointOfView = cameraNode

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

    /// The ground: the SAME aerial photo the 2D canvas shows, textured onto
    /// a plane laid flat in XZ. Mapping contract: normalized image (x, y)
    /// with top-left origin → world ((x−0.5)·W, 0, (y−0.5)·H).
    private func groundNode(image: UIImage, width: CGFloat, height: CGFloat) -> SCNNode {
        let plane = SCNPlane(width: width, height: height)
        let material = SCNMaterial()
        material.diffuse.contents = image
        material.lightingModel = .lambert        // receives the sun's shadow
        material.isDoubleSided = false
        plane.materials = [material]
        let node = SCNNode(geometry: plane)
        // Rotating the XY plane by −90° about X maps plane (px, py) →
        // world (px, 0, −py); with texture v=1 at the image top this puts
        // image-top at −Z, matching the zone mapping below.
        node.eulerAngles.x = -.pi / 2
        node.castsShadow = false
        return node
    }

    /// A thin dark-warm slab under the photo — the "table maquette" edge.
    private func plinthNode(width: CGFloat, height: CGFloat) -> SCNNode {
        let box = SCNBox(width: width + 0.5, height: 0.4,
                         length: height + 0.5, chamferRadius: 0.08)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.13, green: 0.10, blue: 0.08, alpha: 1)
        material.lightingModel = .lambert
        box.materials = [material]
        let node = SCNNode(geometry: box)
        node.position = SCNVector3(0, -0.21, 0)  // top face just under the photo
        return node
    }

    /// One zone: an extruded translucent prism in the zone's color, a small
    /// amber pin floating above the centroid, and a billboarded name label.
    /// The group node carries "zone-<uuid>" so a hit anywhere inside opens
    /// the zone's space page.
    private func zoneNode(_ zone: Twin3DZone, width: CGFloat, height: CGFloat) -> SCNNode {
        let group = SCNNode()
        group.name = "zone-\(zone.id.uuidString)"

        // Normalized (x, y) → prism-local (px, py). The prism is built in
        // XY and rotated −90° about X, which maps (px, py) → (px, −py) in
        // XZ — so py must be (0.5 − y)·H for image-top to land at −Z,
        // identical to the 2D canvas's NormPolygon mapping.
        let path = UIBezierPath()
        for (index, point) in zone.points.enumerated() {
            let planePoint = CGPoint(x: (point.x - 0.5) * width,
                                     y: (0.5 - point.y) * height)
            if index == 0 { path.move(to: planePoint) } else { path.addLine(to: planePoint) }
        }
        path.close()

        let prismHeight: CGFloat = 0.5
        let shape = SCNShape(path: path, extrusionDepth: prismHeight)
        let tint = UIColor(Color(hex: zone.colorHex) ?? Color.smartAmber)
        let material = SCNMaterial()
        material.diffuse.contents = tint
        material.transparency = 0.30
        material.emission.contents = tint
        material.emission.intensity = 0.35
        material.lightingModel = .lambert
        material.isDoubleSided = true
        shape.materials = [material]
        let prism = SCNNode(geometry: shape)
        prism.eulerAngles.x = -.pi / 2
        prism.position.y = Float(prismHeight / 2) + 0.005   // sits on the photo
        group.addChildNode(prism)

        // Centroid in world XZ for the pin + label anchor.
        let count = Double(zone.points.count)
        let cx = Float((zone.points.map(\.x).reduce(0, +) / count - 0.5) * width)
        let cz = Float((zone.points.map(\.y).reduce(0, +) / count - 0.5) * height)

        group.addChildNode(pinNode(at: SIMD3(cx, Float(prismHeight), cz)))
        group.addChildNode(labelNode(text: zone.name,
                                     at: SIMD3(cx, Float(prismHeight) + 1.05, cz)))
        return group
    }

    /// The floating space pin: stem + amber marker + soft glow halo.
    private func pinNode(at base: SIMD3<Float>) -> SCNNode {
        let amber = UIColor(Color.smartAmber)
        let pin = SCNNode()

        let stemGeometry = SCNCylinder(radius: 0.022, height: 0.55)
        let stemMaterial = SCNMaterial()
        stemMaterial.diffuse.contents = amber.withAlphaComponent(0.8)
        stemMaterial.lightingModel = .constant
        stemGeometry.materials = [stemMaterial]
        let stem = SCNNode(geometry: stemGeometry)
        stem.position = SCNVector3(base.x, base.y + 0.275, base.z)
        stem.castsShadow = false
        pin.addChildNode(stem)

        let markerGeometry = SCNSphere(radius: 0.14)
        markerGeometry.segmentCount = 24
        let markerMaterial = SCNMaterial()
        markerMaterial.diffuse.contents = amber
        markerMaterial.emission.contents = amber
        markerMaterial.emission.intensity = 0.8
        markerMaterial.lightingModel = .constant
        markerGeometry.materials = [markerMaterial]
        let marker = SCNNode(geometry: markerGeometry)
        marker.position = SCNVector3(base.x, base.y + 0.62, base.z)
        marker.castsShadow = false
        pin.addChildNode(marker)

        let haloGeometry = SCNSphere(radius: 0.26)
        haloGeometry.segmentCount = 16
        let haloMaterial = SCNMaterial()
        haloMaterial.diffuse.contents = UIColor.clear
        haloMaterial.emission.contents = amber
        haloMaterial.emission.intensity = 0.6
        haloMaterial.transparency = 0.22
        haloMaterial.lightingModel = .constant
        haloMaterial.writesToDepthBuffer = false
        haloGeometry.materials = [haloMaterial]
        let halo = SCNNode(geometry: haloGeometry)
        halo.position = marker.position
        halo.castsShadow = false
        pin.addChildNode(halo)

        return pin
    }

    /// Billboarded zone name in the warm-white text tone; always faces the
    /// camera via `SCNBillboardConstraint`, so it reads at any orbit angle.
    private func labelNode(text: String, at position: SIMD3<Float>) -> SCNNode {
        let textGeometry = SCNText(string: text, extrusionDepth: 0)
        textGeometry.font = UIFont.systemFont(ofSize: 4, weight: .semibold)
        textGeometry.flatness = 0.25
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(Color.smartTextPrimary)
        material.lightingModel = .constant       // always readable, unlit
        textGeometry.materials = [material]

        let node = SCNNode(geometry: textGeometry)
        let (minBound, maxBound) = node.boundingBox
        // Pivot at bottom-center so the label floats centered above the pin.
        node.pivot = SCNMatrix4MakeTranslation((minBound.x + maxBound.x) / 2, minBound.y, 0)
        node.scale = SCNVector3(0.2, 0.2, 0.2)
        node.position = SCNVector3(position.x, position.y, position.z)
        node.castsShadow = false
        node.constraints = [SCNBillboardConstraint()]   // free on all axes
        return node
    }

    /// Warm ambient + one warm directional "sun" with a soft ground shadow —
    /// the SmartHomeTheme mood carried into the scene's lighting.
    private func addLights(to scene: SCNScene) {
        let warm = UIColor(red: 1.0, green: 0.94, blue: 0.86, alpha: 1)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = warm
        ambient.intensity = 450
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let sun = SCNLight()
        sun.type = .directional
        sun.color = warm
        sun.intensity = 900
        sun.castsShadow = true
        sun.shadowColor = UIColor.black.withAlphaComponent(0.32)
        sun.shadowRadius = 8
        let sunNode = SCNNode()
        sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-Float.pi / 2.6, -Float.pi / 5, 0)
        scene.rootNode.addChildNode(sunNode)
    }

    // MARK: Camera

    private func applyCamera() {
        yawNode.eulerAngles.y = yaw
        pitchNode.eulerAngles.x = pitch
        cameraNode.position = SCNVector3(0, 0, distance)
        targetNode.position = SCNVector3(
            min(max(targetNode.position.x, -panLimit.x), panLimit.x),
            0,
            min(max(targetNode.position.z, -panLimit.y), panLimit.y)
        )
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
