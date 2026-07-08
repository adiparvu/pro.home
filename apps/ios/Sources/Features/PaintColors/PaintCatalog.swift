import SwiftUI

// MARK: - Built-in paint catalog
//
// The RAL Classic palette — the code system every paint shop in Belgium and
// Romania mixes against — with the standard sRGB conversions, bilingual
// names, and the brands sold in both countries for one-tap filling of the
// form. Picking an entry fills name + code + hex, so the swatch squares in
// the gallery always carry the real color. The hexes are the published
// screen conversions: orientative on screen, exact at the mixing counter
// via the RAL code.

struct PaintCatalogColor: Identifiable, Equatable {
    let code: String      // "RAL 9010"
    let nameEN: String
    let nameRO: String
    let hex: String       // 6-digit sRGB, no '#'

    var id: String { code }
    var name: String { Locale.appIsRomanian ? nameRO : nameEN }
    var color: Color {
        guard let v = UInt64(hex, radix: 16) else { return .gray }
        return Color(red: Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255)
    }
}

struct PaintCatalogFamily: Identifiable {
    let id: String        // localization key for the section title
    let colors: [PaintCatalogColor]
}

enum PaintCatalog {

    /// Brands common on the Belgian and Romanian markets, for the brand menu.
    static let brandsBelgium = ["Levis", "Trimetal", "Sikkens", "Boss Paints", "Mathys", "Colora",
                                "Sigma", "Dulux", "Caparol", "Rust-Oleum", "V33"]
    static let brandsRomania = ["Policolor", "Spor", "Savana", "Kober", "Oskar", "Düfa", "Deutek",
                                "Danke!", "Caparol", "Dulux", "Azur", "Fabryo", "Duraziv", "Vitex"]

    private static func c(_ code: String, _ en: String, _ ro: String, _ hex: String) -> PaintCatalogColor {
        PaintCatalogColor(code: "RAL \(code)", nameEN: en, nameRO: ro, hex: hex)
    }

    static let families: [PaintCatalogFamily] = [
        PaintCatalogFamily(id: "paint_family_whites", colors: [
            c("9010", "Pure white", "Alb pur", "FFFFFF"),
            c("9016", "Traffic white", "Alb trafic", "F6F6F6"),
            c("9003", "Signal white", "Alb semnal", "F4F4F4"),
            c("9001", "Cream", "Crem", "FDF4E3"),
            c("9002", "Grey white", "Alb-gri", "E7EBDA"),
            c("1013", "Oyster white", "Alb perlat", "EAE6CA"),
            c("1015", "Light ivory", "Ivoriu deschis", "E6D2B5"),
        ]),
        PaintCatalogFamily(id: "paint_family_greys", colors: [
            c("7047", "Telegrey 4", "Gri deschis", "D0D0D0"),
            c("7035", "Light grey", "Gri luminos", "D7D7D7"),
            c("7040", "Window grey", "Gri fereastră", "9DA1AA"),
            c("7004", "Signal grey", "Gri semnal", "969992"),
            c("7001", "Silver grey", "Gri argintiu", "8A9597"),
            c("7042", "Traffic grey A", "Gri trafic", "8D948D"),
            c("7016", "Anthracite grey", "Gri antracit", "293133"),
            c("7021", "Black grey", "Gri-negru", "23282B"),
            c("9006", "White aluminium", "Aluminiu alb", "A5A5A5"),
            c("9007", "Grey aluminium", "Aluminiu gri", "8F8F8F"),
        ]),
        PaintCatalogFamily(id: "paint_family_beiges", colors: [
            c("1001", "Beige", "Bej", "D0B084"),
            c("1002", "Sand yellow", "Galben nisip", "D2AA6D"),
            c("1011", "Brown beige", "Bej-maro", "AB8153"),
            c("1019", "Grey beige", "Bej-gri", "A48F7A"),
            c("8001", "Ochre brown", "Maro ocru", "955F20"),
            c("8003", "Clay brown", "Maro argilă", "734222"),
            c("8011", "Nut brown", "Maro nucă", "5A3A29"),
            c("8017", "Chocolate brown", "Maro ciocolată", "45322E"),
            c("8025", "Pale brown", "Maro pal", "755C48"),
        ]),
        PaintCatalogFamily(id: "paint_family_yellows", colors: [
            c("1003", "Signal yellow", "Galben semnal", "F9A800"),
            c("1018", "Zinc yellow", "Galben zinc", "F8F32B"),
            c("1021", "Rape yellow", "Galben rapiță", "F3DA0B"),
            c("1023", "Traffic yellow", "Galben trafic", "FAD201"),
            c("1034", "Pastel yellow", "Galben pastel", "EFA94A"),
            c("2000", "Yellow orange", "Portocaliu-galben", "ED760E"),
            c("2003", "Pastel orange", "Portocaliu pastel", "FF7514"),
            c("2008", "Bright red orange", "Portocaliu aprins", "F75E25"),
            c("2011", "Deep orange", "Portocaliu intens", "EC7C26"),
        ]),
        PaintCatalogFamily(id: "paint_family_reds", colors: [
            c("3000", "Flame red", "Roșu flacără", "AF2B1E"),
            c("3003", "Ruby red", "Roșu rubin", "9B111E"),
            c("3005", "Wine red", "Roșu vin", "5E2129"),
            c("3009", "Oxide red", "Roșu oxid", "642424"),
            c("3012", "Beige red", "Roșu-bej", "C1876B"),
            c("3014", "Antique pink", "Roz antic", "D36E70"),
            c("3015", "Light pink", "Roz deschis", "EA899A"),
            c("4003", "Heather violet", "Violet erică", "DE4C8A"),
            c("4005", "Blue lilac", "Lila-albastru", "6C4675"),
            c("4008", "Signal violet", "Violet semnal", "924E7D"),
            c("4010", "Telemagenta", "Telemagenta", "CF3476"),
        ]),
        PaintCatalogFamily(id: "paint_family_blues", colors: [
            c("5012", "Light blue", "Albastru deschis", "3B83BD"),
            c("5015", "Sky blue", "Albastru cer", "2271B3"),
            c("5024", "Pastel blue", "Albastru pastel", "5D9B9B"),
            c("5023", "Distant blue", "Albastru estompat", "49678D"),
            c("5014", "Pigeon blue", "Albastru porumbel", "606E8C"),
            c("5010", "Gentian blue", "Albastru gențiană", "0E294B"),
            c("5005", "Signal blue", "Albastru semnal", "1E2460"),
            c("5002", "Ultramarine blue", "Albastru ultramarin", "20214F"),
            c("5003", "Sapphire blue", "Albastru safir", "1D1E33"),
            c("5009", "Azure blue", "Albastru azur", "025669"),
        ]),
        PaintCatalogFamily(id: "paint_family_greens", colors: [
            c("6019", "Pastel green", "Verde pastel", "BDECB6"),
            c("6021", "Pale green", "Verde pal", "89AC76"),
            c("6017", "May green", "Verde mai", "587246"),
            c("6011", "Reseda green", "Verde rezeda", "6C7156"),
            c("6029", "Mint green", "Verde mentă", "20603D"),
            c("6000", "Patina green", "Verde patină", "316650"),
            c("6027", "Light green", "Verde luminos", "84C3BE"),
            c("6034", "Pastel turquoise", "Turcoaz pastel", "7FB5B5"),
            c("6005", "Moss green", "Verde mușchi", "2F4538"),
        ]),
        PaintCatalogFamily(id: "paint_family_darks", colors: [
            c("9004", "Signal black", "Negru semnal", "282828"),
            c("9005", "Jet black", "Negru intens", "0A0A0A"),
            c("9011", "Graphite black", "Negru grafit", "1C1C1C"),
            c("9017", "Traffic black", "Negru trafic", "1E1E1E"),
        ]),
    ]

