import SwiftUI

// MARK: - App Icon Picker (scenic carousel)
//
// A full-bleed, slide-per-icon gallery: each theme gets its own stage with a
// blurred backdrop drawn from its own artwork, a live light/dark preview, and a
// short story. Applying an icon is one tap with haptic confirmation.

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
                .frame(width: 520, height: 520)
                .blur(radius: 90)
                .opacity(0.55)
                .offset(y: -120)
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

    // MARK: Pager dots

    private var pager: some View {
        HStack(spacing: 6) {
            ForEach(themes.indices, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Color.accentColor : Color.primary.opacity(0.18))
                    .frame(width: i == index ? 18 : 6, height: 6)
            }
        }
        .animation(.snappy, value: index)
        .padding(.vertical, AppSpacing.sm)
        // Keep the row compact even with many themes.
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .opacity(themes.count <= 40 ? 1 : 0.9)
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
                HStack(spacing: 8) {
                    Image(systemName: isApplied ? "checkmark.circle.fill" : "square.and.arrow.down.on.square")
                    Text(isApplied ? (ro ? "Aplicată" : "Applied")
                                   : (ro ? "Aplică această iconiță" : "Apply this icon"))
                        .font(AppFont.subheadline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .foregroundStyle(isApplied ? Color.primary : .white)
                .background(
                    isApplied ? AnyShapeStyle(.ultraThinMaterial)
                              : AnyShapeStyle(LinearGradient(colors: [Color.accentColor, Color.brandPurple],
                                                             startPoint: .leading, endPoint: .trailing)),
                    in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                )
            }
            .buttonStyle(.plain)
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
            VStack(alignment: .leading, spacing: 1) {
                Text(ro ? "Schimbare automată zi/noapte" : "Auto day/night switch")
                    .font(AppFont.footnoteEmphasis)
                Text(ro ? "Perechile light/dark urmează sistemul"
                        : "Light/dark pairs follow the system")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
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
    @Environment(\.colorScheme) private var colorScheme

    private var ro: Bool { Locale.appIsRomanian }

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer(minLength: 0)

            // Artwork — pair shows light + dark, single shows one.
            HStack(spacing: 18) {
                IconArtwork(name: theme.lightPreview, size: theme.hasPair ? 116 : 168)
                    .overlay(alignment: .bottom) { if theme.hasPair { modeTag("sun.max.fill", ro ? "Zi" : "Day") } }
                if let dark = theme.darkPreview {
                    IconArtwork(name: dark, size: 116)
                        .overlay(alignment: .bottom) { modeTag("moon.stars.fill", ro ? "Noapte" : "Night") }
                }
            }
            .scaleEffect(isCurrent ? 1 : 0.9)
            .animation(.smooth, value: isCurrent)

            VStack(spacing: 8) {
                Text(theme.name)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                if theme.hasPair {
                    Label(ro ? "Se schimbă automat cu tema sistemului"
                             : "Switches automatically with the system",
                          systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                } else if theme.isDefault {
                    Label(ro ? "Iconița implicită" : "Default icon", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                }

                Text(theme.story)
                    .font(AppFont.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, AppSpacing.sm)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private func modeTag(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 8))
            Text(text).font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(.black.opacity(0.35), in: Capsule())
        .offset(y: 10)
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
            .shadow(color: .black.opacity(0.3), radius: 18, y: 10)
    }
}
