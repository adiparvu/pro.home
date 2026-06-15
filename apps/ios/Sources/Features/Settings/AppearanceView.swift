import SwiftUI

struct AppearanceView: View {
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var currencyService: CurrencyService
    @EnvironmentObject private var auth: AuthService

    private let accentOptions: [(name: String, color: Color, label: String)] = [
        ("blue",   .blue,                                              "Albastru"),
        ("purple", .purple,                                            "Violet"),
        ("green",  Color(red: 0.25, green: 0.82, blue: 0.45),         "Verde"),
        ("orange", .orange,                                            "Portocaliu"),
        ("pink",   .pink,                                              "Roz"),
        ("gold",   Color(red: 0.9,  green: 0.7,  blue: 0.15),         "Auriu"),
        ("red",    .red,                                               "Red"),
        ("teal",   .teal,                                              "Turcoaz"),
    ]

    private var currentLabel: String {
        if appSettings.accentColor.hasPrefix("#") { return "Personalizat" }
        return accentOptions.first(where: { $0.name == appSettings.accentColor })?.label ?? "Albastru"
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
                PageHeader(title: "Aspect")
                themeSection
                accentSection
                hapticSection
                currencySection
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await currencyService.refresh() }
    }

    // MARK: - Theme

    private var themeSection: some View {
        SettingsGroup(title: "Theme") {
            ForEach(AppSettings.themes, id: \.code) { theme in
                ThemeOptionRow(
                    icon: theme.icon,
                    title: theme.label,
                    isSelected: appSettings.theme == theme.code,
                    accentColor: currentColor
                ) {
                    withAnimation(.spring(response: 0.3)) { appSettings.theme = theme.code }
                    HapticFeedback.selection()
                    if let uid = auth.session?.user.id { appSettings.syncToProfile(userId: uid) }
                }
            }
        }
    }

    // MARK: - Currency

    private var currencySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Currency")

            VStack(spacing: 0) {
                ForEach(CurrencyService.supported, id: \.code) { cur in
                    let isSelected = appSettings.preferredCurrency == cur.code
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            appSettings.preferredCurrency = cur.code
                        }
                        if let uid = auth.session?.user.id {
                            appSettings.syncToProfile(userId: uid)
                        }
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSelected ? Color.primary.opacity(0.18) : Color.primary.opacity(0.07))
                                    .frame(width: 40, height: 40)
                                Text(cur.symbol)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.5))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(cur.code) — \(cur.name)")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.primary)
                                if isSelected {
                                    Text(currencyService.rateDisplay(for: cur.code))
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.primary.opacity(0.4))
                                        .transition(.opacity)
                                }
                            }

                            Spacer()

                            if currencyService.isLoading && isSelected {
                                ProgressView().scaleEffect(0.7).tint(Color.primary.opacity(0.5))
                            } else if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.tint)
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                Circle()
                                    .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1.5)
                                    .frame(width: 20, height: 20)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)

                    if cur.code != CurrencyService.supported.last?.code {
                        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 68)
                    }
                }
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))

            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10))
                Text("BNR rates · Updated \(currencyService.lastUpdatedDisplay)")
                    .font(.system(size: 11))
            }
            .foregroundStyle(Color.primary.opacity(0.3))
            .padding(.leading, 4)

            Button {
                Task { await forceFetch() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                    Text("Refresh rates now")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.tint)
                .padding(.leading, 4)
            }
            .buttonStyle(.plain)
            .disabled(currencyService.isLoading)
        }
    }

    private func forceFetch() async {
        UserDefaults.standard.removeObject(forKey: "prvio.bnr.ratesDate")
        await currencyService.refresh()
    }

    // MARK: - Accent Color

    private var accentSection: some View {
        SettingsGroup(title: "Visual Theme") {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "paintpalette.fill", color: appSettings.accentEnabled ? currentColor : Color.primary.opacity(0.4))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Culoare de accent")
                            .font(.system(size: 15)).foregroundStyle(.primary)
                        Text(appSettings.accentEnabled ? currentLabel : "Dezactivat")
                            .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.4))
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { appSettings.accentEnabled },
                        set: { newVal in
                            appSettings.objectWillChange.send()
                            appSettings.accentEnabled = newVal
                            HapticFeedback.selection()
                            if let uid = auth.session?.user.id { appSettings.syncToProfile(userId: uid) }
                        }
                    ))
                    .labelsHidden().tint(accentPreviewColor)
                }
                .padding(.horizontal, 14).padding(.vertical, 13)

                if appSettings.accentEnabled {
                    Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.4).padding(.leading, 52)

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

                    // Custom color picker (rainbow circle) — the ColorPicker sits
                    // underneath with an enlarged hit area; the rainbow + rings are
                    // visual-only so a tap anywhere on the swatch opens the picker.
                    ZStack {
                        ColorPicker("", selection: customColorBinding, supportsOpacity: false)
                            .labelsHidden()
                            .scaleEffect(1.9)
                            .opacity(0.02)
                            .frame(width: 40, height: 40)

                        Circle()
                            .fill(AngularGradient(
                                gradient: Gradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink, .red]),
                                center: .center
                            ))
                            .frame(width: 26, height: 26)
                            .allowsHitTesting(false)
                        if appSettings.accentColor.hasPrefix("#") {
                            Circle().strokeBorder(.white, lineWidth: 2.5).frame(width: 26, height: 26).allowsHitTesting(false)
                            Circle().strokeBorder(currentColor, lineWidth: 1.5).frame(width: 32, height: 32).allowsHitTesting(false)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 14).padding(.vertical, 14)
                }
            }
        }
    }

    // MARK: - Haptic

    private var hapticSection: some View {
        SettingsGroup(title: "General") {
            HStack(spacing: 12) {
                ColoredIconBadge(icon: "iphone.radiowaves.left.and.right", color: .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Haptic feedback")
                        .font(.system(size: 15)).foregroundStyle(.primary)
                    Text("Vibrations on app interactions")
                        .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.4))
                }
                Spacer()
                Toggle("", isOn: $appSettings.hapticEnabled)
                    .labelsHidden().tint(currentColor)
                    .onChange(of: appSettings.hapticEnabled) { _, on in
                        if on { HapticFeedback.impact(.medium) }
                    }
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(0.35))
            .padding(.leading, 4)
    }
}

// MARK: - Theme Row

private struct ThemeOptionRow: View {
    let icon: String
    let title: String
    let isSelected: Bool
    var accentColor: Color = .blue
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ColoredIconBadge(icon: icon, color: isSelected ? accentColor : Color.primary.opacity(0.4), size: 36)
                Text(title)
                    .font(.system(size: 15)).foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20)).foregroundStyle(accentColor)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }
}

