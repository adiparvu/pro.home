import SwiftUI
import PhotosUI

// MARK: - Background (Settings → Aspect → Fundal) — the personalized backdrop
//
// The old "Fundaluri" page (weather-stage controls only) retired at the
// owner's request (2026-07-20): this page owns the WHOLE backdrop now.
// Three modes, one live preview, and the mode's own controls beneath:
//  · Cer viu — the F1–F4 weather stage, with its atmosphere pinning,
//    custom hours, particle effects and live-weather reaction;
//  · Gradient — a curated static gallery (zero GPU cost);
//  · Fotografia ta — the owner's photo, with a readability dim; text
//    colors follow the photo's measured luminance automatically.

struct BackgroundSettingsView: View {
    private var moodEngine: AppMoodEngine { .shared }
    private var style: BackgroundStyle { .shared }

    @State private var mode = BackgroundStyle.shared.mode
    @State private var gradientId = BackgroundStyle.shared.gradientId
    @State private var photoDim = BackgroundStyle.shared.photoDim
    @State private var pickerItem: PhotosPickerItem?

    @State private var preset: WeatherStagePreset? = WeatherStagePrefs.preset
    @State private var effectsOn = WeatherStagePrefs.effectsEnabled
    @State private var weatherReactive = AppMoodEngine.shared.weatherReactive
    @State private var customHours = AppMoodEngine.shared.hasCustomHours

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                previewCard

                SettingsGroup(title: "bg_mode_title") {
                    VStack(spacing: 0) {
                        modeRow(.liveSky, icon: "sun.haze.fill",
                                title: "bg_mode_live", caption: "bg_mode_live_caption")
                        rowDivider
                        modeRow(.gradient, icon: "rectangle.fill.badge.checkmark",
                                title: "bg_mode_gradient", caption: "bg_mode_gradient_caption")
                        rowDivider
                        modeRow(.photo, icon: "photo.fill",
                                title: "bg_mode_photo", caption: "bg_mode_photo_caption")
                    }
                }

                switch mode {
                case .liveSky:  liveSkySections
                case .gradient: gradientSection
                case .photo:    photoSection
                }

