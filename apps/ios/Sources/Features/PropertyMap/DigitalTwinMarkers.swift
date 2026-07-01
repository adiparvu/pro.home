import SwiftUI

// MARK: - Property home marker

struct PropertyHomeMarker: View {
    var body: some View {
        Image(systemName: "house.fill")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(
                LinearGradient(colors: [Color(red: 0.2, green: 0.7, blue: 0.95),
                                        Color(red: 0.25, green: 0.5, blue: 0.95)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Circle()
            )
            .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 2))
            .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }
}

// MARK: - Zone badge

struct ZoneBadge: View {
    let zone: PropertyZone
    let heatmap: Bool
    let selected: Bool
    let onTap: () -> Void

    private var color: Color { heatmap ? zone.healthColor : zone.tint }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                Image(systemName: zone.icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.95), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: selected ? 2.5 : 1.5))
                    .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
                Text(zone.name)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppSpacing.xs).padding(.vertical, 2)
                    .background(.black.opacity(0.45), in: Capsule())
            }
            .scaleEffect(selected ? 1.12 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Vertex handle

struct VertexHandle: View {
    var body: some View {
        Circle()
            .fill(.white)
            .frame(width: 26, height: 26)
            .overlay(Circle().fill(Color.accentColor).frame(width: 13, height: 13))
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
            .contentShape(Circle())
    }
}

// MARK: - Move handle

struct MoveHandle: View {
    var body: some View {
        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(Color.accentColor, in: Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
            .contentShape(Circle())
    }
}

// MARK: - Object marker

struct ObjectMarker: View {
    let element: PropertyElement

    var body: some View {
        Image(systemName: element.elementType.icon)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(element.healthColor.opacity(0.95), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
            .contentShape(Circle())
    }
}
