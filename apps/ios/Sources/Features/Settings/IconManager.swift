import SwiftUI
import Observation

// MARK: - App Icon theme model
//
// Each theme is one entry in the gallery. A theme is either:
//   • a light/dark PAIR — two alternate icons that IconManager swaps between as
//     the system appearance changes (iOS auto-switches only the *primary* icon,
//     never alternates, so we do it manually), or
//   • a SINGLE icon that looks the same in both modes.
//
// The `default` theme uses the primary AppIcon (alternate name = nil), which the
// asset catalog auto-switches light/dark on its own.
//
// Preview images are regular imagesets (`<key>`); the launchable icons are app
// icon assets (`AppIcon<key>`). They're separate because UIKit can't load an
// app-icon asset with `UIImage(named:)`.

struct AppIconTheme: Identifiable, Equatable {
    let id: String
    let name: String
    /// Localized one-line story, keyed by the two primary languages.
    let storyRO: String
    let storyEN: String
    let category: Category
    /// Preview imageset names.
    let lightPreview: String
    let darkPreview: String?
    /// Alternate icon asset names (nil light+dark ⇒ the default primary icon).
    let lightIcon: String?
    let darkIcon: String?

    var hasPair: Bool { darkPreview != nil }
    var isDefault: Bool { lightIcon == nil && darkIcon == nil }

    var story: String { Locale.appIsRomanian ? storyRO : storyEN }

    /// The merged day/night asset for pair themes: ONE alternate icon whose
    /// dark variant iOS renders by itself — no setAlternateIconName on theme
    /// change, so the system "You have changed the icon" alert never fires
    /// for appearance switches. Naming: "…Light" pairs drop the suffix
    /// ("AppIconGlass"), joined singles gain "Set" ("AppIconRoseMochaSet").
    var pairedIcon: String? {
        guard hasPair, let lightIcon else { return nil }
        return lightIcon.hasSuffix("Light") ? String(lightIcon.dropLast(5)) : lightIcon + "Set"
    }

    /// The alternate icon name to install for a given appearance (nil = primary).
    func iconName(isDark: Bool) -> String? {
        if isDefault { return nil }
        if hasPair { return isDark ? darkIcon : lightIcon }
        return lightIcon
    }

    enum Category: String, CaseIterable, Identifiable {
        case signature, elegant, nature, vibrant, minimal
        var id: String { rawValue }
        var titleRO: String {
            switch self {
            case .signature: return "Semnătură"
            case .elegant:   return "Elegante"
            case .nature:    return "Natură"
            case .vibrant:   return "Vibrante"
            case .minimal:   return "Minimale"
            }
        }
        var titleEN: String {
            switch self {
            case .signature: return "Signature"
            case .elegant:   return "Elegant"
            case .nature:    return "Nature"
            case .vibrant:   return "Vibrant"
            case .minimal:   return "Minimal"
            }
        }
        var title: String { Locale.appIsRomanian ? titleRO : titleEN }
    }
}

extension Locale {
    /// True when the app is running in Romanian.
    ///
    /// Reads the app's own saved choice (`prvio.locale` / `prvio.followSystemLang`)
    /// rather than `Locale.preferredLanguages`, which stays cached at its launch
    /// value until the process restarts — so this flips the instant the user picks
    /// a language, keeping RO/EN copy in sync with the rest of the UI without a
    /// relaunch.
    static var appIsRomanian: Bool {
        let followSystem = (UserDefaults.standard.object(forKey: "prvio.followSystemLang") as? Bool) ?? false
        if followSystem {
            return (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("ro")
        }
        let saved = UserDefaults.standard.string(forKey: "prvio.locale") ?? "ro"
        return saved.lowercased().hasPrefix("ro")
    }
}

// MARK: - Catalog

enum AppIconCatalog {
    private static func pair(_ id: String, _ name: String, base: String,
                             _ cat: AppIconTheme.Category, _ ro: String, _ en: String,
                             isDefault: Bool = false) -> AppIconTheme {
        AppIconTheme(
            id: id, name: name, storyRO: ro, storyEN: en, category: cat,
            lightPreview: base + "Light", darkPreview: base + "Dark",
            lightIcon: isDefault ? nil : "AppIcon" + base + "Light",
            darkIcon:  isDefault ? nil : "AppIcon" + base + "Dark"
        )
    }

