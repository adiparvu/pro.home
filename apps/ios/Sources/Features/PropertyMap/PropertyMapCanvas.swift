import SwiftUI

struct PropertyMapCanvas: View {
    let elements: [PropertyElement]
    let isEditMode: Bool
    var onTap: (PropertyElement) -> Void
    var onLongPress: (CGPoint) -> Void
    var onMove: (PropertyElement, Double, Double) -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var draggingId: UUID? = nil
    @State private var draggingPos: CGPoint = .zero

    private let canvasRatio: CGFloat = 4.0 / 3.0   // landscape canvas

    var body: some View {
        GeometryReader { geo in
            let canvasW = geo.size.width
            let canvasH = canvasW / canvasRatio

            ScrollView([]) {
                ZStack {
                    // ── Background canvas ─────────────────────────────────
                    MapBackground()
                        .frame(width: canvasW, height: canvasH)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 0.4) {
                            // handled per-element or blank tap
                        }

                    // ── Element pins ──────────────────────────────────────
                    ForEach(elements) { element in
                        let pinX = element.positionX * canvasW
                        let pinY = element.positionY * canvasH
                        let isDragging = draggingId == element.id

                        ElementPin(
                            element: element,
                            isEditMode: isEditMode,
                            isDragging: isDragging
                        )
                        .position(isDragging ? draggingPos : CGPoint(x: pinX, y: pinY))
                        .gesture(
                            isEditMode
                            ? DragGesture(minimumDistance: 4)
                                .onChanged { val in
                                    if draggingId == nil {
                                        draggingId = element.id
                                        draggingPos = CGPoint(x: pinX, y: pinY)
                                    }
                                    if draggingId == element.id {
                                        draggingPos = CGPoint(
                                            x: (pinX + val.translation.width).clamped(to: 28...(canvasW - 28)),
                                            y: (pinY + val.translation.height).clamped(to: 28...(canvasH - 28))
                                        )
                                    }
                                }
                                .onEnded { val in
                                    guard draggingId == element.id else { return }
                                    let newX = (draggingPos.x / canvasW).clamped(to: 0.03...0.97)
                                    let newY = (draggingPos.y / canvasH).clamped(to: 0.03...0.97)
                                    onMove(element, newX, newY)
                                    draggingId = nil
                                }
                            : nil
                        )
                        .onTapGesture {
                            guard draggingId == nil else { return }
                            onTap(element)
                        }
                        .animation(.spring(response: 0.3), value: isDragging)
                    }

                    // ── Empty state overlay ───────────────────────────────
                    if elements.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "map")
                                .font(.system(size: 40))
                                .foregroundStyle(Color.primary.opacity(0.2))
                            Text("No elements on map")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if isEditMode {
                                Text("Tap + to add the first element")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.center)
                            } else {
                                Text("Enable edit mode to add elements")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(AppSpacing.xxl)
                    }
                }
                .frame(width: canvasW, height: canvasH)
            }
            .frame(width: canvasW, height: canvasH)
            .scaleEffect(scale)
            .gesture(
                MagnificationGesture()
                    .onChanged { val in
                        scale = (lastScale * val).clamped(to: 0.8...2.5)
                    }
                    .onEnded { _ in lastScale = scale }
            )
        }
        .aspectRatio(canvasRatio, contentMode: .fit)
    }
}

// MARK: - MapBackground

private struct MapBackground: View {
    var body: some View {
        ZStack {
            // Ground
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.13, blue: 0.10),
                    Color(red: 0.05, green: 0.09, blue: 0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Subtle grid
            GeometryReader { geo in
                Canvas { ctx, size in
                    let step: CGFloat = 40
                    var x: CGFloat = 0
                    while x < size.width {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        ctx.stroke(path, with: .color(Color.primary.opacity(0.04)), lineWidth: 0.5)
                        x += step
                    }
                    var y: CGFloat = 0
                    while y < size.height {
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                        ctx.stroke(path, with: .color(Color.primary.opacity(0.04)), lineWidth: 0.5)
                        y += step
                    }
                }
            }

            // Property boundary hint
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.primary.opacity(0.18), Color.primary.opacity(AppOpacity.hairline)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 1.5, dash: [8, 6])
                    )
                    .padding(AppSpacing.lg)
            }
        }
    }
}

// MARK: - ElementPin

private struct ElementPin: View {
    let element: PropertyElement
    let isEditMode: Bool
    let isDragging: Bool

    @State private var appear = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Glow
                Circle()
                    .fill(element.elementType.accentColor.opacity(isDragging ? 0.35 : 0.15))
                    .frame(width: isDragging ? 60 : 46, height: isDragging ? 60 : 46)
                    .blur(radius: isDragging ? 8 : 4)

                // Pin circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [element.elementType.accentColor, element.elementType.accentColor.opacity(0.7)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: isDragging ? 48 : 38, height: isDragging ? 48 : 38)
                    .overlay(
                        Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: element.elementType.accentColor.opacity(0.5), radius: isDragging ? 12 : 6, y: 2)

                // Icon
                Image(systemName: element.elementType.icon)
                    .font(.system(size: isDragging ? 20 : 15, weight: .semibold))
                    .foregroundStyle(.primary)

                // Health score ring
                Circle()
                    .trim(from: 0, to: CGFloat(element.healthScore) / 100)
                    .stroke(element.healthColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: isDragging ? 52 : 42, height: isDragging ? 52 : 42)
                    .rotationEffect(.degrees(-90))

                // Edit mode indicator
                if isEditMode {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.primary)
                        .padding(3)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                        .offset(x: 13, y: -13)
                }
            }

            // Label
            Text(element.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.9))
                .lineLimit(1)
                .padding(.horizontal, AppSpacing.xs)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(Color.black.opacity(0.45))
                )
                .shadow(color: .black.opacity(0.4), radius: 2)
        }
        .scaleEffect(appear ? 1 : 0.3)
        .opacity(appear ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.65).delay(Double.random(in: 0...0.2))) {
                appear = true
            }
        }
    }
}

// MARK: - Comparable clamp helper

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
