import SwiftUI

// MARK: - Built-in plant species catalog
//
// A curated horticultural database — houseplants, succulents, garden
// flowers, shrubs, conifers, fruit and ornamental trees, herbs — with
// bilingual common names, Latin binomials, a sensible default watering
// interval for a home context, and light needs. Picking an entry prefills
// the Add Plant form (name, species, emoji, watering interval); every
// field stays editable afterwards. The catalog never touches persistence.

struct PlantSpecies: Identifiable, Equatable {
    enum LightNeed {
        case low, medium, bright, fullSun

        /// Localization key for the light requirement label.
        var titleKey: String {
            switch self {
            case .low:     return "plant_light_low"
            case .medium:  return "plant_light_medium"
            case .bright:  return "plant_light_bright"
            case .fullSun: return "plant_light_full_sun"
            }
        }

        /// SF Symbol communicating the light requirement at a glance.
        var symbol: String {
            switch self {
            case .low:     return "sun.min"
            case .medium:  return "cloud.sun"
            case .bright:  return "sun.max"
            case .fullSun: return "sun.max.fill"
            }
        }
    }

    let id: String
    let nameEN: String
    let nameRO: String
    let latin: String
    let emoji: String
    let wateringDays: Int
    let light: LightNeed

    var name: String { Locale.appIsRomanian ? nameRO : nameEN }
}

struct PlantSpeciesFamily: Identifiable {
    let id: String        // localization key for the section title
    let species: [PlantSpecies]
}

enum PlantSpeciesCatalog {

    private static func s(_ id: String, _ en: String, _ ro: String, _ latin: String,
                          _ emoji: String, _ days: Int, _ light: PlantSpecies.LightNeed) -> PlantSpecies {
        PlantSpecies(id: id, nameEN: en, nameRO: ro, latin: latin,
                     emoji: emoji, wateringDays: days, light: light)
    }