    private static func single(_ id: String, _ name: String, asset: String,
                               _ cat: AppIconTheme.Category, _ ro: String, _ en: String) -> AppIconTheme {
        AppIconTheme(
            id: id, name: name, storyRO: ro, storyEN: en, category: cat,
            lightPreview: asset, darkPreview: nil,
            lightIcon: "AppIcon" + asset, darkIcon: nil
        )
    }

    static let all: [AppIconTheme] = [
        // Signature
        AppIconTheme(id: "default", name: "PRVIO",
            storyRO: "Semnătura casei. Se schimbă singură între zi și noapte, odată cu sistemul.",
            storyEN: "The house signature. It shifts between day and night on its own, with the system.",
            category: .signature,
            lightPreview: "PrimaryLight", darkPreview: "PrimaryDark", lightIcon: nil, darkIcon: nil),
        pair("glass", "Liquid Glass", base: "Glass", .signature,
             "Sticlă lichidă, lumină care curge. Iconul iOS 26, translucid și viu.",
             "Liquid glass, flowing light. The iOS 26 icon — translucent and alive."),
        pair("classic", "Clasic", base: "Classic", .signature,
             "Bleumarin și aur. Clasicul care nu iese niciodată din modă.",
             "Navy and gold. The classic that never goes out of style."),

        // Elegant
        pair("roseGold", "Rose Gold", base: "RoseGold", .elegant,
             "Cupru cald, finisaj de bijuterie. Eleganță discretă pe ecranul tău.",
             "Warm copper, a jeweller's finish. Quiet elegance on your screen."),
        pair("baroque", "Baroc", base: "Baroque", .elegant,
             "Opulență aurie pe catifea. Pentru cine vrea ca acasă să respire lux.",
             "Golden opulence on velvet. For a home that breathes luxury."),
        pair("metallic", "Metalic", base: "Metallic", .elegant,
             "Metal șlefuit, reflexii reci. Precizie industrială, rafinată.",
             "Brushed metal, cool reflections. Industrial precision, refined."),
        // Two single designs joined into a day/night set: liquid gold by
        // day, gold on black by night.
        AppIconTheme(id: "metallic-gold", name: "Aur Lichid",
            storyRO: "Aur topit ziua, aur pe negru profund noaptea.",
            storyEN: "Molten gold by day, gold on deep black by night.",
            category: .elegant,
            lightPreview: "MetallicGold", darkPreview: "GoldNoir",
            lightIcon: "AppIconMetallicGold", darkIcon: "AppIconGoldNoir"),
        AppIconTheme(id: "rose-mocha", name: "Rose Mocha",
            storyRO: "Roz-cafeniu cald ziua, cupru pe noapte adâncă seara.",
            storyEN: "Warm rosy mocha by day, rose copper on deep night after dark.",
            category: .elegant,
            lightPreview: "RoseMocha", darkPreview: "RoseNoir",
            lightIcon: "AppIconRoseMocha", darkIcon: "AppIconRoseNoir"),
        single("silver-noir", "Argint Nocturn", asset: "SilverNoir", .elegant,
               "Argint pur pe umbră. Sobrietate lucioasă.",
               "Pure silver on shadow. Glossy restraint."),
        single("baroque-cream", "Baroc Crem", asset: "BaroqueCream", .elegant,
               "Marmură crem și ornamente fine. Baroc, dar luminos.",
               "Cream marble and fine ornament. Baroque, but luminous."),
        single("baroque-floral", "Baroc Floral", asset: "BaroqueFloral", .elegant,
               "Flori sculptate în jurul monogramei. Grădină de palat.",
               "Flowers carved around the monogram. A palace garden."),

        // Nature
        pair("forest", "Pădure", base: "Forest", .nature,
             "Verde adânc și aur cald. Liniștea unei păduri la răsărit.",
             "Deep green and warm gold. The calm of a forest at dawn."),
        pair("emerald", "Smarald", base: "Emerald", .nature,
             "Verde care strălucește din interior. O piatră prețioasă vie.",
             "Green that glows from within. A living gemstone."),
        pair("sunset", "Apus", base: "Sunset", .nature,
             "Portocaliu de amurg. Căldura ultimei raze a zilei.",
             "Dusk orange. The warmth of the day's last light."),
        single("forest-royal", "Pădure Regală", asset: "ForestRoyal", .nature,
               "Verde smarald și aur regal. Natura, la rang de coroană.",
               "Emerald green and royal gold. Nature, crowned."),
        AppIconTheme(id: "emerald-marble", name: "Smarald Marmură",
            storyRO: "Marmură verde ziua, smarald lustruit sub sticlă noaptea.",
            storyEN: "Green marble by day, polished emerald under glass by night.",
            category: .nature,
            lightPreview: "EmeraldMarble", darkPreview: "EmeraldGloss",
            lightIcon: "AppIconEmeraldMarble", darkIcon: "AppIconEmeraldGloss"),
        single("lavender-royal", "Lavandă Regală", asset: "LavenderRoyal", .nature,
               "Mov profund și aur. Un câmp de lavandă la asfințit.",
               "Deep purple and gold. A lavender field at sundown."),

        // Vibrant
        single("noir", "Noir / Viitor", asset: "Noir", .vibrant,
               "Neon cyan și magenta pe negru. Viitorul, azi.",
               "Cyan and magenta neon on black. The future, today."),
        pair("arctic", "Arctic", base: "Arctic", .vibrant,
             "Albastru de gheață, luminat din spate. Rece și clar.",
             "Ice blue, backlit. Cold and crystal-clear."),
        single("crimson", "Roșu Aprins", asset: "Crimson", .vibrant,
               "Roșu incandescent. Energie pură, imposibil de ignorat.",
               "Incandescent red. Pure energy, impossible to ignore."),
        single("dazzle", "Dazzle", asset: "Dazzle", .vibrant,
               "Neon topit, explozie de culoare. Pentru zilele îndrăznețe.",
               "Melting neon, a burst of colour. For the bold days."),
        single("dazzle-splatter", "Dazzle Splatter", asset: "DazzleSplatter", .vibrant,
               "Stropi de vopsea și neon. Artă stradală în buzunar.",
               "Paint splatter and neon. Street art in your pocket."),
        single("dazzle-cosmic", "Dazzle Cosmic", asset: "DazzleCosmic", .vibrant,
               "Un vârtej de galaxie în jurul casei. Cosmic.",
               "A galaxy swirl around the house. Cosmic."),
        single("dazzle-floral", "Dazzle Floral", asset: "DazzleFloral", .vibrant,
               "Neon și petale. Delicat și electric în același timp.",
               "Neon and petals. Delicate and electric at once."),
        single("neon-magenta", "Neon Magenta", asset: "NeonMagenta", .vibrant,
               "Magenta pur, contur incandescent pe negru.",
               "Pure magenta, glowing outline on black."),
        pair("lavender", "Lavandă", base: "Lavender", .vibrant,
             "Mov catifelat și aur. Regal, dar jucăuș.",
             "Velvet purple and gold. Regal, yet playful."),
        single("retro-vapor", "Retro-Vapor", asset: "RetroVapor", .vibrant,
               "Apus synthwave, palmieri și grilă neon. Anii '80 revin.",
               "A synthwave sunset, palms and neon grid. The '80s are back."),
        single("retro-pixel", "Retro Pixel", asset: "RetroPixel", .vibrant,
               "Peisaj pixel-art, nostalgie de joc retro.",
               "A pixel-art landscape, retro-game nostalgia."),
        single("vapor-pixel", "Vapor Pixel", asset: "VaporPixel", .vibrant,
               "Vaporwave în pixeli. Cyan, magenta, apus digital.",
               "Vaporwave in pixels. Cyan, magenta, a digital sunset."),

        // Minimal
        single("midnight", "Midnight", asset: "Midnight", .minimal,
               "Bleumarin de miezul nopții, argintiu fin. Sobru și elegant.",
               "Midnight navy, fine silver. Sober and elegant."),
        pair("carbon", "Carbon", base: "Carbon", .minimal,
             "Fibră de carbon, textură tehnică. Sport și serios.",
             "Carbon fibre, technical texture. Sporty and serious."),
        pair("minimal", "Minimalist", base: "Minimal", .minimal,
             "Linie curată, esențial. Mai puțin, dar mai bine.",
             "A clean line, the essential. Less, but better."),
        single("minimal-outline", "Contur", asset: "MinimalOutline", .minimal,
               "Doar conturul, nimic în plus. Pură claritate.",
               "Just the outline, nothing more. Pure clarity."),
    ]

