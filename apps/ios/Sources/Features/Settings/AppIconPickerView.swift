import SwiftUI

// MARK: - App Icon Picker
//
// The Tide Guide layout, faithfully: a title + one-line promise, a paging
// carousel with ONE hero icon centered and the next family peeking from the
// edge, a compact position capsule (19 families would overflow a dot pager),
// a row of circular "tint" swatches — the current family's variant designs —
// and a full-width glass pill that reads "Active" when the shown icon is the
// installed one. The moon button previews the night face of paired themes;
// with the auto day/night switch off it also picks which face gets installed.

struct AppIconPickerView: View {
    @Environment(IconManager.self) private var iconManager
    @Environment(\.colorScheme) private var colorScheme

    private let families = AppIconFamilies.all

    /// The family the carousel is resting on (scroll-position binding).
    @State private var familyID: String?
    /// Chosen variant per family, so browsing away and back keeps the pick.
    @State private var variantByFamily: [String: String] = [:]
    /// Face choice for the shown pair: nil = automatic day/night, a face =
    /// exactly that half gets installed and stays, whatever the appearance.
    @State private var pickedFace: IconFace?
    @State private var showError = false

    private var ro: Bool { Locale.appIsRomanian }

    private var currentFamily: IconFamily {
        families.first { $0.id == familyID } ?? families[0]
    }

    private func variant(of family: IconFamily) -> AppIconTheme {
        family.variants.first { $0.id == variantByFamily[family.id] } ?? family.variants[0]
    }

    private var current: AppIconTheme { variant(of: currentFamily) }

    /// Pairs always install the face matching the system appearance —
    /// day/night switching just happens, like the primary icon.
    private var appliesDarkFace: Bool { current.hasPair && colorScheme == .dark }

    /// The face the big preview shows: the explicit pick wins, otherwise the
    /// system appearance.
    private var previewsDarkFace: Bool { pickedFace.map { $0 == .dark } ?? (colorScheme == .dark) }

