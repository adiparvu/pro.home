import SwiftUI
import Observation

// MARK: - App mood (the living background's seven atmospheres)
//
// One mood drives the whole app's backdrop and color scheme: dimineața
// (morning) / zi (day) / apus (sunset) / noapte (night) / ploaie (rain) /
// iarnă (winter) / eveniment (event). Auto composes the first four from the
// clock — refined by the property's coordinates when they exist — then
// layers weather, season, and celebrations on top (the precedence is
// documented on `AppMoodEngine`); any of the seven can also be pinned
// manually from Settings → Aspect → Fundal, exactly like before.
//
// Honesty notes (constitution):
// - The sunrise/sunset window is a standard low-precision solar
//   approximation (same family as the retired Twin3D sun model): declination
//   from day-of-year, hour angle from the local clock. When a longitude is
//   available, solar noon is corrected for the time zone's offset (which
//   also absorbs DST); the equation of time (±16 min) is ignored. Good for
//   picking an atmosphere, never presented as an ephemeris.
// - Without coordinates the engine claims nothing about the sun — it follows
//   fixed clock windows (6–10 / 10–19 / 19–20 / 20–6, the 19–20 hour being
//   the coordinate-less sunset band), and the settings page's Auto
//   explanation says exactly that.
// - Custom Auto thresholds ("night starts at…") override only the edge they
//   name; the settings caption then says the hours are the user's, not the
//   sun's. The sunset band always derives from the real sun window (or the
//   fixed clock band); a custom night onset only decides where it ends —
//   and when the two cross, night wins. A pinned mood ignores them, so
//   their pickers never show then.
// - The weather tone comes only from a FRESH cached Apple Weather summary
//   (≤ 2h); with stale or missing data the backdrop claims nothing. The
//   same freshness rule gates the Auto rain MOOD (see AppMoodEngine).
// - The event layer claims only what it can prove: a curated in-code table
//   of Romanian legal holidays (sources cited at the table) and the family
//   roster's stored birth dates. House states (Vacanță / Petrecere) do not
//   exist yet, so Auto never pretends to know them — see the extension
//   point on `AppMoodEngine.eventToday`.

enum AppMood: String, CaseIterable, Identifiable {
    // Raw values are a persistence contract: they live in the stored
    // override ("app.mood.override"), the App Group publish
    // ("app.mood.current"), and the watch payload's `mood` field. Existing
    // values must never change; new atmospheres only ever append.
    case morning
    case day
    case sunset
    case night
    case rain
    case winter
    case event
    // The pre-atmosphere classics, kept by request (IMG_8622): one flat
    // light / dark ground, zero light pools, zero atmospheric effects.
    // Manual picks only — Auto never resolves to them.
    case classicLight = "classic_light"
    case classicDark  = "classic_dark"

    var id: String { rawValue }

    /// The two flat classics — no accents, no effects, scheme pinned.
    var isClassic: Bool { self == .classicLight || self == .classicDark }

    var titleKey: LocalizedStringKey {
        switch self {
        case .morning: "mood_morning"
        case .day:     "mood_day"
        case .sunset:  "mood_sunset"
        case .night:   "mood_night"
        case .rain:    "mood_rain"
        case .winter:  "mood_winter"
        case .event:   "mood_event"
        case .classicLight: "mood_classic_light"
        case .classicDark:  "mood_classic_dark"
        }
    }

    /// Resolved string for contexts that need a `String` (settings row
    /// values, accessibility labels).
    var localizedTitle: String {
        switch self {
        case .morning: String(localized: "mood_morning")
        case .day:     String(localized: "mood_day")
        case .sunset:  String(localized: "mood_sunset")
        case .night:   String(localized: "mood_night")
        case .rain:    String(localized: "mood_rain")
        case .winter:  String(localized: "mood_winter")
        case .event:   String(localized: "mood_event")
        case .classicLight: String(localized: "mood_classic_light")
        case .classicDark:  String(localized: "mood_classic_dark")
        }
    }

    /// The mood's picker glyph (Settings → Aspect → Fundal carousel).
    /// Symbolic, not user text — the localized name always sits beside it.
    var emoji: String {
        switch self {
        case .morning: "🌅"
        case .day:     "☀️"
        case .sunset:  "🌇"
        case .night:   "🌙"
        case .rain:    "🌧️"
        case .winter:  "❄️"
        case .event:   "🎉"
        case .classicLight: "⬜️"
        case .classicDark:  "⬛️"
        }
    }

