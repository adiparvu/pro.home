import SwiftUI

// MARK: - Liquid Glass Card (iOS 26/27)

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 20
    var cornerRadius: CGFloat = 24
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    // Specular shimmer — top-leading light catch
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(LinearGradient(
                                colors: [.white.opacity(0.18), .clear, .white.opacity(0.04)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                    }
                    // Gradient border
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(LinearGradient(
                                colors: [.white.opacity(0.40), .white.opacity(0.08), .clear],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ), lineWidth: 0.8)
                    }
            }
            .shadow(color: .black.opacity(0.18), radius: 28, x: 0, y: 8)
            .shadow(color: .black.opacity(0.07), radius: 4,  x: 0, y: 1)
    }
}

// MARK: - Heavy Glass (modal sheets, prominent panels)

struct HeavyGlassCard<Content: View>: View {
    var padding: CGFloat = 20
    var cornerRadius: CGFloat = 24
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(LinearGradient(
                                colors: [.white.opacity(0.12), .clear],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(LinearGradient(
                                colors: [.white.opacity(0.35), .white.opacity(0.06)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ), lineWidth: 0.8)
                    }
            }
            .shadow(color: .black.opacity(0.22), radius: 32, x: 0, y: 10)
    }
}

// MARK: - Stat Row

struct StatRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(valueColor)
        }
    }
}

// MARK: - Icon Badge

struct IconBadge: View {
    let icon: String
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.primary.opacity(0.25), in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
    }
}
