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

struct AerialCanvasView: View {
    let property: PropertyModel
    let elements: [PropertyElement]
    var interactive: Bool = false
    var pinMode: Bool = false
    var onElementTap: (PropertyElement) -> Void = { _ in }
    var onCanvasTap: (CGPoint) -> Void = { _ in }
    var onElementMove: (PropertyElement, CGPoint) -> Void = { _, _ in }

    @State private var dragId: UUID? = nil
    @State private var dragPos: CGPoint = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                aerialImage(size: geo.size)

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

                // Element pins
                ForEach(elements) { el in
                    pinView(el, size: geo.size)
                }

                if interactive && pinMode { placeBanner }
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
        let pin = AerialElementPin(element: el, dragging: dragId == el.id)
            .position(pinPoint(el, size))
        if interactive {
            pin
                .highPriorityGesture(dragGesture(el, size))
                .onTapGesture { if dragId == nil { onElementTap(el) } }
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

    private func pinPoint(_ el: PropertyElement, _ size: CGSize) -> CGPoint {
        if dragId == el.id { return dragPos }
        // Legacy elements with no normalised position default to centre.
        let nx = (el.positionX == 0 && el.positionY == 0) ? 0.5 : el.positionX
        let ny = (el.positionX == 0 && el.positionY == 0) ? 0.5 : el.positionY
        return CGPoint(x: nx * size.width, y: ny * size.height)
    }

    private func clampNorm(_ p: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(p.x / max(size.width, 1), 0), 1),
            y: min(max(p.y / max(size.height, 1), 0), 1)
        )
    }

    // MARK: - Banner

    private var placeBanner: some View {
        VStack {
            HStack(spacing: 6) {
                Image(systemName: "hand.tap.fill")
                Text("Tap the photo to place an element")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(.black.opacity(0.65), in: Capsule())
            .padding(.top, 14)
            Spacer()
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Aerial Element Pin

private struct AerialElementPin: View {
    let element: PropertyElement
    var dragging: Bool = false

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(element.elementType.accentColor)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                Image(systemName: element.elementType.icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }
            .scaleEffect(dragging ? 1.25 : 1.0)

            Text(element.name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.black.opacity(0.55), in: Capsule())
        }
        .animation(.spring(response: 0.25), value: dragging)
    }
}
