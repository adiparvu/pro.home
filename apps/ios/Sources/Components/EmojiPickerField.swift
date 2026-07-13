import SwiftUI

// MARK: - EmojiPickerField
//
// The app's one emoji picker for forms. A compact favorites strip by default
// (the shape both plant forms already had), plus a search field and a "show
// all" affordance that opens the full nature catalog in titled sections.
//
// Search matches Romanian AND English keywords at once, regardless of the
// app language — a Romanian user who knows a plant by its English name (or
// vice versa) still finds it, and the folded comparison makes "lavanda"
// find "lavandă". Selection is a plain emoji String, so adopting the field
// never changes what a form saves.

// MARK: Catalog data

/// One pickable emoji plus its RO + EN search keywords.
///
/// LOCALIZATION EXCEPTION (deliberate): these keywords are search-matching
/// data, never displayed copy, so they live here as Swift data instead of
/// Localizable.xcstrings. Both languages are searched at the same time by
/// design; routing them through the catalog would force a per-language
/// lookup and break cross-language search. Section titles, the placeholder,
/// and the empty hint ARE displayed copy and stay in the catalog
/// (`plantemoji_` keys).
struct EmojiPickerEntry: Identifiable {
    let emoji: String
    let roKeywords: [String]
    let enKeywords: [String]

    /// Pre-folded haystack (case- and diacritic-insensitive), built once so
    /// live typing only does cheap `contains` work per entry.
    let foldedKeywords: String

    var id: String { emoji }

    init(_ emoji: String, ro: [String], en: [String]) {
        self.emoji = emoji
        self.roKeywords = ro
        self.enKeywords = en
        self.foldedKeywords = (ro + en)
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    func matches(foldedQuery: String) -> Bool {
        foldedKeywords.contains(foldedQuery) || emoji == foldedQuery
    }
}

/// A titled group of catalog entries. `titleKey` is a Localizable.xcstrings
/// key (displayed copy — RO + EN live in the catalog).
struct EmojiPickerSection: Identifiable {
    let titleKey: String
    let entries: [EmojiPickerEntry]

    var id: String { titleKey }
}

/// The curated nature catalog: plants, flowers, trees, fruits, vegetables &
/// herbs, and garden life. Every emoji here renders on the app's minimum OS
/// (iOS 17.1) — the newest are Unicode 15.0, shipped with iOS 16.4. Unicode
/// 15.1+ glyphs (🍄‍🟫, 🍋‍🟩 — iOS 17.4; 🪾 — iOS 18.4) are deliberately
/// excluded: on 17.1 they'd render as broken tofu/split glyphs.
enum EmojiPickerCatalog {

