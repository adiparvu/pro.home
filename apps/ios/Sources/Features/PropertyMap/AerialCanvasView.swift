import SwiftUI
import UIKit

// MARK: - Aerial Canvas View
// Shows the property's static aerial/drone photo full-bleed and lets the user
// place, move and open element pins directly on the image.
//
// Design notes:
//   • The image is the BUNDLED `aerial_property` asset — never a remote URL —
//     so the user always sees exactly the photo shipped in the app.
//   • The image is STATIC (no Ken Burns) so pins stay locked to image features.
//   • Pins are positioned purely by normalised positionX/positionY (0–1).

/// A programmatic "fly-to" request: normalized target + a token so the same
/// point can be requested twice in a row and still animate.
struct MapFocus: Equatable {
    let point: CGPoint
    let token: UUID

    init(point: CGPoint) {
        self.point = point
        self.token = UUID()
    }
}

struct AerialCanvasView: View {
    let property: PropertyModel
    let elements: [PropertyElement]
    var zones: [PropertyZone] = []
    var interactive: Bool = false
    /// When set, the canvas zooms in and centers on this normalized point
    /// (search results, "show on map" actions).
    var focus: MapFocus? = nil
    // Live layers (Faza 3): all optional, all rendered over the same photo.
    /// Zones drawn with a dashed "underground" outline (buried utilities).
    var dashedZoneIds: Set<UUID> = []
    /// Per-zone fill/stroke override (health tinting).
    var zoneTintOverride: [UUID: Color] = [:]
    /// Pulsing badge color per element id (open tasks: red = urgent/overdue).
    var elementBadges: [UUID: Color] = [:]
    /// Photo-count bubbles anchored at zone centroids (journal layer).
    var journalBadges: [TwinJournalBadge] = []
    var onJournalBadgeTap: (UUID) -> Void = { _ in }
    /// Elements with a linked 3D scan get a "3D" badge on their pin.
    var threeDElementIds: Set<UUID> = []
    var pinMode: Bool = false
    var zoneDrawMode: Bool = false
    var draftZonePoints: [CGPoint] = []   // normalized 0–1
    var reshapeMode: Bool = false
    var reshapePoints: [CGPoint] = []     // normalized 0–1
    var showZones: Bool = true
    var showNames: Bool = true
    /// nil = show all; 0/1/2 = only elements in the top/middle/bottom third.
    var sectionFilter: Int? = nil
    var categoryFilter: ElementCategory? = nil
    var onElementTap: (PropertyElement) -> Void = { _ in }
    var onCanvasTap: (CGPoint) -> Void = { _ in }
    var onElementMove: (PropertyElement, CGPoint) -> Void = { _, _ in }
    var onElementEdit: (PropertyElement) -> Void = { _ in }
    var onElementDelete: (PropertyElement) -> Void = { _ in }
    var onElementFavorite: (PropertyElement) -> Void = { _ in }
    var onZoneTap: (PropertyZone) -> Void = { _ in }
    var onAddZonePoint: (CGPoint) -> Void = { _ in }
    var onZoneReshape: (PropertyZone) -> Void = { _ in }
    var onZoneDelete: (PropertyZone) -> Void = { _ in }
    var onMoveReshapePoint: (Int, CGPoint) -> Void = { _, _ in }
    var onRemoveReshapePoint: (Int) -> Void = { _ in }

    @State private var dragId: UUID? = nil
    @State private var dragPos: CGPoint = .zero

    // Pinch-to-zoom / pan (view-only; reset while editing)
    @State private var zoomScale: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var lastPan: CGSize = .zero

    private var canZoom: Bool { interactive && !pinMode && !zoneDrawMode && !reshapeMode }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { v in guard canZoom else { return }; zoomScale = min(max(lastZoom * v, 1), 5) }
            .onEnded { _ in
                lastZoom = zoomScale
                if zoomScale <= 1.01 { withAnimation(.spring(response: 0.3)) { zoomScale = 1; lastZoom = 1; panOffset = .zero; lastPan = .zero } }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { v in guard canZoom, zoomScale > 1 else { return }
                panOffset = CGSize(width: lastPan.width + v.translation.width, height: lastPan.height + v.translation.height) }
            .onEnded { _ in lastPan = panOffset }
    }

    private func resetZoom() {
        zoomScale = 1; lastZoom = 1; panOffset = .zero; lastPan = .zero
    }