    /// Ids of singles that were merged into day/night pairs keep resolving.
    private static let mergedIDs = ["gold-noir": "metallic-gold",
                                    "rose-noir": "rose-mocha",
                                    "emerald-gloss": "emerald-marble"]

    static func theme(id: String) -> AppIconTheme {
        let resolved = mergedIDs[id] ?? id
        return all.first { $0.id == resolved } ?? all[0]
    }

    static func theme(forIconName name: String?) -> AppIconTheme {
        guard let name else { return all[0] }
        return all.first {
            $0.lightIcon == name || $0.darkIcon == name || $0.pairedIcon == name
        } ?? all[0]
    }
}

// MARK: - Icon families (carousel page = family, swatches = its variants)
//
// The picker browses FAMILIES — one hero icon per page — and offers each
// family's related designs as swatch "tints" below, like the system icon
// customizers. Every catalog theme belongs to exactly one family (verified
// by AppIconFamilyTests), so nothing can silently drop out of the gallery.

struct IconFamily: Identifiable, Equatable {
    let id: String
    let variantIDs: [String]
    var variants: [AppIconTheme] { variantIDs.map(AppIconCatalog.theme(id:)) }
}

enum AppIconFamilies {
    static let all: [IconFamily] = [
        IconFamily(id: "default",     variantIDs: ["default"]),
        IconFamily(id: "glass",       variantIDs: ["glass"]),
        IconFamily(id: "classic",     variantIDs: ["classic"]),
        IconFamily(id: "roseGold",    variantIDs: ["roseGold", "rose-mocha"]),
        IconFamily(id: "baroque",     variantIDs: ["baroque", "baroque-cream", "baroque-floral"]),
        IconFamily(id: "metallic",    variantIDs: ["metallic", "metallic-gold"]),
        IconFamily(id: "noir-metals", variantIDs: ["silver-noir"]),
        IconFamily(id: "forest",      variantIDs: ["forest", "forest-royal"]),
        IconFamily(id: "emerald",     variantIDs: ["emerald", "emerald-marble"]),
        IconFamily(id: "sunset",      variantIDs: ["sunset"]),
        IconFamily(id: "lavender",    variantIDs: ["lavender", "lavender-royal"]),
        IconFamily(id: "arctic",      variantIDs: ["arctic"]),
        IconFamily(id: "crimson",     variantIDs: ["crimson"]),
        IconFamily(id: "dazzle",      variantIDs: ["dazzle", "dazzle-splatter", "dazzle-cosmic", "dazzle-floral"]),
        IconFamily(id: "neon",        variantIDs: ["noir", "neon-magenta"]),
        IconFamily(id: "retro",       variantIDs: ["retro-vapor", "retro-pixel", "vapor-pixel"]),
        IconFamily(id: "midnight",    variantIDs: ["midnight"]),
        IconFamily(id: "carbon",      variantIDs: ["carbon"]),
        IconFamily(id: "minimal",     variantIDs: ["minimal", "minimal-outline"]),
    ]

