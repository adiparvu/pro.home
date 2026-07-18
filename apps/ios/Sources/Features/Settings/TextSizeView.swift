import SwiftUI

// MARK: - Text size (Settings → Aspect → Mărimea textului)
//
// PRVIO's in-app equivalent of iOS Settings → Display & Brightness → Text
// Size: a live preview (a real GlassCard whose text renders at the chosen
// size — what you see is literally what every screen gets), an explicit
// "Folosește mărimea sistemului" toggle (following the system is a stated
// choice, never a magic slider position), and the classic discrete A…A
// slider with tick marks, one haptic per step, and the iOS-style "Mărimi
// mai mari pentru accesibilitate" toggle that extends the range to the
// five accessibility sizes.
//
// Honesty: the preview card carries no special-cased fonts — it uses the
// same AppFont tokens as the rest of the app, so it scales through exactly
// the machinery (TextSizePreference → AppTextScale → AppFont) that scales
// every other screen. If the preview grows, the app grows.

struct TextSizeView: View {
    private var pref: TextSizePreference { .shared }

    /// Whether the slider spans all twelve sizes. Derived from the current
    /// size on appear (like iOS: the toggle is ON whenever an accessibility
    /// size is active), page-local otherwise.
    @State private var showAccessibilitySizes = false

    /// Below the root `.appTextSize()` modifier this reads
    /// `override ?? system` — i.e. whatever the app is rendering right now.
    /// While following the system (override == nil, the only moment it is
    /// used as a seed) it is exactly the system size.
    @Environment(\.dynamicTypeSize) private var environmentSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var effectiveSize: DynamicTypeSize { pref.override ?? environmentSize }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: AppSpacing.xxl) {
                previewSection
                controlSection
                Spacer(minLength: 100)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle(Text("textsize_title"))
        .navigationBarTitleDisplayMode(.large)
        .onAppear { showAccessibilitySizes = effectiveSize.isAccessibilitySize }
    }

    // MARK: Preview — the real glass, the real tokens

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("textsize_preview_section")
                .font(AppFont.captionStrong)
                .foregroundStyle(.secondary)
                .padding(.leading, AppSpacing.sm)

            GlassCard(padding: AppSpacing.xl, cornerRadius: AppRadius.xl) {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("textsize_sample_title")
                        .font(AppFont.headline)
                        .foregroundStyle(.primary)
                    Text("textsize_sample_body")
                        .font(AppFont.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Controls

    private var controlSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SettingsGroup(title: "textsize_section") {
                systemRow
                if pref.override != nil {
                    accessibilitySizesRow
                    sliderRow
                }
            }

            Text("textsize_footer")
                .font(AppFont.caption)
                .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AppSpacing.sm)
        }
    }

    /// "Folosește mărimea sistemului" — ON by default. Turning it OFF seeds
    /// the override with the size already on screen (no visual jump) and
    /// reveals the slider.
    private var systemRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ColoredIconBadge(icon: "textformat.size", color: .brandSkyBlue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("textsize_use_system")
                        .font(AppFont.scaled(15))
                        .foregroundStyle(.primary)
                    Text("textsize_use_system_subtitle")
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("textsize_use_system", isOn: followSystemBinding)
                    .labelsHidden()
                    .tint(.accentColor)
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, 13)

            if pref.override != nil {
                Rectangle()
                    .fill(Color.primary.opacity(AppOpacity.hairline))
                    .frame(height: 0.4)
                    .padding(.leading, 52)
            }
        }
    }

    /// "Mărimi mai mari pentru accesibilitate" — extends the slider to the
    /// five accessibility sizes; turning it OFF clamps an accessibility
    /// override back to the largest standard size, exactly like iOS.
    private var accessibilitySizesRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ColoredIconBadge(icon: "accessibility", color: .brandPrimaryBlue)
                Text("textsize_ax_toggle")
                    .font(AppFont.scaled(15))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Toggle("textsize_ax_toggle", isOn: accessibilitySizesBinding)
                    .labelsHidden()
                    .tint(.accentColor)
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, 13)

            Rectangle()
                .fill(Color.primary.opacity(AppOpacity.hairline))
                .frame(height: 0.4)
                .padding(.leading, 52)
        }
    }

    private var sliderRow: some View {
        VStack(spacing: AppSpacing.md) {
            TextSizeSlider(
                sizes: showAccessibilitySizes ? TextSizePreference.allSizes
                                              : TextSizePreference.standardSizes,
                selection: sliderBinding)

            // The chosen size, stated in words — the visual twin of the
            // slider's VoiceOver value.
            Text(verbatim: TextSizePreference.localizedName(for: effectiveSize))
                .font(AppFont.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)   // the slider already speaks it
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.lg)
    }

    // MARK: Bindings

    private var followSystemBinding: Binding<Bool> {
        Binding(
            get: { pref.override == nil },
            set: { follow in
                HapticFeedback.selection()
                withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
                    if follow {
                        pref.override = nil
                        showAccessibilitySizes = environmentSize.isAccessibilitySize
                    } else {
                        // Seed with what's on screen right now — no jump.
                        pref.override = environmentSize
                        if environmentSize.isAccessibilitySize {
                            showAccessibilitySizes = true
                        }
                    }
                }
            })
    }

    private var accessibilitySizesBinding: Binding<Bool> {
        Binding(
            get: { showAccessibilitySizes },
            set: { on in
                HapticFeedback.selection()
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
                    showAccessibilitySizes = on
                    if !on, pref.isAccessibilityOverride {
                        pref.override = .xxxLarge
                    }
                }
            })
    }

    private var sliderBinding: Binding<DynamicTypeSize> {
        Binding(
            get: { effectiveSize },
            set: { pref.override = $0 })
    }
}