    /// The mood's background palette (tokens live in DesignSystem.swift so
    /// the palette values sit with every other design token).
    var palette: AppMoodPalette {
        switch self {
        case .morning: .morning
        case .day:     .day
        case .sunset:  .sunset
        case .night:   .night
        case .rain:    .rain
        case .winter:  .winter
        case .event:   .event
        case .classicLight: .classicLight
        case .classicDark:  .classicDark
        }
    }

    // MARK: Automatic resolution (the TIME base only)

    /// The time-of-day base of the Auto composition — it only ever returns
    /// morning / day / sunset / night; the weather, season, and event layers
    /// live in `AppMoodEngine` where their data sources are.
    ///
    /// Sunrise..10h → morning; 10h..(sunset−45m) → day; (sunset−45m)..
    /// (sunset+45m) → sunset (golden hour straddles the real sun);
    /// everything else → night. Without coordinates (or inside a polar
    /// day/night) the fixed clock windows apply (6–10 / 10–19 / 19–20 /
    /// 20–6). In a high-latitude winter where the sun rises after 10h, the
    /// morning band collapses and day starts at sunrise.
    ///
    /// `morningStart`/`nightStart` (fractional local-clock hours) are the
    /// user's optional custom thresholds: each one overrides ONLY the edge
    /// it names — morning onset (sunrise / 6h) or night onset (sunset+45m /
    /// 20h) — and every other edge keeps its sun/clock default. The sunset
    /// band's START always derives from the sun window (or the 19h clock
    /// band); a custom night onset only moves where the band ENDS, and when
    /// it starts before the band does, night wins and the band collapses.
    static func auto(at date: Date = .now,
                     latitude: Double?,
                     longitude: Double? = nil,
                     morningStart: Double? = nil,
                     nightStart: Double? = nil) -> AppMood {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = Double(parts.hour ?? 12) + Double(parts.minute ?? 0) / 60

        let edges = defaultEdges(on: date, latitude: latitude, longitude: longitude)
        let morningBegin = morningStart ?? edges.morning
        let nightBegin = nightStart ?? edges.night
        // The sunset band never outlives night's onset (night wins a cross).
        let duskBegin = min(edges.dusk, nightBegin)
        // Day never begins before 10h (the original band) nor after dusk.
        let dayBegin = min(max(10, morningBegin), max(morningBegin, duskBegin))

        if hour < morningBegin || hour >= nightBegin { return .night }
        if hour < dayBegin { return .morning }
        return hour < duskBegin ? .day : .sunset
    }

    /// The automatic edges a given day would use with no custom thresholds:
    /// morning onset (sunrise, or 6h without coordinates / in polar
    /// day/night), dusk onset (sunset−45m, or 19h — where the sunset band
    /// begins), and night onset (sunset+45m, or 20h). The settings page
    /// seeds its custom-hour pickers from `morning`/`night`, so "reset" is
    /// always honest about what Auto would actually do today.
    static func defaultEdges(on date: Date = .now,
                             latitude: Double?,
                             longitude: Double? = nil)
        -> (morning: Double, dusk: Double, night: Double) {
        guard let latitude,
              let sun = SunWindow.compute(on: date, latitude: latitude,
                                          longitude: longitude) else {
            return (6, 19, 20)
        }
        return (sun.sunrise, sun.sunset - 0.75, sun.sunset + 0.75)
    }

    // MARK: Season (the Auto winter layer's only input)

    /// December–February. The primary property is in Romania — northern
    /// hemisphere — so the winter months are hardcoded honestly rather than
    /// pretending to read a hemisphere the model doesn't store; if southern
    /// properties ever arrive, derive this from the property's latitude.
    static func isWinterSeason(_ date: Date = .now,
                               calendar: Calendar = .current) -> Bool {
        let month = calendar.component(.month, from: date)
        return month == 12 || month <= 2
    }
}

// MARK: - Approximate sunrise/sunset window

/// Local-clock sunrise and sunset hours from the standard low-precision
/// solar approximation (see the honesty notes at the top of this file).
private struct SunWindow {
    /// Local clock hours (0–24, fractional).
    let sunrise: Double
    let sunset: Double

