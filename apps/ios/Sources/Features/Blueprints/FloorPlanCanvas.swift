import SwiftUI

// MARK: - Interactive 2D floor plan (Plans & 3D rebuild, phase C)
//
// Renders a level's rooms as tiles positioned by their percent rectangles
// (the geometry the schema always had). Rooms that were never placed get a
// deterministic auto-grid slot so the plan is useful from the first day —
// the moment the owner drags a tile in edit mode, its real rectangle
// persists. Tiles tint by the matching Digital Twin zone's health when a
// zone shares the room's name; otherwise by room kind.

struct LevelPlanCanvas: View {
    let rooms: [RoomRecord]
    /// Digital Twin health for a room (nil = no matching zone).
    let healthFor: (RoomRecord) -> Int?
    let isEditing: Bool
    let onTap: (RoomRecord) -> Void
    /// Fired on drag/resize end with the new percent rectangle (0–100).
    let onGeometryChange: (RoomRecord, CGRect) -> Void

    /// In-flight gesture state, keyed by room id (0–1 canvas space).
    @State private var liveRects: [UUID: CGRect] = [:]

    private static let aspect: CGFloat = 4.0 / 3.0

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                // Graph-paper backdrop — reads as a plan, not a list.
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                gridLines(in: size)

                ForEach(Array(rooms.enumerated()), id: \.element.id) { index, room in
                    let rect = liveRects[room.id] ?? Self.rect(for: room, index: index)
                    tile(room, rect: rect, canvas: size)
                }
            }
        }
        .aspectRatio(Self.aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .strokeBorder(Color.primary.opacity(AppOpacity.hairline), lineWidth: 0.5)
        )
    }

    // MARK: Layout

    /// The room's rectangle in 0–1 canvas space: the stored percents when
    /// present, otherwise a deterministic 3-column grid slot.
    static func rect(for room: RoomRecord, index: Int) -> CGRect {
        if let x = room.xPct, let y = room.yPct,
           let w = room.widthPct, let h = room.heightPct, w > 0, h > 0 {
            return CGRect(x: x / 100, y: y / 100, width: w / 100, height: h / 100)
        }
        let column = index % 3
        let row = index / 3
        return CGRect(x: 0.04 + Double(column) * 0.32,
                      y: 0.05 + Double(row) * 0.24,
                      width: 0.28, height: 0.20)
    }

    private func gridLines(in size: CGSize) -> some View {
        Canvas { context, _ in
            let step: CGFloat = size.width / 12
            var path = Path()
            var x: CGFloat = step
            while x < size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = step
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            context.stroke(path, with: .color(.primary.opacity(0.04)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }

    // MARK: Tile

    private func tile(_ room: RoomRecord, rect: CGRect, canvas: CGSize) -> some View {
        let frame = CGRect(x: rect.minX * canvas.width, y: rect.minY * canvas.height,
                           width: rect.width * canvas.width, height: rect.height * canvas.height)
        let tint = tint(for: room)
        return RoomTile(room: room, tint: tint, showsName: frame.width > 64)
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .overlay(alignment: .bottomTrailing) {
                if isEditing {
                    resizeHandle(room, rect: rect, canvas: canvas)
                        .offset(x: frame.minX + frame.width - 12,
                                y: frame.minY + frame.height - 12)
                        // The handle overlay spans the whole canvas; pin it
                        // onto the tile's corner instead.
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .onTapGesture {
                guard !isEditing else { return }
                onTap(room)
            }
            .gesture(isEditing ? moveGesture(room, rect: rect, canvas: canvas) : nil)
            .animation(.snappy(duration: 0.2), value: isEditing)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: room.name))
    }

    private func tint(for room: RoomRecord) -> Color {
        if let health = healthFor(room) {
            if health >= 80 { return Color.brandSuccess }
            if health >= 50 { return .orange }
            return Color.brandDanger
        }
        return RoomKind.color(room.roomType)
    }

    // MARK: Gestures

    private func moveGesture(_ room: RoomRecord, rect: CGRect, canvas: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                var next = rect
                next.origin.x = clamp(rect.minX + value.translation.width / canvas.width,
                                      0, 1 - rect.width)
                next.origin.y = clamp(rect.minY + value.translation.height / canvas.height,
                                      0, 1 - rect.height)
                liveRects[room.id] = next
            }
            .onEnded { _ in
                commit(room)
            }
    }

    private func resizeHandle(_ room: RoomRecord, rect: CGRect, canvas: CGSize) -> some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 22, height: 22)
            .overlay(
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        var next = liveRects[room.id] ?? rect
                        next.size.width = clamp(rect.width + value.translation.width / canvas.width,
                                                0.10, 1 - rect.minX)
                        next.size.height = clamp(rect.height + value.translation.height / canvas.height,
                                                 0.08, 1 - rect.minY)
                        liveRects[room.id] = next
                    }
                    .onEnded { _ in
                        commit(room)
                    }
            )
    }

    private func commit(_ room: RoomRecord) {
        guard let rect = liveRects[room.id] else { return }
        onGeometryChange(room, CGRect(x: rect.minX * 100, y: rect.minY * 100,
                                      width: rect.width * 100, height: rect.height * 100))
        // Keep the live rect until the service round-trips the new percents;
        // it is superseded naturally on the next external reload.
    }

    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(max(v, lo), max(lo, hi))
    }
}

// MARK: - Room tile

private struct RoomTile: View {
    let room: RoomRecord
    let tint: Color
    let showsName: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .fill(tint.opacity(0.18))
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .strokeBorder(tint.opacity(0.55), lineWidth: 1.5)
            VStack(spacing: 3) {
                Image(systemName: room.kindIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                if showsName {
                    Text(room.name)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 3)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if room.hasScan {
                Image(systemName: "cube.transparent.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.purple)
                    .padding(3)
            }
        }
    }
}
