import SwiftUI

// MARK: - liquidGlass() — the content-layer card surface
//
// THE LAYERING CONTRACT (HIG Materials, WWDC26): Liquid Glass belongs to
// the FUNCTIONAL layer — controls and navigation floating above content
// (toolbars, FABs, the composer, filter chips). Passive content surfaces —
// cards, tiles, list rows — use standard system Materials. So the
// non-interactive path here renders material on EVERY OS version (the
// same treatment pre-26 devices always had), and `.glassEffect` is
// reserved for `interactive: true` button chrome. Dozens of simultaneous
// glass effects also carry a real per-frame compositor cost Apple warns
// about — content cards were paying it for nothing.
//
// Never use fixed opacity, blur, or colour values for glass — the system
// determines the visual result automatically.

extension View {
    /// `interactive: true` — for glass that IS a button's chrome: on iOS 26
    /// the material deforms and shimmers under the finger like system
    /// controls. Non-interactive callers are content-layer surfaces and
    /// render standard material by contract (see the layering note above).
    @ViewBuilder
    func liquidGlass(cornerRadius: CGFloat = 24, thick: Bool = false,
                     interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26, *), interactive {
            self.glassEffect(Glass.regular.interactive(), in: shape)
                .contentShape(shape)
        } else {
            self.modifier(LegacyGlass(shape: shape, thick: thick, shadowed: true))
        }
    }

    /// Native Liquid Glass for circular icon buttons (iOS 26+), with a
    /// system-material fallback on older versions. Use instead of manually
    /// layering `.ultraThinMaterial` + a stroke border.
    /// Pass `interactive: true` when the circle is tappable button chrome —
    /// the glass then responds to touch like system Liquid Glass buttons.
    @ViewBuilder
    func glassCircle(interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(interactive ? Glass.regular.interactive() : .regular, in: Circle())
                .contentShape(Circle())
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

    /// REGULAR Liquid Glass for functional chrome that must stay legible
    /// over ANY wallpaper — the chat composer's pill and its controls.
    /// Clear glass is gorgeous over media but disappears on bright, busy
    /// wallpapers (IMG_8532); Regular carries the HIG's adaptive
    /// legibility layer, so the pill separates from whatever sits behind
    /// it. A hairline stroke defines the edge the way the pre-26 fallback
    /// always did. Fallback = the same treatment as `mediaGlass`.
    @ViewBuilder
    func legibleMediaGlass<S: InsettableShape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(interactive ? Glass.regular.interactive() : .regular, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.7))
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
                    .glassCircle(interactive: true)
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
    /// Disabled keeps the glass and drops the label to secondary — callers
    /// must never fake the state with `.opacity` over the whole button.
    var isEnabled: Bool = true
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
            .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .mediaGlass(in: Capsule(), interactive: true)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isBusy || !isEnabled)
        .accessibilityLabel(Text(label))
    }
}

// MARK: - GlassProminentIconButton
//
// The ONE sanctioned CONFIRM control for toolbars and sheet headers — the
// Save/checkmark circle. Enabled: accent-tinted interactive Liquid Glass
// with a white glyph. Disabled: the glass stays glass and only the glyph
// drops to secondary — never `.opacity` over a colored fill (the washed
// lavender disc of IMG_8288).
struct GlassProminentIconButton: View {
    let systemImage: String
    var size: CGFloat = 38
    var isEnabled: Bool = true
    /// Shows a spinner and disables the button (e.g. while saving).
    var isBusy: Bool = false
    let accessibilityLabel: LocalizedStringKey
    var action: () -> Void

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            action()
        } label: {
            Group {
                if isBusy {
                    ProgressView()
                } else {
                    Image(systemName: systemImage)
                        .font(AppFont.scaled(16, weight: .bold))
                        .foregroundStyle(isEnabled ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                }
            }
            .frame(width: size, height: size)
            .glassProminent(in: Circle(), enabled: isEnabled && !isBusy)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isBusy)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

extension View {
    /// Accent-tinted interactive Liquid Glass behind a PRIMARY action
    /// (Save, Sign In, Schedule…). Disabled keeps plain glass — state is
    /// carried by the label color, exactly like system buttons, never by
    /// dimming a colored fill. Pre-26 falls back to an accent gradient /
    /// hairline material pair with the same contract.
    @ViewBuilder
    func glassProminent<S: InsettableShape>(in shape: S, enabled: Bool = true) -> some View {
        if #available(iOS 26, *) {
            if enabled {
                self.glassEffect(Glass.regular.tint(Color.accentColor.opacity(0.85)).interactive(),
                                 in: shape)
                    .contentShape(shape)
            } else {
                self.glassEffect(.regular, in: shape)
                    .contentShape(shape)
            }
        } else {
            self.background(enabled ? AnyShapeStyle(Color.accentColor.gradient)
                                    : AnyShapeStyle(.ultraThinMaterial),
                            in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(enabled ? 0 : 0.1), lineWidth: 0.5))
                .contentShape(shape)
        }
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
