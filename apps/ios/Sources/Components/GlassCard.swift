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
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26, *) {
            self.glassEffect(in: shape).contentShape(shape)
        } else {
            self.modifier(LegacyGlass(shape: shape, thick: thick, shadowed: true))
        }
    }

    /// Native Liquid Glass for circular icon buttons (iOS 26+), with a
    /// system-material fallback on older versions. Use instead of manually
    /// layering `.ultraThinMaterial` + a stroke border.
    @ViewBuilder
    func glassCircle() -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(in: Circle()).contentShape(Circle())
        } else {
            self.modifier(LegacyGlass(shape: Circle(), stroked: true))
        }
    }

    /// Native Liquid Glass for pill-shaped buttons (iOS 26+), with fallback.
    @ViewBuilder
    func glassCapsule() -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(in: Capsule()).contentShape(Capsule())
        } else {
            self.modifier(LegacyGlass(shape: Capsule(), stroked: true))
        }
    }

    /// Native Liquid Glass for rounded-rect icon buttons (iOS 26+), with fallback.
    @ViewBuilder
    func glassRoundedRect(_ cornerRadius: CGFloat = 12) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26, *) {
            self.glassEffect(in: shape).contentShape(shape)
        } else {
            self.modifier(LegacyGlass(shape: shape, stroked: true))
        }
    }

    /// CLEAR Liquid Glass (iOS 26+) for controls floating over media-rich
    /// content — the chat compose bar over a wallpaper is exactly the case
    /// the HIG's Clear variant exists for. Interactive glass reacts to touch;
    /// use it for buttons, not for containers holding a text field. Pre-26
    /// falls back to regular material + hairline + shadow (the treatment
    /// that made the bar legible on any wallpaper brightness).
    @ViewBuilder
    func mediaGlass<S: InsettableShape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(interactive ? Glass.clear.interactive() : .clear, in: shape)
                .contentShape(shape)
        } else {
            self.background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.7))
                .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
                .contentShape(shape)
        }
    }
}

/// The pre-iOS-26 glass fallback. On iOS 26+ the native `glassEffect`
/// handles Reduce Transparency itself; here we honor it explicitly — when
/// the user asks for less transparency, glass becomes an opaque elevated
/// surface with identical geometry, instead of a blur they struggle to
/// read through.
private struct LegacyGlass<S: InsettableShape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let shape: S
    var thick = false
    var stroked = false
    var shadowed = false

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color(.secondarySystemBackground), in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                .contentShape(shape)
        } else if stroked {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                .contentShape(shape)
        } else {
            content
                .background(thick ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(.ultraThinMaterial),
                            in: shape)
                .shadow(color: Color.primary.opacity(AppOpacity.subtleFill), radius: shadowed ? 20 : 0, y: shadowed ? 5 : 0)
                .shadow(color: Color.primary.opacity(0.03), radius: shadowed ? 3 : 0, y: shadowed ? 1 : 0)
                .contentShape(shape)
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