// MARK: - Discrete A…A slider

/// The classic iOS text-size control: a small-A / large-A pair flanking a
/// track with one tick per size, a snapping thumb, and a selection haptic
/// per step. One VoiceOver element — adjustable, with the size's name as
/// its value.
private struct TextSizeSlider: View {
    let sizes: [DynamicTypeSize]
    @Binding var selection: DynamicTypeSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let thumbDiameter: CGFloat = 28
    private static let trackHeight: CGFloat = 4
    private static let tickHeight: CGFloat = 10

    /// A selection outside the visible range (an accessibility size while
    /// the toggle is off, mid-animation) pins the thumb to the last tick.
    private var index: Int {
        sizes.firstIndex(of: selection) ?? sizes.count - 1
    }

    var body: some View {
        HStack(spacing: AppSpacing.base) {
            endpointGlyph(pointSize: 13)
            track
            endpointGlyph(pointSize: 24)
        }
        .frame(height: 44)
        .accessibilityElement()
        .accessibilityLabel(Text("textsize_title"))
        .accessibilityValue(Text(verbatim: TextSizePreference.localizedName(for: selection)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: select(index + 1)
            case .decrement: select(index - 1)
            @unknown default: break
            }
        }
    }

    /// The endpoint "A"s are the scale's reference marks, so they are
    /// deliberately frozen (`Font.system(size:)`, not an AppFont token) —
    /// scaling them with the selection would move the goalposts. iOS's own
    /// slider anchors behave the same way.
    private func endpointGlyph(pointSize: CGFloat) -> some View {
        Text(verbatim: "A")
            .font(Font.system(size: pointSize, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private var track: some View {
        // GeometryReader is required here: snapping needs the real track
        // width for finger→tick math. It is confined to this fixed-height
        // control, so it costs one measurement, not a layout cascade.
        GeometryReader { geo in
            // max(…, 1) guards the zero-width first layout pass — a NaN
            // position would poison the whole ZStack.
            let usable = max(geo.size.width - Self.thumbDiameter, 1)
            let stepWidth = usable / CGFloat(sizes.count - 1)
            let midY = geo.size.height / 2

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: Self.trackHeight)

                ForEach(0..<sizes.count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 0.5)
                        .fill(Color.primary.opacity(0.22))
                        .frame(width: 1, height: Self.tickHeight)
                        .position(x: Self.thumbDiameter / 2 + CGFloat(i) * stepWidth,
                                  y: midY)
                }

                Circle()
                    .fill(.white)
                    .frame(width: Self.thumbDiameter, height: Self.thumbDiameter)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.04), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 1)
                    .offset(x: CGFloat(index) * stepWidth)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let raw = (gesture.location.x - Self.thumbDiameter / 2) / stepWidth
                        select(Int(raw.rounded()))
                    })
        }
        .frame(height: 44)
    }

    private func select(_ rawIndex: Int) {
        let clamped = min(max(rawIndex, 0), sizes.count - 1)
        guard sizes[clamped] != selection else { return }
        HapticFeedback.selection()
        if reduceMotion {
            selection = sizes[clamped]
        } else {
            withAnimation(.smooth(duration: 0.18)) { selection = sizes[clamped] }
        }
    }
}
