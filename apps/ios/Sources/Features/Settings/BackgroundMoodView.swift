import SwiftUI

// MARK: - Background mood (Settings → Aspect → Fundal)
//
// The dedicated page for the living background: a hero preview that renders
// the ACTUAL backdrop of the selected mood with a real glass card on top
// (what you see is literally what every screen gets), an Atmosferă group
// (Auto + optional custom hours), an airy horizontal carousel — the Auto
// card first (a live preview of what Auto composes right now, captioned
// with WHY), then the seven atmospheres (~3.5 visible, swipe for the
// rest, view-aligned snapping) — and a Personalizare group (atmospheric
// effects, mood-following app icon, weather-reactive backdrop). Selection
// persists through `AppMoodEngine.override`.
//
// The hero preview is the one fixed preview allowed to run the LIVE
// atmospheric effects scene (it is a single instance and the page is where
// the user auditions moods); the carousel thumbnails only ever get the
// static pre-baked hint that `AppBackdrop` bakes into fixed previews.
//
// Honesty:
// - The Auto explanation only claims sunrise/sunset when the engine
//   actually has coordinates, and says "your hours" when custom thresholds
//   are set. It mentions the weather / season / celebration layers only
//   while each is actually available or active — never as a promise.
// - The Auto card's caption states the single winning reason behind what
//   Auto shows ("Automat · apus", "Automat · zi de sărbătoare"), straight
//   from the engine's own composition.
// - Custom-hour pickers exist only while Auto is active — a pinned mood
//   ignores them, so they are never shown as dead controls.
// - The icon toggle disables itself (with the reason) when the selected
//   icon has no installable day/night pair; the weather toggle disables
//   itself when no fresh weather data exists — and since the toggle drives
//   real behavior, opening this page is also the on-demand weather moment:
//   with property coordinates and a stale/absent cache one fetch attempt
//   runs (progress on the row meanwhile). When it fails, the caption quotes
//   the RECORDED error (PropertyWeather.lastRefreshError) instead of
//   implying the fetch merely hasn't happened, hints at WeatherKit
//   activation for auth-shaped failures, and offers a retry.

struct BackgroundMoodView: View {
    @Environment(IconManager.self) private var iconManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// True while the page's own weather fetch attempt is in flight.
    @State private var isRefreshingWeather = false

    private var engine: AppMoodEngine { .shared }

