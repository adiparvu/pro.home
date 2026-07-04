import SwiftUI

// MARK: - App Icon Picker (scenic carousel)
//
// One slide per theme: artwork, name, apply. No info paragraphs — the compact
// progress capsule replaces the old dot-per-theme pager, whose 36 dots forced
// the whole layout wider than the screen (the "button off-screen" bug).

struct AppIconPickerView: View {
    @Environment(IconManager.self) private var iconManager
    @Environment(\.colorScheme) private var colorScheme

    private let themes = AppIconCatalog.all
    @State private var index = 0
    @State private var showError = false

    private var ro: Bool { Locale.appIsRomanian }
    private var current: AppIconTheme { themes[min(index, themes.count - 1)] }

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: 0) {
                header
                carousel
                pager
                applyBar
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            index = themes.firstIndex(of: iconManager.selected) ?? 0
        }
        .alert(ro ? "Iconițele nu sunt disponibile" : "Icons not available",
               isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(ro ? "Dispozitivul nu permite schimbarea iconiței aplicației."
                    : "This device doesn't allow changing the app icon.")
        }
    }

    // MARK: Backdrop — the current icon, blurred into an ambient stage

    private var backdrop: some View {
        ZStack {
            appBackground
            Image(current.lightPreview)
                .resizable()
                .scaledToFill()
                .frame(width: 480, height: 480)
                .blur(radius: 90)
                .opacity(0.5)
                .offset(y: -110)
                .id(current.id)
                .transition(.opacity)
            Rectangle().fill(.ultraThinMaterial)
        }
        .ignoresSafeArea()
        .animation(.smooth(duration: 0.5), value: current.id)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 4) {
            Text(ro ? "Iconița aplicației" : "App Icon")
                .font(AppFont.title3)
                .foregroundStyle(.primary)
            Text(current.category.title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.md)
    }

    // MARK: Carousel — one slide per theme

    private var carousel: some View {
        TabView(selection: $index) {
            ForEach(themes.indices, id: \.self) { i in
                IconSlide(theme: themes[i], isCurrent: i == index)
                    .tag(i)
                    .padding(.horizontal, AppSpacing.xl)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.smooth, value: index)
    }

    // MARK: Pager — fixed-width progress capsule (never wider than the screen)

    private var pager: some View {
        let trackWidth: CGFloat = 132
        let thumbWidth: CGFloat = 14
        let progress = themes.count > 1 ? CGFloat(index) / CGFloat(themes.count - 1) : 0
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
            Text("\(index + 1)/\(themes.count)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(height: 16)
        .animation(.snappy, value: index)
        .padding(.vertical, AppSpacing.sm)
    }

    // MARK: Apply bar

    private var applyBar: some View {
        let isApplied = iconManager.selected.id == current.id
        return VStack(spacing: 10) {
            autoSwitchToggle
            Button {
                guard iconManager.supportsAlternateIcons else { showError = true; return }
                HapticFeedback.success()
                iconManager.select(current, isDark: colorScheme == .dark)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: isApplied ? "checkmark.circle.fill" : "square.and.arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                    Text(isApplied ? (ro ? "Aplicată" : "Applied")
                                   : (ro ? "Aplică iconița" : "Apply icon"))
                        .font(AppFont.subheadline)
                }
                // A compact centered pill, not a full-width bar.
                .padding(.horizontal, 26)
                .padding(.vertical, 12)
                .foregroundStyle(isApplied ? Color.primary : .white)
                .background(
                    isApplied ? AnyShapeStyle(.ultraThinMaterial)
                              : AnyShapeStyle(LinearGradient(colors: [Color.accentColor, Color.brandPurple],
                                                             startPoint: .leading, endPoint: .trailing)),
                    in: Capsule()
                )
                .shadow(color: isApplied ? .clear : Color.accentColor.opacity(0.3), radius: 12, y: 5)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .disabled(isApplied)
            .animation(.snappy, value: isApplied)
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.bottom, AppSpacing.lg)
    }

    private var autoSwitchToggle: some View {
        @Bindable var iconManager = iconManager
        return HStack(spacing: 10) {
            Image(systemName: "circle.lefthalf.filled")
                .foregroundStyle(Color.brandPurple)
            Text(ro ? "Schimbare automată zi/noapte" : "Auto day/night switch")
                .font(AppFont.footnoteEmphasis)
            Spacer()
            Toggle("", isOn: $iconManager.autoSwitch).labelsHidden().tint(Color.brandPurple)
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
    }
}

// MARK: - One slide

private struct IconSlide: View {
    let theme: AppIconTheme
    let isCurrent: Bool

    private var ro: Bool { Locale.appIsRomanian }

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer(minLength: 0)

            // Artwork — a paired theme shows its light + dark faces side by side
            // (no per-icon labels; the auto-switch toggle below explains it),
            // a single theme shows one large icon.
            HStack(spacing: 18) {
                IconArtwork(name: theme.lightPreview, size: theme.hasPair ? 122 : 176)
                if let dark = theme.darkPreview {
                    IconArtwork(name: dark, size: 122)
                }
            }
            .scaleEffect(isCurrent ? 1 : 0.9)
            .animation(.smooth, value: isCurrent)

            VStack(spacing: 6) {
                Text(theme.name)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                // Fills the space under the name and tells the user what the pair
                // means without cluttering the icons with badges.
                if theme.hasPair {
                    Label(ro ? "Se adaptează la tema telefonului" : "Adapts to your theme",
                          systemImage: "circle.lefthalf.filled")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text(theme.category.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
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
            // A soft, tight contact shadow — not a wide grey halo. The earlier
            // radius:18 spread bled a grey cloud well past the icon edges, which
            // read as an unwanted "background" around every preview.
            .shadow(color: .black.opacity(0.16), radius: 7, y: 4)
    }
}