    static func compute(on date: Date, latitude: Double,
                        longitude: Double?) -> SunWindow? {
        let calendar = Calendar.current
        let dayOfYear = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 172)
        let phi = latitude * .pi / 180
        let declination = -23.44 * cos(2 * .pi * (dayOfYear + 10) / 365) * .pi / 180

        // Half-day arc: cos(H0) = −tanφ·tanδ. Out of range → polar day or
        // polar night; the caller falls back to the clock windows.
        let cosH0 = -tan(phi) * tan(declination)
        guard cosH0 > -1, cosH0 < 1 else { return nil }
        let halfDayHours = acos(cosH0) * 180 / .pi / 15

        // Solar noon on the local clock. With a longitude the time zone's
        // offset (incl. DST) is corrected for; without one, 12:00 is assumed.
        var solarNoon = 12.0
        if let longitude {
            let zoneHours = Double(TimeZone.current.secondsFromGMT(for: date)) / 3600
            solarNoon = 12 + zoneHours - longitude / 15
        }
        return SunWindow(sunrise: solarNoon - halfDayHours,
                         sunset: solarNoon + halfDayHours)
    }
}

// MARK: - App appearance (the theme, SEPARATE from the atmosphere)

/// The app's color-scheme control (IMG_8678, user-decreed): picking a theme
/// must never disable the living backgrounds. `.mood` is the original
/// behavior — the scheme follows the atmosphere's palette; the other three
/// pin light/dark or defer to the device while the backdrop keeps living
/// (AppBackdrop already resolves a palette/scheme disagreement by swapping
/// to the matching palette).
enum AppAppearance: String, CaseIterable, Identifiable {
    case mood
    case system
    case light
    case dark

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .mood:   "appearance_mood"
        case .system: "appearance_system"
        case .light:  "appearance_light"
        case .dark:   "appearance_dark"
        }
    }
}

// MARK: - AppMoodEngine

/// The single mood authority. Views read `resolved`; the settings page
/// writes `override` (persisted; nil = Auto) and the optional custom Auto
/// thresholds; the app shell provides the primary property's coordinates
/// when it has them (PropertyService is a per-scene `@State` service, not a
/// singleton — the engine never reaches into the environment itself).
///
/// AUTO COMPOSITION — the layers and their exact precedence, top wins:
///  1. EVENT (whole day): today is a Romanian legal holiday (curated
///     in-code table, sources cited there) or a family member's birthday
///     (the roster's stored birth dates, read from the same offline cache
///     `FamilyService` hydrates from) → `.event`.
///  2. WEATHER RAIN: the weather-reactive toggle is ON and a FRESH (≤ 2h)
///     cached Apple Weather summary maps to `AppWeatherTone.rain` → the
///     morning/day/sunset/winter base becomes `.rain`. Night stays night —
///     rain after dark keeps the night palette with the existing wash
///     modulation, which reads more honestly than a bright rain ground.
///  3. SEASON: December–February (northern hemisphere, hardcoded — see
///     `AppMood.isWinterSeason`) shifts the broad DAY base to `.winter`;
///     morning and sunset keep their character at the day's edges.
///  4. TIME base: sunrise..10h morning, 10h..sunset−45m day, ±45m around
///     sunset the sunset band, else night (`AppMood.auto`; the fixed clock
///     windows without coordinates, custom thresholds for the
///     morning/night edges).
/// A manual `override` bypasses the whole composition — a flat pick of any
/// of the seven moods, exactly like before.
///
/// Recomputation is event-driven, never continuous: an internal 15-minute
/// timer runs only while at least one live `AppBackdrop` is on screen
/// (ref-counted from the view's appear/disappear), plus a refresh whenever
/// the scene becomes active. Resolution itself is O(1) arithmetic.
///
/// Every change of the resolved mood is published to the shared App Group
/// suite ("app.mood.current" = the raw mood, "app.mood.scheme" =
/// "light"/"dark") for the widgets/watch, and announced in-process via
/// `Notification.Name.appMoodResolvedChanged` (the icon manager listens).
@MainActor
@Observable
final class AppMoodEngine {
    static let shared = AppMoodEngine()