    /// Sane picker windows (minutes since midnight): morning onset
    /// 04:00–11:45, night onset 15:00–23:45. They keep the two thresholds
    /// from ever crossing, so "night wins" stays a theoretical fallback.
    private static let morningRange = 4 * 60...(11 * 60 + 45)
    private static let nightRange = 15 * 60...(23 * 60 + 45)

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: AppSpacing.xxl) {
                heroPreview
                selectorSection
                personalizeSection
                Spacer(minLength: 100)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle(Text("mood_settings_title"))
        .navigationBarTitleDisplayMode(.large)
        .task { await refreshWeatherIfStale() }
    }

    // MARK: On-demand weather refresh (page open + the row's retry)

    /// One honest fetch attempt when the property has coordinates and the
    /// cache is stale or absent (no-op otherwise — the 1h write TTL makes
    /// repeat visits free). Success enables the toggle and recomposes Auto
    /// immediately (the engine observes `.propertyWeatherCacheDidUpdate`);
    /// failure records the error the caption quotes.
    private func refreshWeatherIfStale() async {
        guard let lat = engine.latitude, let lon = engine.longitude,
              !PropertyWeather.hasFreshCache, !isRefreshingWeather else { return }
        isRefreshingWeather = true
        await PropertyWeather.refreshRecordingErrors(latitude: lat, longitude: lon)
        isRefreshingWeather = false
    }

    // MARK: Hero — the real backdrop, the real glass

    /// Live preview of the selected mood (Auto shows whatever it resolves to
    /// right now). The card inside is the app's actual `GlassCard`, and the
    /// preview adopts the mood's own color scheme, so glass, text, and
    /// ground are exactly what the rest of the app will render.
    private var heroPreview: some View {
        let mood = engine.resolved
        return ZStack {
            AppBackdrop(fixed: mood)
            // The one live effects instance a fixed preview may run: what
            // you audition here is exactly what the real backdrop does
            // (and it obeys the same energy policy — toggle off, Reduce
            // Motion, or Low Power Mode leave the hero static too).
            AppBackdropEffectsLayer(mood: mood)
            GlassCard(padding: AppSpacing.lg, cornerRadius: AppRadius.xl) {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("mood_preview_card_title")
                        .font(AppFont.headline)
                        .foregroundStyle(.primary)
                    Text("mood_preview_card_body")
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(AppSpacing.xxl)
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xxl, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
        )
        // The app's scheme follows the mood; the preview must too, or the
        // glass would lie about its contrast.
        .environment(\.colorScheme, mood.palette.colorScheme)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(mood.titleKey))
    }

    // MARK: Selector — Auto (+ custom hours) + the atmosphere carousel

    private var selectorSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SettingsGroup(title: "mood_choose_title") {
                autoRow
                // Custom hours refine Auto only; a pinned mood ignores them,
                // so the rows exist only while Auto is active.
                if engine.isAuto {
                    rowDivider
                    customHoursToggleRow
                    if engine.hasCustomHours {
                        rowDivider
                        hourRow(title: "mood_hours_morning",
                                minutes: morningMinutesBinding,
                                range: Self.morningRange)
                        rowDivider
                        hourRow(title: "mood_hours_night",
                                minutes: nightMinutesBinding,
                                range: Self.nightRange)
                    }
                }
            }
            moodCarousel
        }
    }

    /// The atmosphere carousel: Auto first (live composition + reason),
    /// then all seven moods. ~3.5 cards visible (each spans 2/7 of the
    /// width), view-aligned snapping, bleeding to the screen edge so the
    /// swipe feels airy while the cards still align with the page margin.
    /// No programmatic scrolling — nothing moves that the user didn't move
    /// (which is also the whole Reduce Motion story for this row).
    private var moodCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: AppSpacing.md) {
                AutoMoodCard(preview: engine.autoResolved,
                             reason: engine.autoReason,
                             isSelected: engine.isAuto) {
                    select(nil)
                }
                .carouselCardWidth()
                ForEach(AppMood.allCases) { mood in
                    MoodPreviewCard(mood: mood,
                                    isSelected: engine.override == mood) {
                        select(mood)
                    }
                    .carouselCardWidth()
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        // Bleed past the page's horizontal padding, then restore it as
        // content margins so the first card rests on the page grid.
        .padding(.horizontal, -AppSpacing.xl)
        .contentMargins(.horizontal, AppSpacing.xl, for: .scrollContent)
    }

    /// Honest Auto caption, composed of only what is true right now: the
    /// base clause (custom hours / sun / clock — exactly as before), plus
    /// one clause per composition layer that is actually available or
    /// active — weather (toggle on AND fresh data), season (only during the
    /// winter months), celebration (only on an actual event day).
    private var autoCaption: String {
        var parts: [String] = []
        if engine.hasCustomHours {
            parts.append(String(localized: "mood_auto_explain_custom"))
        } else if engine.latitude != nil {
            parts.append(String(localized: "mood_auto_explain_sun"))
        } else {
            parts.append(String(localized: "mood_auto_explain_clock"))
        }
        if engine.weatherReactive, AppWeatherTone.hasFreshSummary {
            parts.append(String(localized: "mood_auto_explain_weather_layer"))
        }
        if AppMood.isWinterSeason() {
            parts.append(String(localized: "mood_auto_explain_winter_layer"))
        }
        if engine.eventToday != nil {
            parts.append(String(localized: "mood_auto_explain_event_layer"))
        }
        return parts.joined(separator: " ")
    }

    private var autoRow: some View {
        Button {
            select(nil)
        } label: {
            HStack(spacing: 12) {
                ColoredIconBadge(icon: "sparkles",
                                 color: engine.isAuto ? .accentColor : Color.primary.opacity(0.4))
                VStack(alignment: .leading, spacing: 2) {
                    Text("mood_auto")
                        .font(AppFont.scaled(15))
                        .foregroundStyle(.primary)
                    Text(autoCaption)
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                if engine.isAuto {
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
        .accessibilityAddTraits(engine.isAuto ? [.isButton, .isSelected] : .isButton)
    }

    private func select(_ mood: AppMood?) {
        guard engine.override != mood else { return }
        HapticFeedback.selection()
        // The backdrop crossfades itself (.smooth 1.2 / instant under Reduce
        // Motion); this spring only carries the checkmarks and rings — and
        // it too stands still when motion is reduced.
        withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
            engine.override = mood
        }
    }

    // MARK: Custom hours (refine Auto; hidden while a mood is pinned)

    private var customHoursToggleRow: some View {
        MoodToggleRow(icon: "clock",
                      title: "mood_hours_custom",
                      caption: engine.latitude != nil ? Text("mood_hours_caption_sun")
                                                      : Text("mood_hours_caption_clock"),
                      isOn: Binding(
                          get: { engine.hasCustomHours },
                          set: { on in
                              HapticFeedback.selection()
                              withAnimation(.spring(response: 0.3)) {
                                  if on {
                                      // Seed from what Auto would do TODAY, so
                                      // the pickers open on the honest values.
                                      let edges = engine.defaultEdges()
                                      engine.morningStartMinutes =
                                          Self.minutes(fromHours: edges.morning, in: Self.morningRange)
                                      engine.nightStartMinutes =
                                          Self.minutes(fromHours: edges.night, in: Self.nightRange)
                                  } else {
                                      // The labeled reset: back to sunrise/sunset
                                      // (or the standard clock windows).
                                      engine.morningStartMinutes = nil
                                      engine.nightStartMinutes = nil
                                  }
                              }
                          }))
    }

    private var morningMinutesBinding: Binding<Int> {
        Binding(get: { engine.morningStartMinutes ?? Self.morningRange.lowerBound },
                set: { engine.morningStartMinutes = $0 })
    }

    private var nightMinutesBinding: Binding<Int> {
        Binding(get: { engine.nightStartMinutes ?? Self.nightRange.lowerBound },
                set: { engine.nightStartMinutes = $0 })
    }

    private func hourRow(title: LocalizedStringKey,
                         minutes: Binding<Int>,
                         range: ClosedRange<Int>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(AppFont.scaled(15))
                .foregroundStyle(.primary)
            Spacer()
            DatePicker(selection: Binding(
                           get: { Self.date(fromMinutes: minutes.wrappedValue) },
                           set: { minutes.wrappedValue = Self.clamp(Self.minutes(from: $0), to: range) }
                       ),
                       in: Self.date(fromMinutes: range.lowerBound)...Self.date(fromMinutes: range.upperBound),
                       displayedComponents: .hourAndMinute) {
                Text(title)
            }
            .labelsHidden()
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.sm)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(AppOpacity.hairline))
            .frame(height: 0.4)
            .padding(.leading, 52)
    }

    // MARK: Personalizare — icon + weather

    private var personalizeSection: some View {
        let canFollow = iconManager.canFollowMood
        let hasWeather = AppWeatherTone.hasFreshSummary
        return SettingsGroup(title: "mood_personalize_title") {
            // Atmospheric effects (rain / snow / event shimmer on the live
            // backdrop). Always operable — the caption is the honest
            // contract: the effects still stand down by themselves in Low
            // Power Mode and under Reduce Motion, whatever this says.
            MoodToggleRow(icon: "cloud.bolt.rain",
                          title: "mood_fx_toggle_title",
                          caption: Text("mood_fx_toggle_caption"),
                          isOn: Binding(
                              get: { AtmosphericEffectsPolicy.shared.userEnabled },
                              set: { on in
                                  HapticFeedback.selection()
                                  AtmosphericEffectsPolicy.shared.userEnabled = on
                              }))
            rowDivider
            MoodToggleRow(icon: "app.badge",
                          title: "mood_icon_follow",
                          caption: Text(iconCaptionKey),
                          isOn: Binding(
                              // Show the EFFECTIVE state: with the alert-free
                              // switch gone the feature is off no matter what
                              // the stored preference says — a disabled row
                              // that still reads "on" would be a lie.
                              get: { iconManager.followsMood && canFollow },
                              set: { on in
                                  HapticFeedback.selection()
                                  iconManager.setFollowsMood(on)
                              }))
                .disabled(!canFollow)
                .opacity(canFollow ? 1 : 0.5)
            rowDivider
            // The weather row manages its own dimming (`dimsAsDisabled`)
            // instead of a row-level `.disabled`, so the retry button under
            // the caption stays tappable when the toggle cannot be.
            MoodToggleRow(icon: "cloud.sun",
                          title: "mood_weather_reactive",
                          caption: weatherCaption,
                          isOn: Binding(
                              get: { engine.weatherReactive },
                              set: { on in
                                  HapticFeedback.selection()
                                  engine.weatherReactive = on
                              }),
                          isBusy: isRefreshingWeather,
                          dimsAsDisabled: !hasWeather,
                          retry: canRetryWeather
                              ? { Task { await refreshWeatherIfStale() } }
                              : nil)
        }
    }

    /// The weather row's honest caption, in priority order: what is being
    /// done right now (fetching) → what works (fresh data) → what failed
    /// (the recorded error, verbatim; auth-shaped failures hint that the
    /// WeatherKit service needs activation) → what never ran (no data yet).
    private var weatherCaption: Text {
        if isRefreshingWeather { return Text("mood_weather_refreshing") }
        if AppWeatherTone.hasFreshSummary { return Text("mood_weather_caption") }
        if let failure = PropertyWeather.lastRefreshError {
            if failure.looksLikeAuthFailure { return Text("mood_weather_error_auth") }
            return Text(verbatim: String(
                format: String(localized: "mood_weather_error_message"),
                failure.message))
        }
        return Text("mood_weather_nodata")
    }

    /// Retry only when it could help: a recorded failure, coordinates to
    /// retry with, no fresh data, and no attempt already in flight.
    private var canRetryWeather: Bool {
        !isRefreshingWeather
            && !AppWeatherTone.hasFreshSummary
            && PropertyWeather.lastRefreshError != nil
            && engine.latitude != nil && engine.longitude != nil
    }

    /// Why the icon can(not) follow the mood, stated plainly: the OS may
    /// have dropped the alert-free switch (every flip would pop the system
    /// modal — the exact interruption this option promises to avoid); the
    /// default primary icon already day/night-switches with the SYSTEM;
    /// singles have no faces to switch; pairs get the full explanation.
    private var iconCaptionKey: LocalizedStringKey {
        if !UIApplication.supportsSilentIconSwitching { return "mood_icon_follow_no_silent" }
        if iconManager.canFollowMood { return "mood_icon_follow_caption" }
        return iconManager.selected.isDefault ? "mood_icon_follow_default"
                                              : "mood_icon_follow_unavailable"
    }

    // MARK: Minutes ↔ Date plumbing (thresholds persist as minutes since midnight)

    private static func date(fromMinutes minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60,
                              second: 0, of: .now) ?? .now
    }

    private static func minutes(from date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Fractional hours → clamped minutes, rounded to 5 for a tidy seed.
    private static func minutes(fromHours hours: Double, in range: ClosedRange<Int>) -> Int {
        clamp(Int((hours * 60 / 5).rounded()) * 5, to: range)
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

// MARK: - Toggle row with caption (Apple Settings grammar)

private struct MoodToggleRow: View {
    let icon: String
    let title: LocalizedStringKey
    /// Prebuilt so captions can carry runtime values (the weather row
    /// quotes a recorded error); plain rows pass `Text("key")` as before.
    let caption: Text
    @Binding var isOn: Bool
    /// A fetch is in flight: the toggle yields to a small spinner and the
    /// caption says what is happening.
    var isBusy: Bool = false
    /// Dims and disables the toggle (and the badge/text) WITHOUT a
    /// row-level `.disabled`, which would also kill the retry button — a
    /// child inside a disabled parent can never re-enable itself.
    var dimsAsDisabled: Bool = false
    /// When set, a small retry affordance renders under the caption. It
    /// stays fully interactive and undimmed even while the toggle is not.
    var retry: (() -> Void)? = nil

    @Environment(\.isEnabled) private var isEnabled

    private var dimmed: Bool { dimsAsDisabled || !isEnabled }

    var body: some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon,
                             color: isOn && !dimmed ? .accentColor : Color.primary.opacity(0.4))
                .opacity(dimmed ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    Text(title)
                        .font(AppFont.scaled(15))
                        .foregroundStyle(.primary)
                    caption
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .opacity(dimmed ? 0.5 : 1)
                if let retry {
                    Button(action: retry) {
                        Text("mood_weather_retry")
                            .font(AppFont.scaled(12))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, AppSpacing.xxs)
                }
            }
            Spacer()
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            } else {
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .tint(.accentColor)
                    .disabled(dimsAsDisabled)
                    .opacity(dimmed ? 0.5 : 1)
            }
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, 13)
        // With a retry button inside, combining would swallow its action;
        // containment keeps the button reachable as its own element.
        .accessibilityElement(children: retry == nil ? .combine : .contain)
    }
}

