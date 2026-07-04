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
    static var appIsRomanian: Bool {
        (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("ro")
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
        single("gold-noir", "Aur Nocturn", asset: "GoldNoir", .elegant,
               "Aur masiv pe negru profund. Sobru, scump, memorabil.",
               "Solid gold on deep black. Sober, expensive, unforgettable."),
        single("metallic-gold", "Aur Lichid", asset: "MetallicGold", .elegant,
               "Aur topit sub sticlă. Lumina alunecă pe fiecare curbă.",
               "Molten gold under glass. Light glides across every curve."),
        single("rose-mocha", "Rose Mocha", asset: "RoseMocha", .elegant,
               "Roz-cafeniu, cald ca o cafea de seară.",
               "Rosy mocha, warm as an evening coffee."),
        single("rose-noir", "Rose Noir", asset: "RoseNoir", .elegant,
               "Cupru trandafiriu pe noapte adâncă. Contrast dramatic.",
               "Rose copper on deep night. Dramatic contrast."),
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
        single("emerald-gloss", "Smarald Lucios", asset: "EmeraldGloss", .nature,
               "Smarald sub un strat de sticlă. Verde profund, lustruit.",
               "Emerald under a coat of glass. Deep green, polished."),
        single("emerald-marble", "Smarald Marmură", asset: "EmeraldMarble", .nature,
               "Marmură verde cu vinișoare de lumină. Solid și scump.",
               "Green marble veined with light. Solid and rich."),
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

    static func theme(id: String) -> AppIconTheme { all.first { $0.id == id } ?? all[0] }

    static func theme(forIconName name: String?) -> AppIconTheme {
        guard let name else { return all[0] }
        return all.first { $0.lightIcon == name || $0.darkIcon == name } ?? all[0]
    }
}

// MARK: - Color scheme watcher (placed as .background() in root view)

struct IconColorSchemeWatcher: View {
    var iconManager: IconManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color.clear
            .onChange(of: colorScheme) { _, scheme in
                iconManager.colorSchemeChanged(isDark: scheme == .dark)
            }
            .onAppear {
                iconManager.colorSchemeChanged(isDark: colorScheme == .dark)
            }
    }
}

// MARK: - Icon Manager

@MainActor
@Observable
final class IconManager {
    var selected: AppIconTheme

    @ObservationIgnored @AppStorage("prvio.selectedIconThemeId") private var savedId: String = "default"
    @ObservationIgnored @AppStorage("prvio.autoSwitchIcon") var autoSwitch: Bool = true

    private var lastAppliedName: String? = UIApplication.shared.alternateIconName

    init() {
        let id = UserDefaults.standard.string(forKey: "prvio.selectedIconThemeId") ?? "default"
        selected = AppIconCatalog.theme(id: id)
    }

    var supportsAlternateIcons: Bool { UIApplication.shared.supportsAlternateIcons }

    func apply(_ theme: AppIconTheme, isDark: Bool, force: Bool = false) {
        let name = theme.iconName(isDark: isDark)
        guard force || name != lastAppliedName else { return }
        UIApplication.shared.setAlternateIconName(name) { [weak self] error in
            guard error == nil else { return }
            Task { @MainActor [weak self] in
                self?.lastAppliedName = name
                self?.selected = theme
                self?.savedId = theme.id
            }
        }
    }

    func select(_ theme: AppIconTheme, isDark: Bool) {
        apply(theme, isDark: isDark, force: true)
    }

    func colorSchemeChanged(isDark: Bool) {
        guard autoSwitch, selected.hasPair else { return }
        apply(selected, isDark: isDark)
    }
}