    static func family(containing themeID: String) -> IconFamily {
        all.first { $0.variantIDs.contains(themeID) } ?? all[0]
    }
}

// MARK: - Color scheme watcher (placed as .background() in root view)

struct IconColorSchemeWatcher: View {
    var iconManager: IconManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Color.clear
            .onChange(of: colorScheme) { _, scheme in
                iconManager.colorSchemeChanged(isDark: scheme == .dark)
            }
            .onAppear {
                iconManager.colorSchemeChanged(isDark: colorScheme == .dark)
            }
            .onChange(of: scenePhase) { _, phase in
                // Foreground is the one moment iOS reliably allows icon
                // changes — retry a mood face a too-early launch attempt
                // could not install (no-op when the icon is already right).
                if phase == .active { iconManager.sceneBecameActive() }
            }
    }
}

// MARK: - Icon Manager

/// One face of a paired (day/night) icon theme.
enum IconFace: String {
    case light, dark
}

@MainActor
@Observable
final class IconManager {
    var selected: AppIconTheme

    /// When set, this exact half of a pair stays installed regardless of the
    /// system appearance — the user explicitly chose it. nil = the pair rides
    /// the merged day/night asset and switches automatically.
    var pinnedFace: IconFace? {
        didSet { UserDefaults.standard.set(pinnedFace?.rawValue, forKey: "prvio.pinnedIconFace") }
    }