    static let families: [PlantSpeciesFamily] = [
        PlantSpeciesFamily(id: "plant_family_houseplants", species: [
            s("monstera",       "Swiss cheese plant", "Monstera",           "Monstera deliciosa",      "🌿", 7,  .bright),
            s("ficus-lyrata",   "Fiddle-leaf fig",    "Ficus lyrata",       "Ficus lyrata",            "🪴", 7,  .bright),
            s("ficus-elastica", "Rubber plant",       "Ficus elastica",     "Ficus elastica",          "🪴", 8,  .bright),
            s("sansevieria",    "Snake plant",        "Limba soacrei",      "Sansevieria trifasciata", "🌱", 14, .low),
            s("zamioculcas",    "ZZ plant",           "Zamioculcas",        "Zamioculcas zamiifolia",  "🌿", 14, .low),
            s("pothos",         "Pothos",             "Pothos",             "Epipremnum aureum",       "🍃", 7,  .medium),
            s("philodendron",   "Heartleaf philodendron", "Filodendron",    "Philodendron hederaceum", "🍃", 7,  .medium),
            s("spathiphyllum",  "Peace lily",         "Crinul păcii",       "Spathiphyllum wallisii",  "🌸", 5,  .low),
            s("dracaena",       "Dragon tree",        "Dracena",            "Dracaena marginata",      "🌴", 10, .medium),
            s("chlorophytum",   "Spider plant",       "Planta păianjen",    "Chlorophytum comosum",    "🌱", 7,  .medium),
            s("calathea",       "Calathea",           "Calathea",           "Calathea orbifolia",      "🍃", 5,  .medium),
            s("anthurium",      "Flamingo flower",    "Anthurium",          "Anthurium andraeanum",    "🌺", 6,  .bright),
            s("areca",          "Areca palm",         "Palmier Areca",      "Dypsis lutescens",        "🌴", 6,  .bright),
            s("kentia",         "Kentia palm",        "Palmier Kentia",     "Howea forsteriana",       "🌴", 8,  .medium),
            s("yucca",          "Yucca",              "Yucca",              "Yucca elephantipes",      "🪴", 12, .bright),
            s("schefflera",     "Umbrella plant",     "Schefflera",         "Schefflera arboricola",   "🌿", 8,  .medium),
            s("begonia",        "Begonia",            "Begonie",            "Begonia rex",             "🌸", 5,  .medium),
            s("peperomia",      "Baby rubber plant",  "Peperomia",          "Peperomia obtusifolia",   "🪴", 9,  .medium),
            s("syngonium",      "Arrowhead plant",    "Singonium",          "Syngonium podophyllum",   "🍃", 6,  .medium),
            s("tradescantia",   "Inch plant",         "Telegraf",           "Tradescantia zebrina",    "🌿", 5,  .bright),
        ]),
        PlantSpeciesFamily(id: "plant_family_succulents", species: [
            s("aloe",       "Aloe vera",         "Aloe vera",        "Aloe vera",               "🌵", 18, .bright),
            s("echeveria",  "Echeveria",         "Echeveria",        "Echeveria elegans",       "🌵", 14, .fullSun),
            s("haworthia",  "Zebra haworthia",   "Haworthia",        "Haworthiopsis fasciata",  "🌵", 16, .bright),
            s("crassula",   "Jade plant",        "Arborele de jad",  "Crassula ovata",          "🪴", 14, .bright),
            s("kalanchoe",  "Kalanchoe",         "Kalanchoe",        "Kalanchoe blossfeldiana", "🌸", 10, .bright),
            s("opuntia",    "Prickly pear",      "Opuntia",          "Opuntia ficus-indica",    "🌵", 21, .fullSun),
            s("euphorbia",  "African milk tree", "Euphorbia",        "Euphorbia trigona",       "🌵", 14, .bright),
            s("sedum",      "Burro's tail",      "Coada măgarului",  "Sedum morganianum",       "🌵", 14, .fullSun),
        ]),
        PlantSpeciesFamily(id: "plant_family_flowers", species: [
            s("rose",          "Rose",          "Trandafir",  "Rosa",                      "🌹", 3, .fullSun),
            s("lavender",      "Lavender",      "Lavandă",    "Lavandula angustifolia",    "🪻", 7, .fullSun),
            s("peony",         "Peony",         "Bujor",      "Paeonia lactiflora",        "🌸", 4, .fullSun),
            s("hydrangea",     "Hydrangea",     "Hortensie",  "Hydrangea macrophylla",     "🌸", 3, .medium),
            s("petunia",       "Petunia",       "Petunie",    "Petunia ×hybrida",          "🌺", 2, .fullSun),
            s("geranium",      "Geranium",      "Mușcată",    "Pelargonium zonale",        "🌺", 3, .fullSun),
            s("chrysanthemum", "Chrysanthemum", "Crizantemă", "Chrysanthemum ×morifolium", "🌼", 3, .fullSun),
            s("tulip",         "Tulip",         "Lalea",      "Tulipa gesneriana",         "🌷", 5, .fullSun),
            s("daffodil",      "Daffodil",      "Narcisă",    "Narcissus pseudonarcissus", "🌼", 5, .fullSun),
            s("dahlia",        "Dahlia",        "Dalie",      "Dahlia pinnata",            "🌺", 3, .fullSun),
            s("gladiolus",     "Gladiolus",     "Gladiolă",   "Gladiolus ×hortulanus",     "🌸", 4, .fullSun),
            s("lily",          "Lily",          "Crin",       "Lilium candidum",           "🌷", 4, .fullSun),
        ]),
        PlantSpeciesFamily(id: "plant_family_shrubs", species: [
            s("buxus",       "Boxwood",           "Buxus",          "Buxus sempervirens",           "🌿", 7,  .medium),
            s("photinia",    "Red Robin photinia", "Photinia",      "Photinia ×fraseri 'Red Robin'", "🌳", 7,  .fullSun),
            s("forsythia",   "Forsythia",         "Forsiție",       "Forsythia ×intermedia",        "🌼", 7,  .fullSun),
            s("lilac",       "Lilac",             "Liliac",         "Syringa vulgaris",             "🪻", 7,  .fullSun),
            s("weigela",     "Weigela",           "Weigela",        "Weigela florida",              "🌸", 7,  .fullSun),
            s("spiraea",     "Japanese spirea",   "Spiree",         "Spiraea japonica",             "🌸", 7,  .fullSun),
            s("cornus",      "Red-twig dogwood",  "Sânger",         "Cornus alba",                  "🌳", 7,  .medium),
            s("ligustrum",   "Privet",            "Lemn câinesc",   "Ligustrum vulgare",            "🌿", 7,  .medium),
            s("hibiscus",    "Rose of Sharon",    "Hibiscus de grădină", "Hibiscus syriacus",       "🌺", 5,  .fullSun),
            s("laurel",      "Cherry laurel",     "Laur englezesc", "Prunus laurocerasus",          "🌿", 7,  .medium),
            s("berberis",    "Barberry",          "Dracilă",        "Berberis thunbergii",          "🌳", 10, .fullSun),
            s("cotoneaster", "Cotoneaster",       "Bârcoace",       "Cotoneaster horizontalis",     "🌿", 10, .fullSun),
        ]),
        PlantSpeciesFamily(id: "plant_family_conifers", species: [
            s("thuja",        "Emerald thuja",       "Tuia Smarald",           "Thuja occidentalis 'Smaragd'",  "🌲", 7,  .fullSun),
            s("leyland",      "Leyland cypress",     "Chiparos Leyland",       "×Cupressocyparis leylandii",    "🌲", 7,  .fullSun),
            s("juniperus",    "Common juniper",      "Ienupăr",                "Juniperus communis",            "🌲", 14, .fullSun),
            s("picea-abies",  "Norway spruce",       "Molid",                  "Picea abies",                   "🌲", 14, .fullSun),
            s("picea-pungens","Blue spruce",         "Molid argintiu",         "Picea pungens 'Glauca'",        "🌲", 14, .fullSun),
            s("pinus-mugo",   "Dwarf mountain pine", "Pin pitic de munte",     "Pinus mugo",                    "🌲", 14, .fullSun),
            s("abies",        "Silver fir",          "Brad",                   "Abies alba",                    "🌲", 14, .medium),
            s("taxus",        "Yew",                 "Tisă",                   "Taxus baccata",                 "🌲", 10, .medium),
            s("chamaecyparis","Lawson cypress",      "Chiparos de California", "Chamaecyparis lawsoniana",      "🌲", 7,  .fullSun),
            s("cryptomeria",  "Japanese cedar",      "Criptomeria",            "Cryptomeria japonica",          "🌲", 7,  .medium),
        ]),
        PlantSpeciesFamily(id: "plant_family_trees", species: [
            s("apple",    "Apple tree",   "Măr",       "Malus domestica",      "🍎", 7,  .fullSun),
            s("pear",     "Pear tree",    "Păr",       "Pyrus communis",       "🍐", 7,  .fullSun),
            s("plum",     "Plum tree",    "Prun",      "Prunus domestica",     "🌳", 7,  .fullSun),
            s("cherry",   "Sweet cherry", "Cireș",     "Prunus avium",         "🍒", 7,  .fullSun),
            s("apricot",  "Apricot tree", "Cais",      "Prunus armeniaca",     "🌳", 7,  .fullSun),
            s("peach",    "Peach tree",   "Piersic",   "Prunus persica",       "🍑", 7,  .fullSun),
            s("walnut",   "Walnut tree",  "Nuc",       "Juglans regia",        "🌰", 14, .fullSun),
            s("birch",    "Silver birch", "Mesteacăn", "Betula pendula",       "🌳", 10, .fullSun),
            s("maple",    "Norway maple", "Arțar",     "Acer platanoides",     "🍁", 10, .fullSun),
            s("magnolia", "Magnolia",     "Magnolie",  "Magnolia ×soulangeana", "🌸", 7, .fullSun),
        ]),
        PlantSpeciesFamily(id: "plant_family_herbs", species: [
            s("basil",      "Basil",      "Busuioc",   "Ocimum basilicum",      "🌿", 2, .fullSun),
            s("rosemary",   "Rosemary",   "Rozmarin",  "Salvia rosmarinus",     "🌿", 7, .fullSun),
            s("mint",       "Peppermint", "Mentă",     "Mentha ×piperita",      "🍃", 3, .medium),
            s("thyme",      "Thyme",      "Cimbru",    "Thymus vulgaris",       "🌿", 7, .fullSun),
            s("sage",       "Sage",       "Salvie",    "Salvia officinalis",    "🌿", 7, .fullSun),
            s("parsley",    "Parsley",    "Pătrunjel", "Petroselinum crispum",  "🌿", 3, .medium),
            s("oregano",    "Oregano",    "Oregano",   "Origanum vulgare",      "🌿", 7, .fullSun),
            s("tomato",     "Tomato",     "Roșie",     "Solanum lycopersicum",  "🍅", 2, .fullSun),
            s("pepper",     "Pepper",     "Ardei",     "Capsicum annuum",       "🫑", 2, .fullSun),
            s("strawberry", "Strawberry", "Căpșun",    "Fragaria ×ananassa",    "🍓", 3, .fullSun),
        ]),
    ]