    private static let overrideKey = "app.mood.override"
    private static let appearanceKey = "app.appearance.mode"
    private static let morningStartKey = "app.mood.morningStart"
    private static let nightStartKey = "app.mood.nightStart"
    private static let weatherReactiveKey = "app.mood.weatherReactive"
    private static let publishedMoodKey = "app.mood.current"
    private static let publishedSchemeKey = "app.mood.scheme"

    /// The theme (Settings → Aspect → Fundal), persisted. Controls ONLY the
    /// root color scheme — the atmosphere keeps living under any of them.
    var appearance: AppAppearance = .mood {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    /// The root `.preferredColorScheme` value: the atmosphere's own scheme
    /// in `.mood`, the device's in `.system`, or the pinned scheme.
    var preferredScheme: ColorScheme? {
        switch appearance {
        case .mood:   resolved.palette.colorScheme
        case .system: nil
        case .light:  ColorScheme.light
        case .dark:   ColorScheme.dark
        }
    }

    /// Manual mood pin; nil follows the clock (Auto). Persisted.
    var override: AppMood? {
        didSet {
            if let override {
                UserDefaults.standard.set(override.rawValue, forKey: Self.overrideKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.overrideKey)
            }
            publishResolvedIfChanged()
        }
    }

    /// Custom Auto thresholds, stored as MINUTES SINCE MIDNIGHT (0–1439);
    /// nil = today's sun/clock behavior. Each overrides only the edge it
    /// names (see `AppMood.auto`). A pinned mood ignores them entirely.
    var morningStartMinutes: Int? {
        didSet {
            persist(minutes: morningStartMinutes, key: Self.morningStartKey)
            publishResolvedIfChanged()
        }
    }
    var nightStartMinutes: Int? {
        didSet {
            persist(minutes: nightStartMinutes, key: Self.nightStartKey)
            publishResolvedIfChanged()
        }
    }

    /// True while at least one custom Auto threshold is set.
    var hasCustomHours: Bool { morningStartMinutes != nil || nightStartMinutes != nil }

    /// Whether the backdrop may modulate with the property's real weather
    /// (Settings → Aspect → Fundal). Persisted; default ON. The toggle only
    /// ever matters when a fresh cached summary exists — see `weatherTone`.
    var weatherReactive: Bool {
        didSet {
            UserDefaults.standard.set(weatherReactive, forKey: Self.weatherReactiveKey)
            refreshWeatherTone()
            // The toggle now also gates the Auto rain MOOD, so flipping it
            // can change what the whole app shows — republish.
            publishResolvedIfChanged()
        }
    }

    /// The current weather modulation layer for live backdrops: non-nil only
    /// when the feature is on AND a fresh (≤ 2h) cached summary maps to a
    /// tone. Reassigned only when the value actually changes, so backdrops
    /// are never invalidated by a no-op tick.
    private(set) var weatherTone: AppWeatherTone?

    /// Primary property coordinates, provided by the app shell when known.
    /// Latitude alone already refines the sun window; longitude additionally
    /// corrects solar noon for the time zone.
    var latitude: Double? {
        didSet { if latitude != oldValue { publishResolvedIfChanged() } }
    }
    var longitude: Double? {
        didSet { if longitude != oldValue { publishResolvedIfChanged() } }
    }

    /// True while no manual pin is set.
    var isAuto: Bool { override == nil }

    /// What the app shows right now: the manual pin, or the full Auto
    /// composition (event > rain > winter > time — see the class comment).
    var resolved: AppMood {
        override ?? autoResolved
    }

    /// What Auto composes right now, independent of any pin — the settings
    /// page's Auto card previews exactly this.
    var autoResolved: AppMood {
        compose(base: dateBase(at: clock))
    }

    /// WHY Auto shows what it shows — the settings page's Auto caption
    /// ("Automat · apus", "Automat · zi de sărbătoare"). Mirrors `compose`
    /// exactly, so the stated reason can never drift from the shown mood.
    var autoReason: AppMoodAutoReason {
        switch eventToday {
        case .holiday:  return .holiday
        case .birthday: return .birthday
        case nil:       break
        }
        let base = dateBase(at: clock)
        if weatherTone == .rain, base != .night { return .rain }
        if base == .winter { return .winter }
        return .time(base)
    }

    /// Today's celebration, if any — the Auto event layer's whole truth.
    /// Recomputed once per calendar day (and when the day rolls over under
    /// a running app) from the holiday table and the family roster's cached
    /// birth dates. EXTENSION POINT: when house states (Vacanță / Petrecere)
    /// exist as real data, they join this enum and `refreshEventDay` — Auto
    /// never fakes a toggle for state the app cannot read yet.
    private(set) var eventToday: AppMoodEventReason?

    /// The calendar day `eventToday` was computed for (start of day), so the
    /// roster file is re-read at most once per day, not every 15-minute tick.
    @ObservationIgnored private var eventDay: Date?

    /// The observation-tracked "now" that `resolved` derives from. Only
    /// reassigned when the automatic mood actually changes, so the dozens of
    /// on-screen backdrops aren't invalidated by a no-op tick.
    private var clock: Date = .now

    @ObservationIgnored private var liveBackdrops = 0
    @ObservationIgnored private var timer: Timer?
    /// The last mood written to the App Group (dedupes publishes).
    @ObservationIgnored private var publishedMood: AppMood?
    /// Weather-cache observation token (the singleton never deallocates,
    /// so the registration is for life — kept only for clarity of intent).
    @ObservationIgnored private var weatherCacheObserver: NSObjectProtocol?

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.overrideKey) ?? ""
        override = AppMood(rawValue: stored)
        appearance = UserDefaults.standard.string(forKey: Self.appearanceKey)
            .flatMap(AppAppearance.init) ?? .mood
        // Migration (IMG_8678): the classics left the atmosphere carousel —
        // a stored classic pin becomes its THEME and the atmosphere returns
        // to Auto. Property observers don't fire in init, so persist by hand.
        if let pinned = override, pinned.isClassic {
            if UserDefaults.standard.string(forKey: Self.appearanceKey) == nil {
                appearance = pinned == .classicLight ? .light : .dark
                UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey)
            }
            override = nil
            UserDefaults.standard.removeObject(forKey: Self.overrideKey)
        }
        morningStartMinutes = Self.readMinutes(key: Self.morningStartKey)
        nightStartMinutes = Self.readMinutes(key: Self.nightStartKey)
        weatherReactive = (UserDefaults.standard.object(forKey: Self.weatherReactiveKey) as? Bool) ?? true
        refreshWeatherTone()
        refreshEventDay(on: .now)
        // Seed the App Group without posting: observers registering later
        // (IconManager) check the engine themselves at startup, and posting
        // from inside the singleton's own `init` could re-enter `shared`.
        publishResolvedIfChanged(posting: false)
        // A freshly fetched weather summary recomposes Auto immediately —
        // rain arrives with the data, not on the next 15-minute tick. The
        // closure resolves `shared` lazily (never during this init), so the
        // singleton's own construction is never re-entered.
        weatherCacheObserver = NotificationCenter.default.addObserver(
            forName: .propertyWeatherCacheDidUpdate, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in AppMoodEngine.shared.refresh() }
        }
    }

    /// The date-derived part of Auto — time base plus the season layer
    /// (both pure functions of the date, so `refresh` can compare them
    /// across ticks): `AppMood.auto` with this engine's coordinates and
    /// custom thresholds, with the broad day window turned to winter in
    /// December–February. Morning and sunset keep their character.
    private func dateBase(at date: Date) -> AppMood {
        let base = AppMood.auto(at: date, latitude: latitude, longitude: longitude,
                                morningStart: morningStartMinutes.map { Double($0) / 60 },
                                nightStart: nightStartMinutes.map { Double($0) / 60 })
        if base == .day, AppMood.isWinterSeason(date) { return .winter }
        return base
    }

    /// Layers the state-derived signals over a date base, in the documented
    /// precedence: event (whole day) > weather rain (never at night —
    /// night keeps its palette and the existing wash) > the base itself
    /// (which already carries the winter season shift).
    private func compose(base: AppMood) -> AppMood {
        if eventToday != nil { return .event }
        if weatherTone == .rain, base != .night { return .rain }
        return base
    }

    /// Today's sun/clock edges (fractional hours) — what Auto uses when no
    /// custom threshold is set; the settings pickers seed from
    /// `morning`/`night`, and `dusk` is where the sunset band begins.
    func defaultEdges() -> (morning: Double, dusk: Double, night: Double) {
        AppMood.defaultEdges(latitude: latitude, longitude: longitude)
    }

    /// Re-evaluates the automatic mood, the weather tone, and (on a day
    /// change) the event layer (scene became active, timer tick).
    func refresh() {
        let now = Date.now
        if dateBase(at: now) != dateBase(at: clock) {
            clock = now
        }
        refreshWeatherTone()
        refreshEventDay(on: now)
        publishResolvedIfChanged()
    }

    // MARK: Event day (holidays + family birthdays, once per calendar day)

    /// Recomputes `eventToday` when the calendar day changed (or was never
    /// computed). The birthday source is the family roster's offline cache —
    /// the very rows `FamilyService` hydrates from and the dashboard's
    /// birthday feed reads — so the layer is exactly as fresh as the app's
    /// own family data and costs one small file read per day. A property
    /// switch is picked up on the next refresh tick the same way.
    private func refreshEventDay(on date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        guard day != eventDay else { return }
        eventDay = day
        let reason: AppMoodEventReason?
        if RomanianLegalHolidays.contains(day) {
            reason = .holiday
        } else if Self.hasFamilyBirthday(on: day) {
            reason = .birthday
        } else {
            reason = nil
        }
        if reason != eventToday { eventToday = reason }
    }

    /// True when a family member's stored birth date (month + day) matches
    /// the given day — the same match the dashboard's Today feed makes.
    private static func hasFamilyBirthday(on day: Date) -> Bool {
        guard let members = ServiceCache.load([FamilyMember].self, entity: "family",
                                              propertyId: PropertyService.activePropertyId),
              !members.isEmpty else { return false }
        let cal = Calendar.current
        let today = cal.dateComponents([.month, .day], from: day)
        return members.contains { member in
            guard let birth = member.birthdayDate else { return false }
            let b = cal.dateComponents([.month, .day], from: birth)
            return b.month == today.month && b.day == today.day
        }
    }

    // MARK: Weather tone (event-driven, from the cached summary only)

    /// Recomputes the tone from the cached Apple Weather summary. Never
    /// fetches; never assigns unless the tone actually changed.
    private func refreshWeatherTone() {
        let tone = weatherReactive ? AppWeatherTone.fromFreshCache() : nil
        if tone != weatherTone { weatherTone = tone }
    }

    // MARK: Cross-process publish + in-process notification

    /// Writes the resolved mood (and its color scheme) to the shared App
    /// Group whenever it changed, and posts `.appMoodResolvedChanged`.
    /// Widgets and the watch read exactly these keys.
    private func publishResolvedIfChanged(posting: Bool = true) {
        let mood = resolved
        guard mood != publishedMood else { return }
        publishedMood = mood
        if let ud = UserDefaults(suiteName: SharedDataStore.suiteName) {
            ud.set(mood.rawValue, forKey: Self.publishedMoodKey)
            ud.set(mood.palette.colorScheme == .dark ? "dark" : "light",
                   forKey: Self.publishedSchemeKey)
        }
        if posting {
            NotificationCenter.default.post(name: .appMoodResolvedChanged, object: nil)
        }
    }

    private func persist(minutes: Int?, key: String) {
        if let minutes {
            UserDefaults.standard.set(minutes, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private static func readMinutes(key: String) -> Int? {
        UserDefaults.standard.object(forKey: key) as? Int
    }

    // MARK: Backdrop lifecycle (ref-counted 15-minute tick)

    /// Called by every live `AppBackdrop`'s `onAppear`. The first visible
    /// backdrop starts the shared timer; there is never more than one.
    func backdropAppeared() {
        liveBackdrops += 1
        guard timer == nil else { return }
        refresh()
        let t = Timer(timeInterval: 15 * 60, repeats: true) { _ in
            Task { @MainActor in AppMoodEngine.shared.refresh() }
        }
        t.tolerance = 90   // let the system coalesce wakeups — battery first
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Called by every live `AppBackdrop`'s `onDisappear`. The last one off
    /// screen stops the timer — nothing ticks while the app shows no backdrop.
    func backdropDisappeared() {
        liveBackdrops = max(0, liveBackdrops - 1)
        if liveBackdrops == 0 {
            timer?.invalidate()
            timer = nil
        }
    }
}

// MARK: - Auto reasons (why Auto shows what it shows)

/// Today's celebration, as the event layer proved it.
enum AppMoodEventReason: Equatable {
    case holiday    // Romanian legal holiday (curated table below)
    case birthday   // a family member's stored birth date is today
}

/// The single winning reason behind `AppMoodEngine.autoResolved`, for the
/// settings page's honest Auto caption. One case per layer, plus the time
/// base itself.
enum AppMoodAutoReason: Equatable {
    case time(AppMood)   // morning / day / sunset / night — the clock/sun base
    case rain            // fresh weather at the property says rain
    case winter          // December–February day window
    case holiday         // Romanian legal holiday
    case birthday        // a family member's birthday

    /// Lowercase, sentence-embeddable label ("Automat · apus").
    var localizedLabel: String {
        switch self {
        case .time(.morning): String(localized: "mood_auto_reason_morning")
        case .time(.day):     String(localized: "mood_auto_reason_day")
        case .time(.sunset):  String(localized: "mood_auto_reason_sunset")
        case .time(.night):   String(localized: "mood_auto_reason_night")
        // The layered moods never arrive as a time base; if one ever did,
        // its own name is still the honest description.
        case .time(let other): other.localizedTitle
        case .rain:     String(localized: "mood_auto_reason_rain")
        case .winter:   String(localized: "mood_auto_reason_winter")
        case .holiday:  String(localized: "mood_auto_reason_holiday")
        case .birthday: String(localized: "mood_auto_reason_birthday")
        }
    }
}

// MARK: - Romanian legal holidays (the event layer's curated table)

/// Zilele libere legale din România — the days the whole house celebrates.
/// Sources: Codul Muncii (Legea 53/2003) art. 139 alin. (1), including the
/// days added by Legea 176/2018 (Vinerea Mare), Legea 220/2016 (1 iunie),
/// and Legea 52/2023 (6–7 ianuarie, in force since 2024).
///
/// Fixed dates are year-independent. The Orthodox Easter–derived days
/// (Vinerea Mare, Paștele, Rusaliile) move with the Julian computus, so
/// they are precomputed for 2026–2028 from the published Orthodox calendar
/// (Easter Sunday: 2026-04-12, 2027-05-02, 2028-04-16). Outside those
/// years only the fixed dates apply — honest degradation, never a guess.
enum RomanianLegalHolidays {
    /// (month, day) — every year.
    private static let fixed: Set<[Int]> = [
        [1, 1], [1, 2],    // Anul Nou
        [1, 6],            // Boboteaza (legal since 2024)
        [1, 7],            // Sfântul Ioan Botezătorul (legal since 2024)
        [1, 24],           // Unirea Principatelor Române
        [5, 1],            // Ziua Muncii
        [6, 1],            // Ziua Copilului
        [8, 15],           // Adormirea Maicii Domnului
        [11, 30],          // Sfântul Andrei
        [12, 1],           // Ziua Națională
        [12, 25], [12, 26] // Crăciunul
    ]

    /// (year, month, day) — Orthodox Easter–derived: Vinerea Mare (E−2),
    /// Paștele (E, E+1), Rusaliile (E+49, E+50).
    private static let easterDerived: Set<[Int]> = [
        // 2026 — Easter Sunday April 12
        [2026, 4, 10], [2026, 4, 12], [2026, 4, 13], [2026, 5, 31], [2026, 6, 1],
        // 2027 — Easter Sunday May 2
        [2027, 4, 30], [2027, 5, 2], [2027, 5, 3], [2027, 6, 20], [2027, 6, 21],
        // 2028 — Easter Sunday April 16
        [2028, 4, 14], [2028, 4, 16], [2028, 4, 17], [2028, 6, 4], [2028, 6, 5],
    ]

    static func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let p = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = p.year, let month = p.month, let day = p.day else { return false }
        return fixed.contains([month, day]) || easterDerived.contains([year, month, day])
    }
}

// MARK: - Resolved-mood change notification

extension Notification.Name {
    /// Posted by `AppMoodEngine` (main actor) every time the RESOLVED mood
    /// changes — auto rollover, manual pin, threshold or coordinate change.
    /// `IconManager` listens to swap the mood-following app icon.
    static let appMoodResolvedChanged = Notification.Name("app.mood.resolvedChanged")
}

// MARK: - Nonisolated last-published mood

extension AppMood {
    /// The mood the engine last published to the shared App Group — kept
    /// current by `AppMoodEngine.publishResolvedIfChanged()`. Nonisolated on
    /// purpose: the "auto" accent resolver (`avatarRingColor`) is called
    /// from UIKit appearance setup outside the main actor, where the engine
    /// itself is unreachable. Falls back to the persisted override, then to
    /// the coordinate-less clock windows, for the moments before the
    /// engine's first write.
    static var lastPublished: AppMood {
        // Keys must match AppMoodEngine's publish/override keys exactly.
        if let raw = UserDefaults(suiteName: SharedDataStore.suiteName)?
            .string(forKey: "app.mood.current"),
           let mood = AppMood(rawValue: raw) {
            return mood
        }
        if let raw = UserDefaults.standard.string(forKey: "app.mood.override"),
           let mood = AppMood(rawValue: raw) {
            return mood
        }
        return .auto(at: .now, latitude: nil)
    }
}

// MARK: - Weather tone (the backdrop's weather modulation)

/// A subtle weather wash blended over the mood palette — one extra
/// low-opacity layer. Derived exclusively from the property's FRESH cached
/// Apple Weather summary (≤ 2 hours old — stale data claims nothing about
/// now) by mapping its SF symbol name. Clear skies map to no tone at all.
/// Since Mood 2.0 the `.rain` tone additionally feeds the Auto composition
/// (a rainy morning/day/sunset resolves to the dedicated rain MOOD — see
/// `AppMoodEngine.compose`); the wash itself remains what live backdrops
/// blend, with the same freshness rules as before.
enum AppWeatherTone: Equatable {
    case rain       // rain / drizzle / storms — cool gray-blue
    case snow       // snow / sleet / flurries — whiter, quieter
    case overcast   // fog / haze / clouds — desaturated

    /// Freshness bound: beyond this the cached summary is ignored entirely.
    static let maxAge: TimeInterval = 2 * 3600

    /// True while a fresh (≤ 2h) cached summary exists at all — the
    /// settings row disables itself honestly on this instead of showing a
    /// toggle that could not do anything.
    static var hasFreshSummary: Bool {
        guard let summary = PropertyWeather.cached() else { return false }
        return Date().timeIntervalSince(summary.fetchedAt) <= maxAge
    }

    /// The tone for the current fresh cached summary, if any.
    static func fromFreshCache(now: Date = .now) -> AppWeatherTone? {
        guard let summary = PropertyWeather.cached(),
              now.timeIntervalSince(summary.fetchedAt) <= maxAge else { return nil }
        return tone(forSymbol: summary.symbol)
    }

    /// SF symbol name → tone. Priority matters: "cloud.snow" must land on
    /// snow and "cloud.bolt.rain" on rain before either falls into the
    /// plain cloud bucket. Sun, moon, and wind symbols return nil.
    static func tone(forSymbol symbol: String) -> AppWeatherTone? {
        let s = symbol.lowercased()
        if ["snow", "sleet", "flurr", "blizzard", "flake"].contains(where: s.contains) {
            return .snow
        }
        if ["rain", "drizzle", "storm", "bolt", "hail", "hurricane", "tropical"]
            .contains(where: s.contains) {
            return .rain
        }
        if ["fog", "haze", "smoke", "dust", "cloud"].contains(where: s.contains) {
            return .overcast
        }
        return nil
    }

    /// The single wash layer `AppBackdrop` lays over the palette, already
    /// carrying its opacity. Values are capped so text keeps AA contrast in
    /// both schemes (worst cases measured: white text over night + snow
    /// ≥ 14:1; near-black text over day + rain ≥ 15.9:1).
    func wash(for scheme: ColorScheme) -> Color {
        let dark = scheme == .dark
        switch self {
        case .rain:
            return dark
                ? Color(red: 0.141, green: 0.220, blue: 0.306).opacity(0.16) // #24384E
                : Color(red: 0.333, green: 0.404, blue: 0.478).opacity(0.10) // #55677A
        case .snow:
            return Color.white.opacity(dark ? 0.06 : 0.30)
        case .overcast:
            return dark
                ? Color(red: 0.604, green: 0.627, blue: 0.651).opacity(0.05) // #9AA0A6
                : Color(red: 0.431, green: 0.431, blue: 0.451).opacity(0.08) // #6E6E73
        }
    }
}
