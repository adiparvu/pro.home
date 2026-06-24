import SwiftUI

// MARK: - liquidGlass() — universal adaptive glass modifier
//
// On iOS 26+: uses native Liquid Glass (.glassEffect) which automatically
//   adapts to the content beneath, respects dark/light mode, reduceTransparency,
//   increaseContrast, and any future Liquid Glass updates from Apple.
// On iOS 17–25: falls back to .ultraThinMaterial / .regularMaterial which are
//   system-managed and equally respect all accessibility and appearance settings.
//
// Never use fixed opacity, blur, or colour values for glass — the system
// determines the visual result automatically.

extension View {
    @ViewBuilder
    func liquidGlass(cornerRadius: CGFloat = 24, thick: Bool = false) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            self
                .background(thick ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.ultraThinMaterial),
                            in: shape)
                .shadow(color: Color.primary.opacity(0.07), radius: 20, y: 5)
                .shadow(color: Color.primary.opacity(0.03), radius: 3, y: 1)
        }
    }

    /// Native Liquid Glass for circular icon buttons (iOS 26+), with a
    /// system-material fallback on older versions. Use instead of manually
    /// layering `.ultraThinMaterial` + a stroke border.
    @ViewBuilder
    func glassCircle() -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(in: Circle())
        } else {
            self
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        }
    }

    /// Native Liquid Glass for pill-shaped buttons (iOS 26+), with fallback.
    @ViewBuilder
    func glassCapsule() -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(in: Capsule())
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        }
    }

    /// Native Liquid Glass for rounded-rect icon buttons (iOS 26+), with fallback.
    @ViewBuilder
    func glassRoundedRect(_ cornerRadius: CGFloat = 12) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26, *) {
            self.glassEffect(in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        }
    }
}

// MARK: - GlassCard

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 20
    var cornerRadius: CGFloat = 24
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .liquidGlass(cornerRadius: cornerRadius)
    }
}

// MARK: - HeavyGlassCard (modal sheets, prominent panels)

struct HeavyGlassCard<Content: View>: View {
    var padding: CGFloat = 20
    var cornerRadius: CGFloat = 24
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .liquidGlass(cornerRadius: cornerRadius, thick: true)
    }
}

// MARK: - StatRow

struct StatRow: View {
    let label: LocalizedStringKey
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

// MARK: - IconBadge

struct IconBadge: View {
    let icon: String
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.primary.opacity(0.18),
                        in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
    }
}
