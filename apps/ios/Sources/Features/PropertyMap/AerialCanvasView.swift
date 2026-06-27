import SwiftUI
import UIKit
import CoreLocation

// MARK: - Aerial Canvas View
// When a property has `photoUrl` (drone / aerial photo), this view displays it
// as an animated background with:
//   • Ken Burns subtle zoom (1.0 → 1.03, 8-second cycle)
//   • Ripple rings on water-named zones (heleșteu, iaz, pond, lake, pool …)
//   • Element pins positioned from lat/lon or normalised positionX/positionY

struct AerialCanvasView: View {
    let property: PropertyModel
    let zones: [PropertyZone]
    let elements: [PropertyElement]
    var onElementTap: (PropertyElement) -> Void = { _ in }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 60)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                ZStack {
                    dronePhotoLayer(t: t, size: geo.size)

                    // Fade out the embedded photo status bar at top
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [.black.opacity(0.55), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: geo.size.height * 0.09)
                        Spacer()
                    }
                    .allowsHitTesting(false)

                    Canvas { ctx, size in
                        for center in waterCentroids(size) {
                            for i in 0..<3 {
                                let phase = (t / 3.0 + Double(i) / 3.0)
                                    .truncatingRemainder(dividingBy: 1.0)
                                let r = CGFloat(phase) * 64
                                let alpha = (1.0 - CGFloat(phase)) * 0.45
                                var p = Path()
                                p.addArc(center: center, radius: r,
                                         startAngle: .zero, endAngle: .degrees(360),
                                         clockwise: false)
                                ctx.stroke(p, with: .color(Color.cyan.opacity(alpha)),
                                           lineWidth: 1.5)
                            }
                        }
                    }
                    .allowsHitTesting(false)

                    let pinnable = elements.filter {
                        $0.latitude != nil || $0.positionX > 0 || $0.positionY > 0
                    }
                    ForEach(pinnable) { el in
                        AerialElementPin(element: el)
                            .position(pinPoint(el, geo.size))
                            .onTapGesture { onElementTap(el) }
                    }
                }
            }
        }
        .clipped()
    }

    // MARK: - Drone photo with Ken Burns

    @ViewBuilder
    private func dronePhotoLayer(t: Double, size: CGSize) -> some View {
        let kenBurnsScale = 1.0 + 0.015 * CGFloat(sin(t * 0.10) * 0.5 + 0.5)
        if let urlStr = property.photoUrl, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .scaleEffect(kenBurnsScale)
                default:
                    bundledAerialPhoto(scale: kenBurnsScale, size: size)
                }
            }
        } else {
            bundledAerialPhoto(scale: kenBurnsScale, size: size)
        }
    }

    @ViewBuilder
    private func bundledAerialPhoto(scale: CGFloat, size: CGSize) -> some View {
        if let uiImg = UIImage(named: "aerial_property") {
            Image(uiImage: uiImg)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
                .scaleEffect(scale)
        } else {
            Color(red: 0.06, green: 0.12, blue: 0.07)
                .frame(width: size.width, height: size.height)
        }
    }

    // MARK: - Geometry helpers

    private let waterKeywords = [
        "heleșteu", "helesteu", "pond", "lake", "pool", "iaz", "apă", "apa",
        "water", "râu", "rau", "river", "piscina", "bazin"
    ]

    private func waterCentroids(_ size: CGSize) -> [CGPoint] {
        zones
            .filter { z in
                waterKeywords.contains(where: { z.name.lowercased().contains($0) })
            }
            .compactMap { z in
                guard !z.coordinates.isEmpty else { return nil }
                let lats = z.coordinates.map(\.latitude)
                let lons = z.coordinates.map(\.longitude)
                let cLat = (lats.min()! + lats.max()!) / 2
                let cLon = (lons.min()! + lons.max()!) / 2
                return latLon(cLat, cLon, in: size)
            }
    }

    private func latLon(_ lat: Double, _ lon: Double, in size: CGSize) -> CGPoint {
        let (minLat, maxLat, minLon, maxLon) = zoneBounds()
        guard maxLat > minLat, maxLon > minLon else {
            return CGPoint(x: size.width / 2, y: size.height / 2)
        }
        let x = (lon - minLon) / (maxLon - minLon) * Double(size.width)
        let y = (1.0 - (lat - minLat) / (maxLat - minLat)) * Double(size.height)
        return CGPoint(x: x, y: y)
    }

    private func zoneBounds() -> (Double, Double, Double, Double) {
        let coords = zones.flatMap(\.coordinates)
        guard !coords.isEmpty else {
            let lat = property.latitude ?? 44.4
            let lon = property.longitude ?? 26.1
            return (lat - 0.0015, lat + 0.0015, lon - 0.002, lon + 0.002)
        }
        return (
            coords.map(\.latitude).min()!,  coords.map(\.latitude).max()!,
            coords.map(\.longitude).min()!, coords.map(\.longitude).max()!
        )
    }

    private func pinPoint(_ el: PropertyElement, _ size: CGSize) -> CGPoint {
        if let lat = el.latitude, let lon = el.longitude {
            return latLon(lat, lon, in: size)
        }
        return CGPoint(x: el.positionX * Double(size.width),
                       y: el.positionY * Double(size.height))
    }
}

// MARK: - Aerial Element Pin

private struct AerialElementPin: View {
    let element: PropertyElement

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.5))
                .frame(width: 34, height: 34)
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
            Image(systemName: element.elementType.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}