    @ObservationIgnored @AppStorage("prvio.selectedIconThemeId") private var savedId: String = "default"

    /// Observable (unlike `@AppStorage`, which Observation ignores) so the
    /// picker can react when the toggle flips — e.g. to make pair faces
    /// individually selectable. Persists to the same key as before.
    var autoSwitch: Bool {
        didSet { UserDefaults.standard.set(autoSwitch, forKey: "prvio.autoSwitchIcon") }
    }

    /// "Iconița urmează atmosfera" (Settings → Aspect → Fundal): the icon
    /// installs the selected pair's face for the RESOLVED MOOD — night mood
    /// → dark face, morning/day → light face — instead of riding the merged
    /// asset (which follows the SYSTEM appearance, something the mood does
    /// not control). Default OFF. Flip it through `setFollowsMood(_:)`.
    private(set) var followsMood: Bool {
        didSet { UserDefaults.standard.set(followsMood, forKey: "app.mood.autoIcon") }
    }

    private var lastAppliedName: String? = UIApplication.shared.alternateIconName

    /// A manual pick owns the icon for a beat — any appearance-driven
    /// re-apply landing inside this window is dropped, so the icon can never
    /// visibly flip right after the user chose it.
    @ObservationIgnored private var suppressAutoUntil: Date = .distantPast

    @ObservationIgnored private var moodObserver: NSObjectProtocol?