                Spacer(minLength: 100)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle(Text("bg_settings_title"))
        .navigationBarTitleDisplayMode(.large)
        .animation(AppMotion.state, value: mode)
        .animation(AppMotion.state, value: preset == nil)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                defer { pickerItem = nil }
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    style.setPhoto(image)
                    mode = .photo
                    HapticFeedback.success()
                }
            }
        }
    }

    // MARK: Live preview — the real chosen backdrop with a sample card

    private var previewCard: some View {
        ZStack {
            AppBackgroundView()
            GlassCard(padding: 16) {
                Text("mood_preview_card_title")
                    .font(AppFont.scaled(15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(AppSpacing.xl)
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    // MARK: Mode selection

    private func modeRow(_ target: AppBackgroundMode, icon: String,
                         title: LocalizedStringKey, caption: LocalizedStringKey) -> some View {
        let selected = mode == target
        return Button {
            guard mode != target else { return }
            mode = target
            HapticFeedback.impact(.light)
            // Photo mode without a photo yet: the section below opens with
            // its picker, but the REAL backdrop switches only once an
            // image lands (setPhoto) — never a black interim ground.
            if target == .photo && style.photo == nil { return }
            style.mode = target
        } label: {
            HStack(spacing: 12) {
                ColoredIconBadge(icon: icon,
                                 color: selected ? .accentColor : Color.primary.opacity(0.4))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppFont.scaled(15))
                        .foregroundStyle(.primary)
                    Text(caption)
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(AppFont.scaled(20))
                        .foregroundStyle(Color.accentColor)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Cer viu — the weather stage's own controls (unchanged engine)

    @ViewBuilder
    private var liveSkySections: some View {
        presetCarousel
        Text("ws_pin_caption")
            .font(AppFont.scaled(12))
            .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, AppSpacing.sm)

        if preset == nil {
            hoursSection
        }

        personalizeSection
    }

    private var presetCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.md) {
                ForEach(WeatherStagePreset.allCases) { pin in
                    presetTile(pin)
                }
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, 2)
        }
    }

    private func presetTile(_ pin: WeatherStagePreset) -> some View {
        let selected = preset == pin
        return Button {
            select(selected ? nil : pin)
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .fill(LinearGradient(colors: tileColors(pin),
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 88, height: 62)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: pin.symbol)
                            .font(AppFont.scaled(13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.35), radius: 2)
                            .padding(6)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : Color.hairline,
                                          lineWidth: selected ? 2 : 1)
                    )
                Text(pin.titleKey)
                    .font(AppFont.scaled(12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.accentColor
                                              : Color.primary.opacity(AppOpacity.secondaryText))
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Thumbnail ground: the CPU sky mirror at a canonical mid-day sun —
    /// the same authority the widgets render, so tiles never lie.
    private func tileColors(_ pin: WeatherStagePreset) -> [Color] {
        let params = pin.params(sunElevation: 0.7, sunAzimuth: 0.5,
                                moonPhase: 0.5, wind: 0.4)
        let c = params.snapshotColors
        return [Color(red: c.top.r, green: c.top.g, blue: c.top.b),
                Color(red: c.bottom.r, green: c.bottom.g, blue: c.bottom.b)]
    }

    private func select(_ pin: WeatherStagePreset?) {
        preset = pin
        WeatherStagePrefs.preset = pin
        HapticFeedback.impact(.light)
        WeatherStageEngine.shared.recompute(animated: true)
    }

    // MARK: Gradient gallery

    private var gradientSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.md) {
                ForEach(BackgroundGradientPreset.all) { g in
                    gradientTile(g)
                }
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, 2)
        }
    }

    private func gradientTile(_ g: BackgroundGradientPreset) -> some View {
        let selected = gradientId == g.id
        return Button {
            gradientId = g.id
            style.gradientId = g.id
            HapticFeedback.impact(.light)
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .fill(LinearGradient(colors: [g.top, g.bottom],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 88, height: 62)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : Color.hairline,
                                          lineWidth: selected ? 2 : 1)
                    )
                Text(LocalizedStringKey(g.titleKey))
                    .font(AppFont.scaled(12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.accentColor
                                              : Color.primary.opacity(AppOpacity.secondaryText))
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Fotografia ta

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SettingsGroup(title: "bg_mode_photo") {
                VStack(spacing: 0) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        HStack(spacing: 12) {
                            ColoredIconBadge(icon: "photo.badge.plus", color: .accentColor)
                            Text(style.photo == nil ? "bg_choose_photo" : "bg_change_photo")
                                .font(AppFont.scaled(15))
                                .foregroundStyle(.primary)
                            Spacer()
                            if let photo = style.photo {
                                Image(uiImage: photo)
                                    .resizable().scaledToFill()
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm,
                                                                style: .continuous))
                            }
                        }
                        .padding(.horizontal, AppSpacing.base)
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if style.photo != nil {
                        rowDivider
                        VStack(alignment: .leading, spacing: 6) {
                            Text("bg_dim_label")
                                .font(AppFont.scaled(15))
                                .foregroundStyle(.primary)
                            Slider(value: Binding(get: { photoDim },
                                                  set: { photoDim = $0
                                                         style.photoDim = $0 }),
                                   in: 0...0.5)
                                .tint(.accentColor)
                        }
                        .padding(.horizontal, AppSpacing.base)
                        .padding(.vertical, 13)

                        rowDivider
                        Button(role: .destructive) {
                            style.removePhoto()
                            mode = style.mode
                            HapticFeedback.impact(.medium)
                        } label: {
                            HStack(spacing: 12) {
                                ColoredIconBadge(icon: "trash.fill", color: .brandDanger)
                                Text("bg_remove_photo")
                                    .font(AppFont.scaled(15))
                                    .foregroundStyle(Color.brandDanger)
                                Spacer()
                            }
                            .padding(.horizontal, AppSpacing.base)
                            .padding(.vertical, 13)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text("bg_photo_caption")
                .font(AppFont.scaled(12))
                .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AppSpacing.sm)
        }
    }

    // MARK: Ore personalizate (Cer viu, Automat only)

    private var hoursSection: some View {
        SettingsGroup(title: "mood_hours_custom") {
            VStack(spacing: 0) {
                Toggle(isOn: customHoursBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("mood_hours_custom")
                            .font(AppFont.scaled(15))
                            .foregroundStyle(.primary)
                        Text("mood_hours_caption_sun")
                            .font(AppFont.scaled(12))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(.accentColor)
                .padding(.horizontal, AppSpacing.base)
                .padding(.vertical, 13)

                if customHours {
                    rowDivider
                    hourRow(label: "mood_hours_morning",
                            minutes: Binding(get: { moodEngine.morningStartMinutes },
                                             set: { moodEngine.morningStartMinutes = $0; stageChanged() }),
                            fallback: moodEngine.defaultEdges().morning)
                    rowDivider
                    hourRow(label: "mood_hours_night",
                            minutes: Binding(get: { moodEngine.nightStartMinutes },
                                             set: { moodEngine.nightStartMinutes = $0; stageChanged() }),
                            fallback: moodEngine.defaultEdges().night)
                }
            }
        }
    }

    private func hourRow(label: LocalizedStringKey,
                         minutes: Binding<Int?>, fallback: Double) -> some View {
        HStack {
            Text(label)
                .font(AppFont.scaled(15))
                .foregroundStyle(.primary)
            Spacer()
            DatePicker("", selection: timeBinding(minutes: minutes, fallback: fallback),
                       displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.sm)
    }

    /// Wall-clock minutes ↔ a same-day Date for the system time picker.
    private func timeBinding(minutes: Binding<Int?>, fallback: Double) -> Binding<Date> {
        Binding<Date>(
            get: {
                let total = minutes.wrappedValue ?? Int(fallback * 60)
                return Calendar.current.date(bySettingHour: min(total / 60, 23),
                                             minute: total % 60, second: 0,
                                             of: .now) ?? .now
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            })
    }

    private var customHoursBinding: Binding<Bool> {
        Binding(
            get: { customHours },
            set: { on in
                customHours = on
                if on {
                    // Seed from what Auto would do TODAY, so the pickers
                    // start honest instead of at an arbitrary hour.
                    let edges = moodEngine.defaultEdges()
                    moodEngine.morningStartMinutes = Int(edges.morning * 60)
                    moodEngine.nightStartMinutes = Int(edges.night * 60)
                } else {
                    moodEngine.morningStartMinutes = nil
                    moodEngine.nightStartMinutes = nil
                }
                stageChanged()
            })
    }

    // MARK: Personalizare — effects + live weather (Cer viu)

    private var personalizeSection: some View {
        SettingsGroup(title: "mood_personalize_title") {
            VStack(spacing: 0) {
                toggleRow(icon: "cloud.bolt.rain",
                          title: "mood_fx_toggle_title",
                          caption: "ws_fx_caption",
                          isOn: Binding(get: { effectsOn },
                                        set: { effectsOn = $0
                                               WeatherStagePrefs.effectsEnabled = $0
                                               stageChanged() }))
                rowDivider
                toggleRow(icon: "cloud.sun.rain",
                          title: "mood_weather_reactive",
                          caption: "mood_weather_caption",
                          isOn: Binding(get: { weatherReactive },
                                        set: { weatherReactive = $0
                                               moodEngine.weatherReactive = $0
                                               stageChanged() }))
            }
        }
    }

    private func toggleRow(icon: String, title: LocalizedStringKey,
                           caption: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 12) {
                ColoredIconBadge(icon: icon, color: isOn.wrappedValue ? .accentColor : Color.primary.opacity(0.4))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppFont.scaled(15))
                        .foregroundStyle(.primary)
                    Text(caption)
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(.accentColor)
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, 13)
    }

    private func stageChanged() {
        HapticFeedback.selection()
        WeatherStageEngine.shared.recompute(animated: true)
    }

    private var rowDivider: some View {
        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 54)
    }
}

// MARK: - The pins' UI vocabulary (names reuse the mood keys where they exist)

private extension WeatherStagePreset {
    var titleKey: LocalizedStringKey {
        switch self {
        case .morning:   "mood_morning"
        case .day:       "mood_day"
        case .sunset:    "mood_sunset"
        case .night:     "mood_night"
        case .cloudy:    "ws_preset_cloudy"
        case .fog:       "ws_preset_fog"
        case .rain:      "mood_rain"
        case .storm:     "ws_preset_storm"
        case .snow:      "ws_preset_snow"
        case .blizzard:  "ws_preset_blizzard"
        case .sandstorm: "ws_preset_sand"
        }
    }

    var symbol: String {
        switch self {
        case .morning:   "sunrise.fill"
        case .day:       "sun.max.fill"
        case .sunset:    "sunset.fill"
        case .night:     "moon.stars.fill"
        case .cloudy:    "cloud.fill"
        case .fog:       "cloud.fog.fill"
        case .rain:      "cloud.rain.fill"
        case .storm:     "cloud.bolt.rain.fill"
        case .snow:      "cloud.snow.fill"
        case .blizzard:  "wind.snow"
        case .sandstorm: "sun.dust.fill"
        }
    }
}