// MARK: - Carousel card width (~3.5 visible)

private extension View {
    /// Each carousel card spans 2/7 of the container, so roughly 3.5 cards
    /// share the screen — enough to invite the swipe toward the rest.
    func carouselCardWidth() -> some View {
        containerRelativeFrame(.horizontal, count: 7, span: 2,
                               spacing: AppSpacing.md)
    }
}

// MARK: - Mood preview card (mini gradient thumbnail + emoji + title)

private struct MoodPreviewCard: View {
    let mood: AppMood
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.sm) {
                AppBackdrop(fixed: mood)
                    .frame(height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : Color.hairline,
                                          lineWidth: isSelected ? 2 : 1)
                    )
                // The glyph is symbolic; the localized name carries the
                // meaning (and is all VoiceOver ever reads).
                (Text(verbatim: mood.emoji) + Text(verbatim: " ") + Text(mood.titleKey))
                    .font(isSelected ? AppFont.footnoteEmphasis : AppFont.footnote)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.primary)
                                                : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(mood.titleKey))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Auto card (live composition preview + the winning reason)

/// The carousel's first card: a live thumbnail of whatever Auto composes
/// right now, and one caption line saying WHY ("Automat · apus",
/// "Automat · zi de sărbătoare") — the reason comes from the engine's own
/// composition, so it can never disagree with the preview above it.
private struct AutoMoodCard: View {
    let preview: AppMood
    let reason: AppMoodAutoReason
    let isSelected: Bool
    let action: () -> Void

    private var caption: String {
        String(format: String(localized: "mood_auto_card_caption"),
               reason.localizedLabel)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.sm) {
                AppBackdrop(fixed: preview)
                    .frame(height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        // The badge that says "this card composes itself".
                        Image(systemName: "sparkles")
                            .font(AppFont.scaled(13))
                            .foregroundStyle(preview.palette.accent)
                            .padding(AppSpacing.xs)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : Color.hairline,
                                          lineWidth: isSelected ? 2 : 1)
                    )
                Text(caption)
                    .font(isSelected ? AppFont.footnoteEmphasis : AppFont.footnote)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.primary)
                                                : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(caption))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