    static let sections: [EmojiPickerSection] = [
        EmojiPickerSection(titleKey: "plantemoji_sec_plants", entries: [
            EmojiPickerEntry("🌱", ro: ["răsad", "puiet", "germinare", "plantă tânără"],
                             en: ["seedling", "sprout", "young plant"]),
            EmojiPickerEntry("🌿", ro: ["iarbă", "verdeață", "mentă", "busuioc", "plantă aromatică"],
                             en: ["herb", "greenery", "mint", "basil"]),
            EmojiPickerEntry("☘️", ro: ["trifoi"],
                             en: ["shamrock", "clover"]),
            EmojiPickerEntry("🍀", ro: ["trifoi cu patru foi", "noroc"],
                             en: ["four-leaf clover", "luck", "lucky"]),
            EmojiPickerEntry("🪴", ro: ["ghiveci", "plantă de apartament", "plantă în ghiveci"],
                             en: ["potted plant", "houseplant"]),
            EmojiPickerEntry("🎋", ro: ["bambus", "dorințe"],
                             en: ["bamboo", "tanabata", "wish tree"]),
            EmojiPickerEntry("🎍", ro: ["bambus decorativ", "kadomatsu"],
                             en: ["pine decoration", "bamboo", "kadomatsu"]),
            EmojiPickerEntry("🌾", ro: ["grâu", "orez", "spic", "cereale"],
                             en: ["wheat", "rice", "sheaf", "grain"]),
            EmojiPickerEntry("🍃", ro: ["frunze", "frunză în vânt", "briză"],
                             en: ["leaf", "leaves", "wind", "breeze"]),
            EmojiPickerEntry("🍂", ro: ["frunze căzute", "toamnă"],
                             en: ["fallen leaves", "autumn", "fall"]),
            EmojiPickerEntry("🍁", ro: ["arțar", "frunză de arțar", "toamnă"],
                             en: ["maple", "maple leaf"]),
            EmojiPickerEntry("🌵", ro: ["cactus", "suculentă", "deșert"],
                             en: ["cactus", "succulent", "desert"]),
            EmojiPickerEntry("🍄", ro: ["ciupercă", "ciuperci"],
                             en: ["mushroom", "toadstool", "fungus"]),
        ]),
        EmojiPickerSection(titleKey: "plantemoji_sec_flowers", entries: [
            EmojiPickerEntry("🌸", ro: ["floare de cireș", "cireș japonez", "sakura"],
                             en: ["cherry blossom", "sakura"]),
            EmojiPickerEntry("💮", ro: ["floare albă"],
                             en: ["white flower"]),
            EmojiPickerEntry("🏵️", ro: ["rozetă", "crizantemă"],
                             en: ["rosette", "chrysanthemum"]),
            EmojiPickerEntry("🌹", ro: ["trandafir"],
                             en: ["rose"]),
            EmojiPickerEntry("🥀", ro: ["floare ofilită", "trandafir ofilit"],
                             en: ["wilted flower", "dried flower"]),
            EmojiPickerEntry("🌺", ro: ["hibiscus"],
                             en: ["hibiscus"]),
            EmojiPickerEntry("🌻", ro: ["floarea-soarelui", "floarea soarelui"],
                             en: ["sunflower"]),
            EmojiPickerEntry("🌼", ro: ["floare", "margaretă", "mușețel"],
                             en: ["blossom", "daisy", "chamomile"]),
            EmojiPickerEntry("🌷", ro: ["lalea", "lalele"],
                             en: ["tulip"]),
            EmojiPickerEntry("🪻", ro: ["lavandă", "lavanda", "zambilă", "lupin"],
                             en: ["hyacinth", "lavender", "lupine", "bluebonnet"]),
            EmojiPickerEntry("🪷", ro: ["lotus", "nufăr"],
                             en: ["lotus", "water lily"]),
            EmojiPickerEntry("💐", ro: ["buchet", "flori"],
                             en: ["bouquet", "flowers"]),
        ]),
        EmojiPickerSection(titleKey: "plantemoji_sec_trees", entries: [
            EmojiPickerEntry("🌲", ro: ["brad", "molid", "pin", "conifer"],
                             en: ["evergreen", "pine", "fir", "spruce", "conifer"]),
            EmojiPickerEntry("🌳", ro: ["copac", "pom", "stejar", "foios"],
                             en: ["tree", "deciduous", "oak"]),
            EmojiPickerEntry("🌴", ro: ["palmier"],
                             en: ["palm", "palm tree"]),
            EmojiPickerEntry("🎄", ro: ["brad de Crăciun", "pom de Crăciun"],
                             en: ["christmas tree"]),
        ]),
        EmojiPickerSection(titleKey: "plantemoji_sec_fruits", entries: [
            EmojiPickerEntry("🍇", ro: ["struguri", "viță-de-vie", "vie"],
                             en: ["grapes", "vine", "vineyard"]),
            EmojiPickerEntry("🍈", ro: ["pepene galben", "cantalup"],
                             en: ["melon", "cantaloupe"]),
            EmojiPickerEntry("🍉", ro: ["pepene roșu", "pepene verde", "lubeniță"],
                             en: ["watermelon"]),
            EmojiPickerEntry("🍊", ro: ["portocală", "mandarină", "citrice"],
                             en: ["orange", "tangerine", "mandarin", "citrus"]),
            EmojiPickerEntry("🍋", ro: ["lămâie", "lămâi"],
                             en: ["lemon"]),
            EmojiPickerEntry("🍌", ro: ["banană", "bananier"],
                             en: ["banana"]),
            EmojiPickerEntry("🍍", ro: ["ananas"],
                             en: ["pineapple"]),
            EmojiPickerEntry("🥭", ro: ["mango"],
                             en: ["mango"]),
            EmojiPickerEntry("🍎", ro: ["măr", "măr roșu"],
                             en: ["apple", "red apple"]),
            EmojiPickerEntry("🍏", ro: ["măr verde"],
                             en: ["green apple"]),
            EmojiPickerEntry("🍐", ro: ["pară", "păr"],
                             en: ["pear"]),
            EmojiPickerEntry("🍑", ro: ["piersică", "piersic"],
                             en: ["peach"]),
            EmojiPickerEntry("🍒", ro: ["cireșe", "vișine", "cireș"],
                             en: ["cherry", "cherries"]),
            EmojiPickerEntry("🍓", ro: ["căpșună", "căpșuni", "frag"],
                             en: ["strawberry"]),
            EmojiPickerEntry("🫐", ro: ["afine", "afin"],
                             en: ["blueberry", "blueberries"]),
            EmojiPickerEntry("🥝", ro: ["kiwi"],
                             en: ["kiwi"]),
            EmojiPickerEntry("🥥", ro: ["nucă de cocos", "cocotier"],
                             en: ["coconut"]),
            EmojiPickerEntry("🫒", ro: ["măslină", "măslin"],
                             en: ["olive", "olive tree"]),
            EmojiPickerEntry("🥑", ro: ["avocado"],
                             en: ["avocado"]),
        ]),
        EmojiPickerSection(titleKey: "plantemoji_sec_veg", entries: [
            EmojiPickerEntry("🍅", ro: ["roșie", "tomată"],
                             en: ["tomato"]),
            EmojiPickerEntry("🥕", ro: ["morcov"],
                             en: ["carrot"]),
            EmojiPickerEntry("🌶️", ro: ["ardei iute", "chili"],
                             en: ["hot pepper", "chili"]),
            EmojiPickerEntry("🫑", ro: ["ardei gras", "gogoșar"],
                             en: ["bell pepper", "paprika"]),
            EmojiPickerEntry("🥬", ro: ["salată", "varză", "spanac", "verdeață"],
                             en: ["lettuce", "leafy green", "cabbage", "spinach", "kale"]),
            EmojiPickerEntry("🥦", ro: ["broccoli"],
                             en: ["broccoli"]),
            EmojiPickerEntry("🧄", ro: ["usturoi"],
                             en: ["garlic"]),
            EmojiPickerEntry("🧅", ro: ["ceapă"],
                             en: ["onion"]),
            EmojiPickerEntry("🥔", ro: ["cartof", "cartofi"],
                             en: ["potato"]),
            EmojiPickerEntry("🍠", ro: ["cartof dulce", "batat"],
                             en: ["sweet potato", "yam"]),
            EmojiPickerEntry("🍆", ro: ["vânătă", "vinete"],
                             en: ["eggplant", "aubergine"]),
            EmojiPickerEntry("🌽", ro: ["porumb"],
                             en: ["corn", "maize"]),
            EmojiPickerEntry("🥒", ro: ["castravete", "castraveți"],
                             en: ["cucumber"]),
            EmojiPickerEntry("🫛", ro: ["mazăre", "păstaie"],
                             en: ["pea pod", "peas"]),
            EmojiPickerEntry("🫘", ro: ["fasole", "boabe"],
                             en: ["beans", "legume"]),
            EmojiPickerEntry("🥜", ro: ["arahide", "alune"],
                             en: ["peanut", "nuts"]),
            EmojiPickerEntry("🌰", ro: ["castană", "castan"],
                             en: ["chestnut"]),
            EmojiPickerEntry("🫚", ro: ["ghimbir"],
                             en: ["ginger", "ginger root"]),
        ]),
        EmojiPickerSection(titleKey: "plantemoji_sec_garden", entries: [
            EmojiPickerEntry("🐝", ro: ["albină", "polenizare"],
                             en: ["bee", "honeybee", "pollinator"]),
            EmojiPickerEntry("🦋", ro: ["fluture"],
                             en: ["butterfly"]),
            EmojiPickerEntry("🐛", ro: ["omidă", "insectă"],
                             en: ["caterpillar", "bug"]),
            EmojiPickerEntry("🐌", ro: ["melc"],
                             en: ["snail"]),
            EmojiPickerEntry("🪱", ro: ["râmă", "vierme"],
                             en: ["worm", "earthworm"]),
            EmojiPickerEntry("🪲", ro: ["gândac", "cărăbuș"],
                             en: ["beetle"]),
            EmojiPickerEntry("🐞", ro: ["buburuză", "gărgăriță"],
                             en: ["ladybug", "ladybird"]),
            EmojiPickerEntry("🌊", ro: ["apă", "val", "acvatic"],
                             en: ["water", "wave", "aquatic"]),
            EmojiPickerEntry("🪸", ro: ["coral"],
                             en: ["coral"]),
            EmojiPickerEntry("🪨", ro: ["piatră", "rocă", "pietriș"],
                             en: ["rock", "stone"]),
            EmojiPickerEntry("🪵", ro: ["lemn", "buștean"],
                             en: ["wood", "log", "timber"]),
        ]),
    ]