    init() {
        let id = UserDefaults.standard.string(forKey: "prvio.selectedIconThemeId") ?? "default"
        selected = AppIconCatalog.theme(id: id)
        autoSwitch = (UserDefaults.standard.object(forKey: "prvio.autoSwitchIcon") as? Bool) ?? true
        pinnedFace = UserDefaults.standard.string(forKey: "prvio.pinnedIconFace").flatMap(IconFace.init)
        followsMood = (UserDefaults.standard.object(forKey: "app.mood.autoIcon") as? Bool) ?? false

        // The engine announces every resolved-mood change while the app runs.
        moodObserver = NotificationCenter.default.addObserver(
            forName: .appMoodResolvedChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.moodDidChange() }
        }
        // The mood may have rolled over while the app was closed, and iOS
        // only changes icons with the app foregrounded — catch up now (the
        // engine's launch resolution is already current, so no notification
        // will fire for it).
        if followsMood {
            Task { @MainActor [weak self] in self?.moodDidChange() }
        }
    }

    deinit {
        if let moodObserver { NotificationCenter.default.removeObserver(moodObserver) }
    }

    var supportsAlternateIcons: Bool { UIApplication.shared.supportsAlternateIcons }

    /// The exact alternate-icon name currently installed (nil = primary).
    /// Lets the picker mark the precise pair face that is applied.
    var appliedIconName: String? { lastAppliedName }

    /// True when the mood-following option can actually do something: the
    /// selected theme must be a pair with installable alternate faces (the
    /// default primary icon has none — iOS already day/night-switches it
    /// with the SYSTEM appearance, which the mood does not drive).
    var canFollowMood: Bool {
        selected.hasPair && !selected.isDefault && supportsAlternateIcons
    }

    /// The resolved mood's darkness — the one signal `followsMood` rides.
    private var moodIsDark: Bool {
        AppMoodEngine.shared.resolved.palette.colorScheme == .dark
    }

    /// The asset to install for a theme: an explicitly pinned face wins;
    /// then a mood-following pair installs the exact face for the resolved
    /// mood; otherwise pair themes with auto-switch ride the merged
    /// day/night asset (iOS adapts it silently with the system appearance);
    /// auto-switch off falls back to the face matching the current
    /// appearance.
    private func resolvedName(for theme: AppIconTheme, isDark: Bool) -> String? {
        if theme.hasPair {
            if let face = pinnedFace { return theme.iconName(isDark: face == .dark) }
            if followsMood, !theme.isDefault { return theme.iconName(isDark: moodIsDark) }
            if autoSwitch, let paired = theme.pairedIcon { return paired }
        }
        return theme.iconName(isDark: isDark)
    }

    /// What `apply` would install right now — lets the picker decide whether
    /// the shown configuration is already the active one.
    func expectedName(for theme: AppIconTheme, isDark: Bool) -> String? {
        resolvedName(for: theme, isDark: isDark)
    }

    func apply(_ theme: AppIconTheme, isDark: Bool, force: Bool = false) {
        let name = resolvedName(for: theme, isDark: isDark)
        guard force || name != lastAppliedName else { return }
        // Commit state synchronously, *before* the async system call. It used
        // to be committed inside the completion, so anything reading
        // `selected`/`lastAppliedName` right after Apply — the colour-scheme
        // watcher, the Apply bar, an immediate second tap — still saw the
        // previous theme and could re-install the old icon.
        lastAppliedName = name
        selected = theme
        savedId = theme.id
        UIApplication.shared.setAlternateIconName(name) { [weak self] error in
            guard error != nil else { return }
            // The system rejected the change — roll back to what is actually
            // installed, unless a newer apply already superseded this one.
            Task { @MainActor [weak self] in
                guard let self, self.lastAppliedName == name else { return }
                let actual = UIApplication.shared.alternateIconName
                self.lastAppliedName = actual
                self.selected = AppIconCatalog.theme(forIconName: actual)
                self.savedId = self.selected.id
            }
        }
    }

    /// `pinFace` non-nil installs exactly that half of a pair and keeps it
    /// through appearance changes; nil restores automatic day/night.
    ///
    /// Honest interplay with "Iconița urmează atmosfera": pinning a face is
    /// a direct contradiction of the mood driving the face, so the manual
    /// choice wins and the option turns itself off (its caption on the
    /// Fundal page says so). Picking a new THEME keeps the option on — the
    /// mood then drives the new design's day/night faces.
    func select(_ theme: AppIconTheme, isDark: Bool, pinFace: IconFace? = nil) {
        pinnedFace = theme.hasPair ? pinFace : nil
        if pinFace != nil { followsMood = false }
        suppressAutoUntil = Date().addingTimeInterval(2.5)
        apply(theme, isDark: isDark, force: true)
    }

    // MARK: Mood-following icon

    /// The Fundal page's toggle. Turning it on releases any pinned face
    /// (the pin would contradict the mood) and immediately installs the
    /// resolved mood's face; turning it off restores the standard behavior
    /// (paired themes ride the merged day/night asset with the system).
    func setFollowsMood(_ on: Bool) {
        guard on != followsMood else { return }
        followsMood = on
        if on { pinnedFace = nil }
        guard canFollowMood else { return }
        apply(selected, isDark: moodIsDark)
    }

    /// Resolved mood changed (engine notification / launch catch-up):
    /// install the matching face. `apply` no-ops when the right face is
    /// already installed, so morning→day never touches the system.
    private func moodDidChange() {
        guard followsMood, canFollowMood else { return }
        apply(selected, isDark: moodIsDark)
    }

    /// Scene became active: retry the mood face in case the launch-time
    /// attempt ran before iOS considered the app foregrounded (a failed
    /// apply rolls `lastAppliedName` back, so this retry is never a no-op
    /// masked by stale state — and a clean state makes it free).
    func sceneBecameActive() {
        guard followsMood, canFollowMood else { return }
        apply(selected, isDark: moodIsDark)
    }

    /// Appearance changes no longer install anything — the merged pair asset
    /// carries both variants and iOS switches them itself, silently. The one
    /// job left is migrating users still on a legacy per-face name (installed
    /// before the merge) onto the merged asset, once. A mood-following icon
    /// deliberately KEEPS its per-face name, so the migration skips it.
    func colorSchemeChanged(isDark: Bool) {
        guard pinnedFace == nil, !followsMood,
              autoSwitch, selected.hasPair, let paired = selected.pairedIcon,
              lastAppliedName != nil, lastAppliedName != paired,
              AppIconCatalog.theme(forIconName: lastAppliedName).id == selected.id else { return }
        guard Date() >= suppressAutoUntil else { return }
        apply(selected, isDark: isDark)
    }
}