    private var isApplied: Bool {
        iconManager.selected.id == current.id
            && iconManager.pinnedFace == (current.hasPair ? pickedFace : nil)
            && iconManager.appliedIconName == iconManager.expectedName(for: current, isDark: appliesDarkFace)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBlock
            Spacer(minLength: AppSpacing.md)
            carousel
            pagerCapsule
                .frame(maxWidth: .infinity)
                .padding(.top, AppSpacing.lg)
            Spacer(minLength: AppSpacing.md)
            variantRow
            if current.hasPair {
                facePicker
                    .padding(.top, AppSpacing.md)
            }
            applyBar
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // The day/night toggle is gone from the UI: paired icons simply
            // follow the system appearance, so the switch is always on.
            iconManager.autoSwitch = true
            let installed = iconManager.selected
            let family = AppIconFamilies.family(containing: installed.id)
            familyID = family.id
            variantByFamily[family.id] = installed.id
            pickedFace = iconManager.pinnedFace
        }
        .onChange(of: familyID) { _, _ in
            HapticFeedback.selection()
            syncPickedFace()
        }
        .onChange(of: variantByFamily) { _, _ in syncPickedFace() }
        .alert(ro ? "Iconițele nu sunt disponibile" : "Icons not available",
               isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(ro ? "Dispozitivul nu permite schimbarea iconiței aplicației."
                    : "This device doesn't allow changing the app icon.")
        }
    }

    // MARK: Title

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ro ? "Personalizează iconița" : "Customize Your Icon")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.primary)
            Text(ro ? "Alege iconița și nuanța care arată așa cum vrei tu PRVIO pe ecranul principal."
                    : "Pick an icon and tint that matches how you want PRVIO to look on your Home Screen.")
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.top, AppSpacing.sm)
    }

    // MARK: Carousel — one hero per family, neighbour peeking at the edge

    private var carousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: AppSpacing.lg) {
                ForEach(families) { family in
                    heroArtwork(for: family)
                        .containerRelativeFrame(.horizontal)
                        .scrollTransition { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.85)
                                .opacity(phase.isIdentity ? 1 : 0.5)
                        }
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, 44, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $familyID)
        .frame(height: 320)
    }

    private func heroArtwork(for family: IconFamily) -> some View {
        let theme = variant(of: family)
        // Paired themes show the explicitly picked face on the current page,
        // otherwise the face matching the system appearance. No identity
        // tricks here: an .id() swap inside the lazy carousel used to break
        // the scroll targets (frozen slides, page stuck after applying).
        let dark = family.id == currentFamily.id ? previewsDarkFace : (colorScheme == .dark)
        let asset = dark ? (theme.darkPreview ?? theme.lightPreview)
                         : theme.lightPreview
        return IconArtwork(name: asset, size: 300)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(Text(theme.name))
    }

    /// Keep the face choice honest while browsing: on the installed theme it
    /// mirrors what is actually pinned, elsewhere it resets to automatic.
    private func syncPickedFace() {
        pickedFace = current.id == iconManager.selected.id ? iconManager.pinnedFace : nil
    }

    // MARK: Position capsule (19 families — a dot pager can't fit)

    private var pagerCapsule: some View {
        let index = families.firstIndex(of: currentFamily) ?? 0
        let trackWidth: CGFloat = 132
        let thumbWidth: CGFloat = 14
        let progress = families.count > 1 ? CGFloat(index) / CGFloat(families.count - 1) : 0
        return HStack(spacing: 10) {
            Capsule()
                .fill(Color.primary.opacity(0.12))
                .frame(width: trackWidth, height: 4)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: thumbWidth, height: 4)
                        .offset(x: (trackWidth - thumbWidth) * progress)
                }
            Text("\(index + 1)/\(families.count)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(height: 16)
        .animation(.snappy, value: familyID)
    }

    // MARK: Variant swatches — the family's designs as circular "tints"

    private var variantRow: some View {
        VStack(spacing: AppSpacing.md) {
            Text(current.name)
                .font(AppFont.subheadline)
                .foregroundStyle(.primary)
                .contentTransition(.opacity)
                .animation(.smooth(duration: 0.25), value: current.id)

            HStack(spacing: AppSpacing.lg) {
                ForEach(currentFamily.variants) { theme in
                    swatch(theme)
                }
            }
            .frame(height: 56)
        }
        .frame(maxWidth: .infinity)
    }

    private func swatch(_ theme: AppIconTheme) -> some View {
        let isSelected = theme.id == current.id
        let asset = previewsDarkFace ? (theme.darkPreview ?? theme.lightPreview) : theme.lightPreview
        return Button {
            HapticFeedback.selection()
            withAnimation(.snappy(duration: 0.25)) {
                variantByFamily[currentFamily.id] = theme.id
            }
        } label: {
            Image(asset)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
                .padding(3)
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(theme.name))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Face picker — Auto / Day / Night for paired themes
    //
    // Auto rides the merged day/night asset (switches with the system);
    // choosing a face installs exactly that half and keeps it pinned.

    private var facePicker: some View {
        HStack(spacing: AppSpacing.xs) {
            faceOption(nil,    label: ro ? "Automat" : "Auto",  icon: "circle.lefthalf.filled")
            faceOption(.light, label: ro ? "Zi" : "Day",        icon: "sun.max.fill")
            faceOption(.dark,  label: ro ? "Noapte" : "Night",  icon: "moon.fill")
        }
        .padding(AppSpacing.xs)
        .background(Color.subtleFill, in: Capsule())
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func faceOption(_ face: IconFace?, label: String, icon: String) -> some View {
        let isOn = pickedFace == face
        return Button {
            HapticFeedback.selection()
            withAnimation(.snappy(duration: 0.25)) { pickedFace = face }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(AppFont.caption)
                Text(label)
                    .font(AppFont.captionEmphasis)
            }
            .foregroundStyle(isOn ? Color.primary : Color.secondary)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, 7)
            .background {
                if isOn {
                    Capsule().fill(Color.accentColor.opacity(0.18))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Apply — "Active" when the shown icon is the installed one

    private var applyBar: some View {
        Button {
            guard iconManager.supportsAlternateIcons else { showError = true; return }
            HapticFeedback.success()
            iconManager.select(current, isDark: appliesDarkFace, pinFace: current.hasPair ? pickedFace : nil)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isApplied ? "checkmark" : "square.and.arrow.down")
                    .font(AppFont.headline)
                Text(isApplied ? (ro ? "Activă" : "Active")
                               : (ro ? "Setează iconița" : "Set Icon"))
                    .font(AppFont.headline)
            }
            .foregroundStyle(isApplied ? Color.secondary : Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .mediaGlass(in: Capsule(), interactive: !isApplied)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isApplied)
        .animation(.snappy, value: isApplied)
        .padding(.horizontal, AppSpacing.xl)
        .padding(.top, AppSpacing.md)
        .padding(.bottom, AppSpacing.lg)
    }
}

// MARK: - Rounded icon artwork

private struct IconArtwork: View {
    let name: String
    let size: CGFloat

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
            )
            // A soft, tight contact shadow — not a wide grey halo.
            .shadow(color: .black.opacity(0.16), radius: 7, y: 4)
    }
}