    static let all: [PlantSpecies] = families.flatMap(\.species)

    static func species(id: String) -> PlantSpecies? {
        all.first { $0.id == id }
    }
}

// MARK: - Catalog picker sheet

struct PlantSpeciesPicker: View {
    var onPick: (PlantSpecies) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filteredFamilies: [PlantSpeciesFamily] {
        guard !search.trimmingCharacters(in: .whitespaces).isEmpty else { return PlantSpeciesCatalog.families }
        return PlantSpeciesCatalog.families.compactMap { family in
            let hits = family.species.filter {
                $0.nameEN.matchesSearch(search)
                    || $0.nameRO.matchesSearch(search)
                    || $0.latin.matchesSearch(search)
            }
            return hits.isEmpty ? nil : PlantSpeciesFamily(id: family.id, species: hits)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: AppSpacing.xs) {
                    if filteredFamilies.isEmpty {
                        EmptyStateView(icon: "magnifyingglass", title: "No results")
                    } else {
                        ForEach(filteredFamilies) { family in
                            sectionHeader(family.id)
                            ForEach(family.species) { entry in
                                row(entry)
                            }
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.sm)
                .padding(.bottom, AppSpacing.xl)
            }
            .navigationTitle(Text("plant_catalog_title"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text("plant_catalog_search"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationBackground(.thinMaterial)
        .presentationDragIndicator(.visible)
    }

    private func sectionHeader(_ key: String) -> some View {
        Text(LocalizedStringKey(key))
            .font(AppFont.captionStrong)
            .foregroundStyle(.secondary)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.xxs)
    }

    private func row(_ entry: PlantSpecies) -> some View {
        Button {
            HapticFeedback.selection()
            onPick(entry)
            dismiss()
        } label: {
            HStack(spacing: AppSpacing.md) {
                Text(entry.emoji)
                    .font(AppFont.scaled(19))
                    .frame(width: 36, height: 36)
                    .background(Color.primary.opacity(AppOpacity.hairline), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(AppFont.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(entry.latin)
                        .font(AppFont.caption)
                        .italic()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: AppSpacing.sm)
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: entry.light.symbol)
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Text(LocalizedStringKey(entry.light.titleKey)))
                    Text(verbatim: "💧 \(waterHint(entry.wateringDays))")
                        .font(AppFont.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, AppSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(entry.name), \(entry.latin), \(waterHint(entry.wateringDays))"))
    }

    private func waterHint(_ days: Int) -> String {
        String(format: String(localized: "plant_water_every_days"), days)
    }
}
