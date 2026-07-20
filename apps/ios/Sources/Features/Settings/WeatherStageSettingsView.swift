import SwiftUI

// MARK: - Fundal (Settings → Aspect → Fundal) — the weather stage's controls
//
// The living background's command page, rebuilt for the F1–F4 weather
// engine (the old mood page retired 2026-07-19; the user decreed the
// backgrounds' return as real weather on 2026-07-20, and this page back
// with them). One authority per control, all persisted where they always
// were:
// - Atmosferă: Automat (real sun + real weather) or a PINNED atmosphere —
//   a time of day under a clear sky, or a weather state under the real
//   sun (WeatherStagePrefs.preset).
// - Ore personalizate: the mood engine's stored thresholds
//   (morningStart/nightStart) now feed the stage's sun window.
// - Efecte atmosferice: the particle layers (rain/snow streaks, bolts,
//   lens droplets, sand grain, fireflies) — the sky's body stays.
// - Reacționează la vreme: the mood engine's stored weatherReactive pref;
//   off = the sky follows time alone, honestly clear.

struct WeatherStageSettingsView: View {
    private var moodEngine: AppMoodEngine { .shared }

    @State private var preset: WeatherStagePreset? = WeatherStagePrefs.preset
    @State private var effectsOn = WeatherStagePrefs.effectsEnabled
    @State private var weatherReactive = AppMoodEngine.shared.weatherReactive
    @State private var customHours = AppMoodEngine.shared.hasCustomHours

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                previewCard

                SettingsGroup(title: "mood_choose_title") {
                    autoRow
                }
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

                Spacer(minLength: 100)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle(Text("mood_settings_title"))
        .navigationBarTitleDisplayMode(.large)
        .animation(AppMotion.state, value: preset == nil)
    }

    // MARK: Live preview — the real stage with a sample card on it

    private var previewCard: some View {
        ZStack {
            WeatherStageView()
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

    // MARK: Atmosferă — Automat row + pinned-atmosphere carousel

    private var autoRow: some View {
        Button {
            guard preset != nil else { return }
            select(nil)
        } label: {
            HStack(spacing: 12) {
                ColoredIconBadge(icon: "sparkles",
                                 color: preset == nil ? .accentColor : Color.primary.opacity(0.4))
                VStack(alignment: .leading, spacing: 2) {
                    Text("theme_auto")
                        .font(AppFont.scaled(15))
                        .foregroundStyle(.primary)
                    Text("ws_auto_caption")
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if preset == nil {
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
        .accessibilityAddTraits(preset == nil ? .isSelected : [])
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

    // MARK: Ore personalizate (Automat only)

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

    // MARK: Personalizare — effects + live weather

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