    /// Sections filtered to entries matching the query; empty sections drop
    /// out. An empty/whitespace query returns everything.
    static func filtered(by query: String) -> [EmojiPickerSection] {
        let folded = query
            .trimmingCharacters(in: .whitespaces)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        guard !folded.isEmpty else { return sections }
        return sections.compactMap { section in
            let hits = section.entries.filter { $0.matches(foldedQuery: folded) }
            return hits.isEmpty
                ? nil
                : EmojiPickerSection(titleKey: section.titleKey, entries: hits)
        }
    }
}

// MARK: - Field view

/// Reusable emoji field for add/edit forms. Binds a plain emoji `String`,
/// so a form's saved-value shape never changes when it adopts this.
///
/// Default state keeps the compact favorites strip; searching or "Toate"
/// opens the full sectioned catalog. The search field never grabs focus on
/// its own, so it can't fight a form's Name field.
struct EmojiPickerField: View {
    @Binding var selection: String
    /// The compact strip shown before searching/expanding (e.g. a feature's
    /// historical curated set). A selection outside it — a species-catalog
    /// pick, or one made from search — is surfaced as its first tile
    /// instead of being lost.
    var favorites: [String]
    var labelKey: LocalizedStringKey = "EMOJI"

    @State private var query = ""
    @State private var isExpanded = false
    @FocusState private var searchFocused: Bool

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var stripEmojis: [String] {
        favorites.contains(selection) ? favorites : [selection] + favorites
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            searchField

            if isSearching {
                let results = EmojiPickerCatalog.filtered(by: query)
                if results.isEmpty {
                    emptyHint
                } else {
                    sectionedGrid(results)
                }
            } else if isExpanded {
                sectionedGrid(EmojiPickerCatalog.sections)
            } else {
                favoritesStrip
            }
        }
        .animation(.smooth(duration: 0.25), value: isExpanded)
        .animation(.smooth(duration: 0.2), value: isSearching)
    }