    /// Zoom in and center the given normalized point, clamped so the photo
    /// keeps covering the viewport (no empty edges).
    private func flyTo(_ p: CGPoint, size: CGSize) {
        let scale: CGFloat = max(zoomScale, 2.4)
        let maxX = (scale - 1) * size.width / 2
        let maxY = (scale - 1) * size.height / 2
        let target = CGSize(
            width: min(max((0.5 - p.x) * size.width * scale, -maxX), maxX),
            height: min(max((0.5 - p.y) * size.height * scale, -maxY), maxY)
        )
        withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
            zoomScale = scale
            panOffset = target
        }
        lastZoom = scale
        lastPan = target
    }

    private var visibleElements: [PropertyElement] {
        var items = elements
        if let cat = categoryFilter {
            items = items.filter { $0.elementType.category == cat }
        }
        if let s = sectionFilter {
            items = items.filter { el in
                let y = (el.positionX == 0 && el.positionY == 0) ? 0.5 : el.positionY
                return Int(min(max(y, 0), 0.999) * 3) == s
            }
        }
        return items
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                aerialImage(size: geo.size)

                // Zones (under pins)
                if showZones {
                    ForEach(zones.filter(\.hasImageShape)) { zone in
                        zoneShape(zone, size: geo.size)
                    }
                }

                // Tap-to-place layer (only while in pin mode)
                if interactive && pinMode {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture()
                                .onEnded { val in
                                    onCanvasTap(clampNorm(val.location, in: geo.size))
                                }
                        )
                }

                // Tap-to-add-corner layer (zone drawing)
                if interactive && zoneDrawMode {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture()
                                .onEnded { val in
                                    onAddZonePoint(clampNorm(val.location, in: geo.size))
                                }
                        )
                    zoneDraftOverlay(size: geo.size)
                }

                // Section dividers (only while a section filter is active)
                if sectionFilter != nil {
                    VStack(spacing: 0) {
                        ForEach(0..<3) { idx in
                            Rectangle()
                                .fill(idx == sectionFilter ? Color.clear : Color.black.opacity(0.35))
                                .overlay(alignment: .bottom) {
                                    if idx < 2 { Rectangle().fill(.white.opacity(0.25)).frame(height: 1) }
                                }
                        }
                    }
                    .allowsHitTesting(false)
                }

                // Element pins (clustered when idle to reduce crowding)
                if !pinMode && !zoneDrawMode && !reshapeMode {
                    let clusters = clusterize(visibleElements, size: geo.size)
                    ForEach(clusters.indices, id: \.self) { i in
                        if clusters[i].count == 1 {
                            pinView(clusters[i][0], size: geo.size)
                        } else {
                            clusterPin(clusters[i], size: geo.size)
                        }
                    }
                } else {
                    ForEach(visibleElements) { el in
                        pinView(el, size: geo.size)
                    }
                }

                // Journal layer: photo-count bubbles at zone centroids.
                if !pinMode && !zoneDrawMode && !reshapeMode {
                    ForEach(journalBadges) { badge in
                        journalBadgeView(badge, size: geo.size)
                    }
                }

                if interactive && reshapeMode { reshapeOverlay(size: geo.size) }

                if interactive && pinMode { placeBanner }
            }
            .scaleEffect(zoomScale)
            .offset(panOffset)
            .simultaneousGesture(zoomGesture)
            .simultaneousGesture(panGesture)
            .onChange(of: pinMode) { _, on in if on { resetZoom() } }
            .onChange(of: zoneDrawMode) { _, on in if on { resetZoom() } }
            .onChange(of: reshapeMode) { _, on in if on { resetZoom() } }
            .onChange(of: focus) { _, f in
                guard let f, canZoom else { return }
                flyTo(f.point, size: geo.size)
            }
        }
        .clipped()
    }

    // MARK: - Image

    @ViewBuilder
    private func aerialImage(size: CGSize) -> some View {
        Group {
            if let ui = UIImage(named: "aerial_property") {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(red: 0.06, green: 0.12, blue: 0.07)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    // MARK: - Pins

    @ViewBuilder
    private func pinView(_ el: PropertyElement, size: CGSize) -> some View {
        let pin = AerialElementPin(element: el, dragging: dragId == el.id, showName: showNames,
                                   badge: elementBadges[el.id],
                                   has3D: threeDElementIds.contains(el.id))
            .position(pinPoint(el, size))
        if interactive {
            let base = pin
                .onTapGesture { if dragId == nil { onElementTap(el) } }
                .contextMenu {
                    Button { onElementTap(el) } label: { Label("Open", systemImage: "eye") }
                    Button { onElementEdit(el) } label: { Label("Edit", systemImage: "pencil") }
                    Button { onElementFavorite(el) } label: {
                        Label(el.isFavorite ? "Remove from favorites" : "Add to favorites",
                              systemImage: el.isFavorite ? "star.slash" : "star")
                    }
                    Divider()
                    Button(role: .destructive) { onElementDelete(el) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            if zoomScale == 1 {
                base.highPriorityGesture(dragGesture(el, size))
            } else {
                base
            }
        } else {
            pin
        }
    }

    private func dragGesture(_ el: PropertyElement, _ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { v in
                dragId = el.id
                dragPos = CGPoint(
                    x: min(max(v.location.x, 0), size.width),
                    y: min(max(v.location.y, 0), size.height)
                )
            }
            .onEnded { v in
                onElementMove(el, clampNorm(v.location, in: size))
                dragId = nil
                HapticFeedback.success()
            }
    }

    // MARK: - Clustering

    private func clusterize(_ els: [PropertyElement], size: CGSize) -> [[PropertyElement]] {
        var clusters: [[PropertyElement]] = []
        var centers: [CGPoint] = []
        let threshold: CGFloat = 42
        for el in els {
            let p = pinPoint(el, size)
            if let idx = centers.firstIndex(where: { hypot($0.x - p.x, $0.y - p.y) < threshold }) {
                clusters[idx].append(el)
                let n = CGFloat(clusters[idx].count)
                centers[idx] = CGPoint(x: (centers[idx].x * (n - 1) + p.x) / n,
                                       y: (centers[idx].y * (n - 1) + p.y) / n)
            } else {
                clusters.append([el]); centers.append(p)
            }
        }
        return clusters
    }

    @ViewBuilder
    private func clusterPin(_ els: [PropertyElement], size: CGSize) -> some View {
        let pts = els.map { pinPoint($0, size) }
        let cx = pts.map(\.x).reduce(0, +) / CGFloat(pts.count)
        let cy = pts.map(\.y).reduce(0, +) / CGFloat(pts.count)
        Menu {
            ForEach(els) { el in
                Button { onElementTap(el) } label: { Label(el.name, systemImage: el.elementType.icon) }
            }
        } label: {
            ZStack {
                Circle().fill(.ultraThinMaterial)
                    .overlay(Circle().fill(Color.accentColor.opacity(0.55)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
                    .frame(width: 34, height: 34)
                Text("\(els.count)").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        }
        .position(x: cx, y: cy)
    }

    private func pinPoint(_ el: PropertyElement, _ size: CGSize) -> CGPoint {
        if dragId == el.id { return dragPos }
        // Legacy elements with no normalised position default to centre.
        let nx = (el.positionX == 0 && el.positionY == 0) ? 0.5 : el.positionX
        let ny = (el.positionX == 0 && el.positionY == 0) ? 0.5 : el.positionY
        return CGPoint(x: nx * size.width, y: ny * size.height)
    }

    // MARK: - Journal badges

    @ViewBuilder
    private func journalBadgeView(_ badge: TwinJournalBadge, size: CGSize) -> some View {
        Button {
            HapticFeedback.impact(.light)
            onJournalBadgeTap(badge.id)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "photo.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("\(badge.count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, AppSpacing.sm).padding(.vertical, 4)
            .background {
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(Color.orange.opacity(0.45))
                }
            }
            .overlay(Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .position(x: badge.point.x * size.width, y: badge.point.y * size.height - 22)
        .accessibilityLabel("Journal photos")
    }

    private func clampNorm(_ p: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(p.x / max(size.width, 1), 0), 1),
            y: min(max(p.y / max(size.height, 1), 0), 1)
        )
    }

    // MARK: - Zones

    @ViewBuilder
    private func zoneShape(_ zone: PropertyZone, size: CGSize) -> some View {
        let pts = zone.imagePoints
        let interactable = interactive && !pinMode && !zoneDrawMode && !reshapeMode
        let tint = zoneTintOverride[zone.id] ?? zone.tint
        let dashed = dashedZoneIds.contains(zone.id)
        ZStack {
            NormPolygon(points: pts).fill(tint.opacity(dashed ? 0.12 : 0.22))
            NormPolygon(points: pts).stroke(
                tint,
                style: dashed
                    ? StrokeStyle(lineWidth: 2, lineJoin: .round, dash: [7, 5])
                    : StrokeStyle(lineWidth: 2, lineJoin: .round)
            )
        }
        .contentShape(NormPolygon(points: pts))
        .onTapGesture { if interactable { onZoneTap(zone) } }
        .contextMenu {
            Button { onZoneTap(zone) } label: { Label("Edit details", systemImage: "pencil") }
            Button { onZoneReshape(zone) } label: { Label("Edit shape", systemImage: "pencil.and.outline") }
            Divider()
            Button(role: .destructive) { onZoneDelete(zone) } label: { Label("Delete", systemImage: "trash") }
        }
        .allowsHitTesting(interactable)
    }

    @ViewBuilder
    private func reshapeOverlay(size: CGSize) -> some View {
        let imgPts = reshapePoints.map { ImagePoint(x: $0.x, y: $0.y) }
        ZStack {
            if imgPts.count >= 2 {
                NormPolygon(points: imgPts).fill(Color.accentColor.opacity(0.18))
                NormPolygon(points: imgPts)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            }
            ForEach(Array(reshapePoints.enumerated()), id: \.offset) { idx, pt in
                Circle()
                    .fill(.white)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().fill(Color.accentColor).frame(width: 11, height: 11))
                    .shadow(color: .black.opacity(0.3), radius: 3)
                    .position(x: pt.x * size.width, y: pt.y * size.height)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in onMoveReshapePoint(idx, clampNorm(v.location, in: size)) }
                    )
                    .onTapGesture(count: 2) { onRemoveReshapePoint(idx) }
            }
        }
    }

    @ViewBuilder
    private func zoneDraftOverlay(size: CGSize) -> some View {
        let imgPts = draftZonePoints.map { ImagePoint(x: $0.x, y: $0.y) }
        ZStack {
            if imgPts.count >= 2 {
                NormPolygon(points: imgPts).fill(Color.accentColor.opacity(0.15))
                NormPolygon(points: imgPts)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
            ForEach(Array(draftZonePoints.enumerated()), id: \.offset) { _, pt in
                Circle().fill(.white).frame(width: 12, height: 12)
                    .overlay(Circle().fill(Color.accentColor).frame(width: 6, height: 6))
                    .position(x: pt.x * size.width, y: pt.y * size.height)
            }
            VStack {
                Text("Tap to add corners (\(draftZonePoints.count))")
                    .font(AppFont.captionEmphasis).foregroundStyle(.white)
                    .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.sm)
                    .background(.black.opacity(0.65), in: Capsule())
                    .padding(.top, AppSpacing.base)
                Spacer()
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Banner

    private var placeBanner: some View {
        VStack {
            HStack(spacing: 6) {
                Image(systemName: "hand.tap.fill")
                Text("Tap the photo to place an element")
                    .font(AppFont.captionEmphasis)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, AppSpacing.base).padding(.vertical, 9)
            .background(.black.opacity(0.65), in: Capsule())
            .padding(.top, AppSpacing.base)
            Spacer()
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Aerial Element Pin

// MARK: - Normalized polygon shape (points are 0–1 of the frame)

struct NormPolygon: Shape {
    let points: [ImagePoint]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let f = points.first else { return p }
        p.move(to: CGPoint(x: f.x * rect.width, y: f.y * rect.height))
        for pt in points.dropFirst() {
            p.addLine(to: CGPoint(x: pt.x * rect.width, y: pt.y * rect.height))
        }
        p.closeSubpath()
        return p
    }
}

private struct AerialElementPin: View {
    let element: PropertyElement
    var dragging: Bool = false
    var showName: Bool = true
    /// Live-layer badge (open tasks) — pulses unless Reduce Motion is on.
    var badge: Color? = nil
    /// Shows the "3D" chip when a scan is linked to this element.
    var has3D: Bool = false

    private let size: CGFloat = 28

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                if let cover = element.coverPhotoUrl, let url = URL(string: cover) {
                    // Cover thumbnail pin
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase { img.resizable().scaledToFill() }
                        else { element.elementType.accentColor.opacity(0.5) }
                    }
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                } else {
                    // Liquid-glass icon pin
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().fill(element.elementType.accentColor.opacity(0.45)))
                        .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                        .frame(width: size, height: size)
                    Image(systemName: element.elementType.icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .overlay(alignment: .topTrailing) {
                if element.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.yellow)
                        .padding(2)
                        .background(Circle().fill(.black.opacity(0.55)))
                        .offset(x: 4, y: -4)
                }
            }
            .overlay(alignment: .topLeading) {
                if let badge {
                    PulsingBadge(color: badge)
                        .offset(x: -5, y: -5)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if has3D {
                    Text(verbatim: "3D")
                        .font(.system(size: 7, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4).padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.brandPurple))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.8), lineWidth: 0.8))
                        .offset(x: 6, y: 3)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .scaleEffect(dragging ? 1.3 : 1.0)

            if showName {
                Text(element.name)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, AppSpacing.xs).padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .animation(.spring(response: 0.25), value: dragging)
    }
}