    static let all: [PaintCatalogColor] = families.flatMap(\.colors)

    /// Catalog lookup for entries saved with a RAL code but no hex —
    /// their gallery squares get the real color anyway.
    static func hex(forCode raw: String) -> String? {
        let cleaned = raw.uppercased()
            .replacingOccurrences(of: "RAL", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard cleaned.count == 4, Int(cleaned) != nil else { return nil }
        return all.first { $0.code == "RAL \(cleaned)" }?.hex
    }
}

// MARK: - Catalog picker sheet

struct PaintCatalogPicker: View {
    var onPick: (PaintCatalogColor) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filteredFamilies: [PaintCatalogFamily] {
        guard !search.trimmingCharacters(in: .whitespaces).isEmpty else { return PaintCatalog.families }
        return PaintCatalog.families.compactMap { family in
            let hits = family.colors.filter {
                $0.name.matchesSearch(search) || $0.code.matchesSearch(search)
            }
            return hits.isEmpty ? nil : PaintCatalogFamily(id: family.id, colors: hits)
        }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    if filteredFamilies.isEmpty {
                        EmptyStateView(icon: "magnifyingglass", title: "No results")
                    } else {
                        ForEach(filteredFamilies) { family in
                            section(family)
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.sm)
                .padding(.bottom, AppSpacing.xl)
            }
            .navigationTitle(Text("paint_catalog_title"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text("paint_catalog_search"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationBackground(.thinMaterial)
        .presentationDragIndicator(.visible)
    }

    private func section(_ family: PaintCatalogFamily) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(LocalizedStringKey(family.id))
                .textCase(.uppercase)
                .font(AppFont.captionStrong)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(family.colors) { entry in
                    tile(entry)
                }
            }
        }
    }

    private func tile(_ entry: PaintCatalogColor) -> some View {
        Button {
            HapticFeedback.selection()
            onPick(entry)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(entry.color)
                    .frame(height: 56)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.7)
                    )
                Text(entry.name)
                    .font(AppFont.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(entry.code)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(entry.name), \(entry.code)"))
    }
}