    // MARK: Header (label + expand toggle)

    private var header: some View {
        HStack {
            Text(labelKey)
                .font(AppFont.label)
                .foregroundStyle(.secondary)
            Spacer()
            if !isSearching {
                Button {
                    HapticFeedback.impact(.light)
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Text(isExpanded
                             ? LocalizedStringKey("plantemoji_show_less")
                             : LocalizedStringKey("plantemoji_show_all"))
                            .font(AppFont.captionStrong)
                        Image(systemName: "chevron.down")
                            .font(AppFont.caption2)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .foregroundStyle(Color.accentColor)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Search field

    private var searchField: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(AppFont.scaled(14))
                .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
            TextField("plantemoji_search_placeholder", text: $query)
                .font(AppFont.scaled(15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .focused($searchFocused)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppFont.scaled(15))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, 10)
        .background(
            Color.subtleFill,
            in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
        )
    }

    // MARK: Favorites strip (the compact default)

    private var favoritesStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(stripEmojis, id: \.self) { emoji in
                    tile(emoji)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    // MARK: Full catalog grid

    private func sectionedGrid(_ sections: [EmojiPickerSection]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text(LocalizedStringKey(section.titleKey))
                        .font(AppFont.label)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                        .textCase(.uppercase)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 52), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(section.entries) { entry in
                            tile(entry.emoji)
                        }
                    }
                }
            }
        }
    }

    // MARK: Empty search state

    private var emptyHint: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(AppFont.footnote)
                .foregroundStyle(.secondary)
            Text("plantemoji_no_results")
                .font(AppFont.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AppSpacing.md)
    }

    // MARK: Tile (the shape both plant forms already used)

    private func tile(_ emoji: String) -> some View {
        Button {
            selection = emoji
            HapticFeedback.selection()
        } label: {
            Text(emoji)
                .font(AppFont.scaled(30))
                .frame(width: 52, height: 52)
                .background(
                    selection == emoji
                        ? Color.accentColor.opacity(0.15)
                        : Color.hairline,
                    in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .strokeBorder(
                            selection == emoji ? Color.accentColor : Color.clear,
                            lineWidth: 2
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: emoji))
        .accessibilityAddTraits(selection == emoji ? [.isSelected] : [])
    }
}
