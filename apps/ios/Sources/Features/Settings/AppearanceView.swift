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

    /// The living background's current selection, stated the way iOS
    /// Settings states a row's value ("Fundal   Automat ›").
    private var moodRowValue: String {
        AppMoodEngine.shared.isAuto
            ? String(localized: "mood_auto")
            : AppMoodEngine.shared.resolved.localizedTitle
    }

    /// The app's color scheme follows the background mood engine (Auto /
    /// Dimineața / Zi / Noaptea), so the old Dark/Light/System rows would
    /// be dead controls — the mood row is the single scheme control now.
    /// (`appSettings.theme` stays stored for profile compatibility.)
    private var themeSection: some View {
        SettingsGroup(title: "Theme") {
            NavSettingsRow(icon: "sun.horizon.fill", color: .brandGold,
                           label: "mood_settings_title",
                           value: moodRowValue) {
                BackgroundMoodView()
            }
            NavSettingsRow(icon: "textformat.size", color: .brandSkyBlue,
                           label: "textsize_title",
                           value: TextSizePreference.shared.rowValue) {
                TextSizeView()
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

                HStack(spacing: 10) {
                    ForEach(accentOptions, id: \.name) { opt in
                        Button {
                            withAnimation(.spring(response: 0.28)) {
                                appSettings.accentColor = opt.name
                                HapticFeedback.selection()
                            }
                            if let uid = auth.session?.user.id {
                                appSettings.syncToProfile(userId: uid)
                            }
                        } label: {
                            ZStack {
                                Circle().fill(opt.color).frame(width: 26, height: 26)
                                if appSettings.accentColor == opt.name {
                                    Circle().strokeBorder(.white, lineWidth: 2.5).frame(width: 26, height: 26)
                                    Circle().strokeBorder(opt.color, lineWidth: 1.5).frame(width: 32, height: 32)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    }

                    // Custom color picker — visible ColorPicker overlaid with rainbow visual
                    ZStack {
                        Circle()
                            .fill(AngularGradient(
                                gradient: Gradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red]),
                                center: .center
                            ))
                            .frame(width: 26, height: 26)
                        if appSettings.accentColor.hasPrefix("#") {
                            Circle().strokeBorder(.white, lineWidth: 2.5).frame(width: 26, height: 26)
                            Circle().strokeBorder(currentColor, lineWidth: 1.5).frame(width: 32, height: 32)
                        }
                        ColorPicker("", selection: customColorBinding, supportsOpacity: false)
                            .labelsHidden()
                            .opacity(0.015)
                            .scaleEffect(2.2)
                            .frame(width: 44, height: 44)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.base)
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
            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
            .padding(.leading, AppSpacing.xxs)
            .textCase(.uppercase)
    }
}


