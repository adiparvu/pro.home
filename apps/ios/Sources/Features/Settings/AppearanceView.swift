import SwiftUI

struct AppearanceView: View {
    @Environment(AppSettings.self) private var appSettings
    @Environment(CurrencyService.self) private var currencyService
    @Environment(AuthService.self) private var auth

    private let accentOptions: [(name: String, color: Color, labelKey: LocalizedStringKey)] = [
        ("blue",   .blue,                                              "Blue"),
        ("purple", .purple,                                            "Purple"),
        ("green",  Color(red: 0.25, green: 0.82, blue: 0.45),         "Green"),
        ("orange", .orange,                                            "Orange"),
        ("pink",   .pink,                                              "Pink"),
        ("gold",   Color(red: 0.9,  green: 0.7,  blue: 0.15),         "Gold"),
        ("red",    .red,                                               "Red"),
        ("teal",   .teal,                                              "Teal"),
    ]

    private var currentAccentLabel: LocalizedStringKey {
        if appSettings.accentColor == "auto" { return "mood_accent_auto" }
        if appSettings.accentColor.hasPrefix("#") { return "Custom" }
        return accentOptions.first(where: { $0.name == appSettings.accentColor })?.labelKey ?? "Blue"
    }

    private var accentSubtitle: LocalizedStringKey {
        appSettings.accentEnabled ? currentAccentLabel : "Disabled"
    }
    // Resolved accent color — respects the enabled/disabled toggle.
    // Use accentPreviewColor where you always want the raw selected color
    // (e.g., the color-picker dots and the toggle's own tint).
    private var currentColor: Color {
        appSettings.accentEnabled ? avatarRingColor(for: appSettings.accentColor) : .blue
    }
    private var accentPreviewColor: Color {
        avatarRingColor(for: appSettings.accentColor)
    }
    private var customColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: appSettings.accentColor) ?? .blue },
            set: { newColor in
                appSettings.accentColor = newColor.hexString()
                HapticFeedback.selection()
                if let uid = auth.session?.user.id { appSettings.syncToProfile(userId: uid) }
            }
        )
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                themeSection
                accentSection
                hapticSection
                currencySection
                Spacer(minLength: 100)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.large)
        .task { await currencyService.refresh() }
    }

    // MARK: - Theme

    /// The Temă page RETIRED (audit 2026-07-21): the chosen backdrop now
    /// dictates the app's color scheme (a dark gradient/photo renders the
    /// app dark, like an iOS wallpaper), so a separate Light/Dark control
    /// would be a dead switch. Fundal is the single appearance authority.
    private var themeSection: some View {
        SettingsGroup(title: "Theme") {
            // The personalized backdrop page (user-decreed 2026-07-20/21):
            // curated gradients or the owner's own photo; its luminance
            // drives the whole app's scheme and the widget/watch ground.
            NavSettingsRow(icon: "photo.on.rectangle.angled", color: .brandPrimaryBlue,
                           label: "bg_settings_title") {
                BackgroundSettingsView()
            }
            NavSettingsRow(icon: "textformat.size", color: .brandSkyBlue,
                           label: "textsize_title",
                           value: TextSizePreference.shared.rowValue) {
                TextSizeView()
            }
            // The app-icon gallery lives here in Aspect (Appearance), beside the
            // mood and text-size controls — it is a look-and-feel choice.
            NavSettingsRow(icon: "app.fill", color: .brandPurple,
                           label: "App Icon") {
                AppIconPickerView()
            }
        }
    }

    // MARK: - Currency

    // Currency earned its own page (it's a financial preference, not a
    // visual one) — Appearance keeps a single value-stating row into it.
    private var currencySection: some View {
        SettingsGroup(title: "Currency") {
            NavSettingsRow(icon: "coloncurrencysign.circle.fill", color: Color.brandSuccess,
                           label: "currency_row_label",
                           value: appSettings.preferredCurrency) {
                CurrencyView()
            }
        }
    }

    // MARK: - Accent Color

    private var accentSection: some View {
        SettingsGroup(title: "Visual Theme") {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "paintpalette.fill", color: appSettings.accentEnabled ? currentColor : Color.primary.opacity(0.4))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accent Color")
                            .font(AppFont.scaled(15)).foregroundStyle(.primary)
                        Text(accentSubtitle)
                            .font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(0.4))
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { appSettings.accentEnabled },
                        set: { newVal in
                            appSettings.accentEnabled = newVal
                            HapticFeedback.selection()
                            if let uid = auth.session?.user.id { appSettings.syncToProfile(userId: uid) }
                        }
                    ))
                    .labelsHidden().tint(accentPreviewColor)
                }
                .padding(.horizontal, AppSpacing.base).padding(.vertical, 13)

                if appSettings.accentEnabled {
                    Rectangle().fill(Color.primary.opacity(AppOpacity.hairline)).frame(height: 0.4).padding(.leading, 52)

                // "Automat" first: the accent follows the living background's
                // mood (morning gold / day sky / night ember). The swatch
                // previews the CURRENT mood's accent, honestly.
                autoAccentRow

                Rectangle().fill(Color.primary.opacity(AppOpacity.hairline)).frame(height: 0.4).padding(.leading, 52)

                // Named palette as a spacious 4-column grid of large swatches
                // — the same visual language as the profile's avatar-ring
                // picker (IMG_8820), replacing the old cramped single row.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4),
                          spacing: AppSpacing.lg) {
                    ForEach(accentOptions, id: \.name) { opt in
                        accentSwatch(name: opt.name, color: opt.color, label: opt.labelKey)
                    }
                }
                .padding(.horizontal, AppSpacing.base)
                .padding(.top, AppSpacing.base)
                .padding(.bottom, AppSpacing.md)

                Rectangle().fill(Color.primary.opacity(AppOpacity.hairline)).frame(height: 0.4).padding(.leading, 52)

                // Custom color — a settings row with the system ColorPicker
                // trailing (its own swatch shows the rainbow / chosen hue),
                // mirroring the profile's "Custom color" card.
                HStack(spacing: AppSpacing.sm) {
                    Text("Custom color")
                        .font(AppFont.scaled(15)).foregroundStyle(.primary)
                    if appSettings.accentColor.hasPrefix("#") {
                        Image(systemName: "checkmark.circle.fill")
                            .font(AppFont.footnote)
                            .foregroundStyle(currentColor)
                    }
                    Spacer()
                    ColorPicker("", selection: customColorBinding, supportsOpacity: false)
                        .labelsHidden()
                        .accessibilityLabel(Text("Custom color"))
                }
                .padding(.horizontal, AppSpacing.base).padding(.vertical, 13)
                }
            }
        }
    }

    /// "Automat" stores the `"auto"` sentinel; the root `.tint` and
    /// `avatarRingColor(for:)` resolve it to the resolved mood's palette
    /// accent (morning gold, day sky, night ember). The swatch previews the
    /// CURRENT mood's accent — exactly what the app is tinted with now.
    private var autoAccentRow: some View {
        let isSelected = appSettings.accentColor == "auto"
        let moodAccent = AppMoodEngine.shared.resolved.palette.accent
        return Button {
            withAnimation(.spring(response: 0.28)) {
                appSettings.accentColor = "auto"
                HapticFeedback.selection()
            }
            if let uid = auth.session?.user.id { appSettings.syncToProfile(userId: uid) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(moodAccent).frame(width: 26, height: 26)
                    Image(systemName: "sparkles")
                        .font(AppFont.scaled(11, weight: .semibold))
                        .foregroundStyle(.white)
                    if isSelected {
                        Circle().strokeBorder(.white, lineWidth: 2.5).frame(width: 26, height: 26)
                        Circle().strokeBorder(moodAccent, lineWidth: 1.5).frame(width: 32, height: 32)
                    }
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("mood_accent_auto")
                        .font(AppFont.scaled(15)).foregroundStyle(.primary)
                    Text("mood_accent_auto_caption")
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(AppFont.scaled(20))
                        .foregroundStyle(moodAccent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// One large palette swatch — the exact look of the profile's avatar-ring
    /// picker (40pt fill, white checkmark, a concentric ring when chosen).
    private func accentSwatch(name: String, color: Color, label: LocalizedStringKey) -> some View {
        let selected = appSettings.accentColor == name
        return Button {
            withAnimation(.snappy(duration: 0.25)) {
                appSettings.accentColor = name
                HapticFeedback.selection()
            }
            if let uid = auth.session?.user.id { appSettings.syncToProfile(userId: uid) }
        } label: {
            ZStack {
                Circle().fill(color).frame(width: 40, height: 40)
                if selected {
                    Image(systemName: "checkmark")
                        .font(AppFont.captionStrong)
                        .foregroundStyle(.white)
                }
            }
            .overlay {
                if selected {
                    Circle().strokeBorder(color, lineWidth: 1.5).frame(width: 48, height: 48)
                }
            }
            .frame(width: 48, height: 48)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Haptic

    private var hapticSection: some View {
        @Bindable var appSettings = appSettings
        return SettingsGroup(title: "General") {
            HStack(spacing: 12) {
                ColoredIconBadge(icon: "iphone.radiowaves.left.and.right", color: .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Haptic feedback")
                        .font(AppFont.scaled(15)).foregroundStyle(.primary)
                    Text("Vibrations on app interactions")
                        .font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(0.4))
                }
                Spacer()
                Toggle("", isOn: $appSettings.hapticEnabled)
                    .labelsHidden().tint(currentColor)
                    .onChange(of: appSettings.hapticEnabled) { _, on in
                        if on { HapticFeedback.impact(.medium) }
                    }
            }
            .padding(.horizontal, AppSpacing.base).padding(.vertical, 13)
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(AppFont.label)
            .foregroundStyle(Color.backdropSecondaryText)
            .padding(.leading, AppSpacing.xxs)
    }
}


