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

// MARK: - Glass action button (the Contacts-card circles)
//
// The ONLY sanctioned shape for icon action buttons: a Liquid Glass circle
// (native glassEffect on iOS 26, material fallback earlier) with a white/
// primary glyph and an 11pt label beneath — Apple's own contact-card row.
// Never ship tinted rounded-rect action chips again.
struct GlassActionButton: View {
    let icon: String
    let label: LocalizedStringKey
    var action: () -> Void

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            action()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(AppFont.scaled(17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 52, height: 52)
                    .glassCircle()
                Text(label)
                    .font(AppFont.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

// MARK: - GlassWideButton
//
// The sanctioned full-width primary action — "Generate PDF", "Share",
// "Save" — as a clear interactive Liquid Glass capsule with a monochrome
// label. Never a tinted or gradient rectangle: prominence comes from
// size and placement, the material stays native and adapts to iOS.
struct GlassWideButton: View {
    var icon: String? = nil
    let label: LocalizedStringKey
    /// Shows a spinner and disables the button (e.g. while exporting).
    var isBusy: Bool = false
    var action: () -> Void

    var body: some View {
        Button {
            HapticFeedback.impact(.medium)
            action()
        } label: {
            HStack(spacing: 10) {
                if isBusy {
                    ProgressView()
                } else {
                    if let icon {
                        Image(systemName: icon)
                            .font(AppFont.headline)
                    }
                    Text(label)
                        .font(AppFont.headline)
                }
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .mediaGlass(in: Capsule(), interactive: true)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel(Text(label))
    }
}

// MARK: - GlassFilterChip
//
// The ONE sanctioned segmented filter/category chip — the "Toate / HVAC /
// Bucătărie…" rows that appear across the app. Both states are native Liquid
// Glass: the selected chip carries an accent-tinted glass + bold accent label,
// the rest are plain glass with a primary label. Never a solid tinted pill
// again; selection reads through the material and the label weight/colour.
struct GlassFilterChip: View {
    let label: String
    /// Optional leading SF Symbol (e.g. a category glyph).
    var systemImage: String? = nil
    /// Optional trailing count badge; hidden when nil or zero.
    var count: Int? = nil
    let isSelected: Bool
    var action: () -> Void

    private var tint: Color { isSelected ? Color.accentColor : Color.primary.opacity(AppOpacity.emphasis) }

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            action()
        } label: {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(AppFont.scaled(11, weight: isSelected ? .semibold : .medium))
                }
                Text(verbatim: label)
                    .font(AppFont.scaled(13, weight: isSelected ? .semibold : .regular))
                if let count, count > 0 {
                    Text(verbatim: "\(count)")
                        .font(AppFont.scaled(11, weight: .bold))
                        .monospacedDigit()
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(tint.opacity(0.16), in: Capsule())
                }
            }
            .foregroundStyle(tint)
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, 7)
            .glassFilterCapsule(selected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: count.map { "\(label), \($0)" } ?? label))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

extension View {
    /// Capsule glass for a filter chip. Selected → accent-tinted interactive
    /// glass (iOS 26) / accent-ringed material (fallback); unselected → plain
    /// glass / hairline material. Keeps the accent label legible on both.
    @ViewBuilder
    func glassFilterCapsule(selected: Bool) -> some View {
        if #available(iOS 26, *) {
            if selected {
                self.glassEffect(Glass.regular.tint(Color.accentColor.opacity(0.22)).interactive(),
                                 in: Capsule())
                    .contentShape(Capsule())
            } else {
                self.glassEffect(.regular.interactive(), in: Capsule())
                    .contentShape(Capsule())
            }
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(
                    selected ? Color.accentColor.opacity(0.9) : Color.primary.opacity(0.1),
                    lineWidth: selected ? 1.5 : 0.5))
                .contentShape(Capsule())
        }
    }

    /// Rounded-rect sibling of `glassFilterCapsule` for tile-shaped filters —
    /// stat tiles that double as toggleable filters (e.g. the inventory
    /// summary bar). Same selection language: accent-tinted interactive glass
    /// on iOS 26, accent ring on the material fallback.
    @ViewBuilder
    func glassFilterRoundedRect(selected: Bool, cornerRadius: CGFloat = AppRadius.lg) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26, *) {
            if selected {
                self.glassEffect(Glass.regular.tint(Color.accentColor.opacity(0.22)).interactive(),
                                 in: shape)
                    .contentShape(shape)
            } else {
                self.glassEffect(.regular.interactive(), in: shape)
                    .contentShape(shape)
            }
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(
                    selected ? Color.accentColor.opacity(0.9) : Color.primary.opacity(0.1),
                    lineWidth: selected ? 1.5 : 0.5))
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
