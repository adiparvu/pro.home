import Foundation

// MARK: - ReceiptProductLexicon
//
// Deterministic product-name normalization and fuzzy matching for receipt
// text. Receipts print "LAPTE ZUZU 1.5% 1L"; the shopping list says "Lapte"
// (or "Milk"). This lexicon folds diacritics and case, strips sizes and
// well-known brand tokens, maps multilingual synonyms onto one canonical
// product id, and scores how well a receipt line matches a list item.
//
// Everything here is rule-based and pure — no network, no models — so it is
// fast, offline, deterministic, and unit-testable.
enum ReceiptProductLexicon {

    /// Minimum `match(_:against:)` score that counts as "the same product".
    static let matchThreshold: Double = 0.6

    // MARK: - Folding

    /// Lowercases, strips diacritics and punctuation, collapses whitespace.
    /// "Brânză 1.5%  " → "branza 1.5%".
    static func fold(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive],
                               locale: Locale(identifier: "ro_RO"))
        var out = String.UnicodeScalarView()
        var lastWasSpace = true
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar)
                || scalar == "." || scalar == "," || scalar == "%" || scalar == "-" {
                out.append(scalar)
                lastWasSpace = false
            } else if !lastWasSpace {
                out.append(" ")
                lastWasSpace = true
            }
        }
        return String(out).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Noise tokens

    /// Brand tokens commonly printed before/after the product noun on
    /// Romanian and Belgian receipts. Stripped before matching.
    private static let brandTokens: Set<String> = [
        "zuzu", "napolact", "pilos", "milbona", "fulga", "dorna", "borsec",
        "cristim", "caroli", "danone", "activia", "muller", "hochland",
        "delaco", "olympus", "covalact", "president", "milka", "poiana",
        "heidi", "jacobs", "lavazza", "tchibo", "nescafe", "lipton",
        "pepsi", "fanta", "sprite", "timisoreana", "ursus", "ciucas",
        "bergenbier", "boni", "kania", "pirlanta", "vitalia", "baneasa",
    ]

    /// Unit / packaging words that carry no product identity.
    private static let unitTokens: Set<String> = [
        "l", "ml", "cl", "g", "gr", "kg", "buc", "bucata", "bucati", "pcs",
        "st", "stuks", "stuk", "set", "pachet", "bax", "vrac", "plic",
        "cutie", "sticla", "pet", "doza", "punga", "folie", "rola", "role",
    ]

    /// True for tokens that are pure numbers, sizes ("1.5", "500g", "10%")
    /// or single characters — they never identify a product.
    private static func isNoise(_ token: String) -> Bool {
        if token.count < 2 { return true }
        if unitTokens.contains(token) { return true }
        if brandTokens.contains(token) { return true }
        // "1.5", "500", "1,5%", "500g", "1l", "0.33l", "10%"
        let stripped = token.trimmingCharacters(in: CharacterSet(charactersIn: ".,%-"))
        if stripped.isEmpty { return true }
        var digits = 0, letters = 0
        var suffix = ""
        for ch in stripped {
            if ch.isNumber { digits += 1 }
            else if ch.isLetter { letters += 1; suffix.append(ch) }
        }
        if digits > 0 && letters == 0 { return true }
        if digits > 0 && letters <= 2 && unitTokens.contains(suffix) { return true }
        return false
    }

    // MARK: - Synonyms (variant token → canonical product id)

    /// Canonical id → display name (Romanian, with diacritics).
    static let displayNames: [String: String] = [
        "lapte": "Lapte", "oua": "Ouă", "paine": "Pâine", "banane": "Banane",
        "iaurt": "Iaurt", "rosii": "Roșii", "cartofi": "Cartofi",
        "ceapa": "Ceapă", "usturoi": "Usturoi", "mere": "Mere", "pui": "Pui",
        "vita": "Vită", "porc": "Porc", "cascaval": "Cașcaval",
        "branza": "Brânză", "unt": "Unt", "smantana": "Smântână",
        "orez": "Orez", "paste": "Paste", "zahar": "Zahăr", "faina": "Făină",
        "ulei": "Ulei", "sare": "Sare", "apa": "Apă", "suc": "Suc",
        "cafea": "Cafea", "ceai": "Ceai", "bere": "Bere", "vin": "Vin",
        "hartieigienica": "Hârtie igienică", "detergent": "Detergent",
        "sapun": "Săpun", "sampon": "Șampon", "pastadinti": "Pastă de dinți",
        "morcovi": "Morcovi", "castraveti": "Castraveți", "ardei": "Ardei",
        "salata": "Salată", "portocale": "Portocale", "lamai": "Lămâi",
        "struguri": "Struguri", "capsuni": "Căpșuni", "pere": "Pere",
        "piersici": "Piersici", "pepene": "Pepene", "somon": "Somon",
        "peste": "Pește", "ton": "Ton", "sunca": "Șuncă", "salam": "Salam",
        "carnati": "Cârnați", "crenvursti": "Crenvurști",
        "mozzarella": "Mozzarella", "parmezan": "Parmezan", "frisca": "Frișcă",
        "kefir": "Kefir", "otet": "Oțet", "mustar": "Muștar",
        "ketchup": "Ketchup", "maioneza": "Maioneză", "miere": "Miere",
        "gem": "Gem", "ciocolata": "Ciocolată", "biscuiti": "Biscuiți",
        "napolitane": "Napolitane", "chipsuri": "Chipsuri",
        "inghetata": "Înghețată", "cereale": "Cereale", "ovaz": "Ovăz",
        "nuci": "Nuci", "migdale": "Migdale", "arahide": "Arahide",
        "seminte": "Semințe", "fasole": "Fasole", "mazare": "Mazăre",
        "linte": "Linte", "naut": "Năut", "porumb": "Porumb",
        "ciuperci": "Ciuperci", "spanac": "Spanac", "broccoli": "Broccoli",
        "conopida": "Conopidă", "varza": "Varză", "dovlecei": "Dovlecei",
        "vinete": "Vinete", "servetele": "Șervețele", "grec": "grec",
    ]

    /// Folded receipt/list token → canonical product id. Covers Romanian,
    /// English, Dutch and French variants plus common receipt abbreviations.
    static let synonyms: [String: String] = [
        // dairy & eggs
        "lapte": "lapte", "milk": "lapte", "melk": "lapte", "lait": "lapte",
        "oua": "oua", "ou": "oua", "eggs": "oua", "egg": "oua",
        "eieren": "oua", "oeufs": "oua",
        "iaurt": "iaurt", "yogurt": "iaurt", "yoghurt": "iaurt", "yaourt": "iaurt",
        "unt": "unt", "butter": "unt", "boter": "unt", "beurre": "unt",
        "smantana": "smantana", "smintina": "smantana", "cream": "smantana",
        "cascaval": "cascaval", "kashkaval": "cascaval",
        "branza": "branza", "telemea": "branza", "cheese": "branza",
        "kaas": "branza", "fromage": "branza",
        "mozzarella": "mozzarella", "parmezan": "parmezan", "parmesan": "parmezan",
        "frisca": "frisca", "slagroom": "frisca", "kefir": "kefir",
        // bakery
        "paine": "paine", "franzela": "paine", "bread": "paine",
        "brood": "paine", "pain": "paine", "chifle": "paine",
        "bagheta": "paine", "lipie": "paine",
        // fruit & veg
        "banane": "banane", "ban": "banane", "banana": "banane",
        "bananas": "banane", "banaan": "banane", "bananen": "banane",
        "rosii": "rosii", "rosie": "rosii", "tomate": "rosii",
        "tomato": "rosii", "tomatoes": "rosii", "tomaten": "rosii",
        "cartofi": "cartofi", "cartof": "cartofi", "potato": "cartofi",
        "potatoes": "cartofi", "aardappelen": "cartofi",
        "ceapa": "ceapa", "onion": "ceapa", "onions": "ceapa", "uien": "ceapa",
        "usturoi": "usturoi", "garlic": "usturoi", "knoflook": "usturoi",
        "mere": "mere", "mar": "mere", "apple": "mere", "apples": "mere",
        "appels": "mere",
        "morcovi": "morcovi", "morcov": "morcovi", "carrot": "morcovi",
        "carrots": "morcovi", "wortelen": "morcovi",
        "castraveti": "castraveti", "castravete": "castraveti",
        "cucumber": "castraveti", "komkommer": "castraveti",
        "ardei": "ardei", "paprika": "ardei",
        "salata": "salata", "lettuce": "salata", "sla": "salata", "salade": "salata",
        "portocale": "portocale", "portocala": "portocale", "orange": "portocale",
        "oranges": "portocale", "sinaasappel": "portocale",
        "lamai": "lamai", "lamaie": "lamai", "lemon": "lamai", "citroen": "lamai",
        "struguri": "struguri", "grapes": "struguri", "druiven": "struguri",
        "capsuni": "capsuni", "strawberry": "capsuni", "strawberries": "capsuni",
        "aardbeien": "capsuni",
        "pere": "pere", "para": "pere", "pears": "pere", "peren": "pere",
        "piersici": "piersici", "peach": "piersici", "perziken": "piersici",
        "pepene": "pepene", "watermelon": "pepene", "meloen": "pepene",
        "ciuperci": "ciuperci", "mushrooms": "ciuperci", "champignons": "ciuperci",
        "spanac": "spanac", "spinach": "spanac", "spinazie": "spanac",
        "broccoli": "broccoli",
        "conopida": "conopida", "cauliflower": "conopida", "bloemkool": "conopida",
        "varza": "varza", "cabbage": "varza", "kool": "varza",
        "dovlecei": "dovlecei", "dovlecel": "dovlecei", "zucchini": "dovlecei",
        "courgette": "dovlecei",
        "vinete": "vinete", "vanata": "vinete", "eggplant": "vinete",
        "aubergine": "vinete",
        // meat & fish
        "pui": "pui", "piept": "pui", "chicken": "pui", "kip": "pui",
        "vita": "vita", "vitel": "vita", "beef": "vita", "rund": "vita",
        "porc": "porc", "pork": "porc", "varken": "porc",
        "somon": "somon", "salmon": "somon", "zalm": "somon",
        "peste": "peste", "fish": "peste", "vis": "peste",
        "ton": "ton", "tuna": "ton", "tonijn": "ton",
        "sunca": "sunca", "ham": "sunca", "jambon": "sunca",
        "salam": "salam", "salami": "salam",
        "carnati": "carnati", "carnat": "carnati", "sausage": "carnati",
        "worst": "carnati",
        "crenvursti": "crenvursti", "crenvurst": "crenvursti",
        // pantry
        "orez": "orez", "rice": "orez", "rijst": "orez", "riz": "orez",
        "paste": "paste", "spaghete": "paste", "spaghetti": "paste",
        "pasta": "paste", "macaroane": "paste", "penne": "paste",
        "fusilli": "paste",
        "zahar": "zahar", "sugar": "zahar", "suiker": "zahar", "sucre": "zahar",
        "faina": "faina", "flour": "faina", "bloem": "faina", "farine": "faina",
        "ulei": "ulei", "oil": "ulei", "olie": "ulei", "huile": "ulei",
        "sare": "sare", "salt": "sare", "zout": "sare", "sel": "sare",
        "otet": "otet", "vinegar": "otet", "azijn": "otet",
        "mustar": "mustar", "mustard": "mustar", "mosterd": "mustar",
        "ketchup": "ketchup",
        "maioneza": "maioneza", "mayo": "maioneza", "mayonnaise": "maioneza",
        "miere": "miere", "honey": "miere", "honing": "miere",
        "gem": "gem", "jam": "gem", "dulceata": "gem",
        "cereale": "cereale", "cereal": "cereale", "musli": "cereale",
        "muesli": "cereale", "granola": "cereale",
        "ovaz": "ovaz", "oats": "ovaz", "havermout": "ovaz",
        "nuci": "nuci", "walnuts": "nuci", "noten": "nuci",
        "migdale": "migdale", "almonds": "migdale", "amandelen": "migdale",
        "arahide": "arahide", "peanuts": "arahide", "pinda": "arahide",
        "seminte": "seminte", "seeds": "seminte",
        "fasole": "fasole", "beans": "fasole", "bonen": "fasole",
        "mazare": "mazare", "peas": "mazare", "erwten": "mazare",
        "linte": "linte", "lentils": "linte", "linzen": "linte",
        "naut": "naut", "chickpeas": "naut", "kikkererwten": "naut",
        "porumb": "porumb", "corn": "porumb", "mais": "porumb",
        // sweets & snacks
        "ciocolata": "ciocolata", "chocolate": "ciocolata",
        "chocolade": "ciocolata", "chocolat": "ciocolata",
        "biscuiti": "biscuiti", "biscuit": "biscuiti", "biscuits": "biscuiti",
        "cookies": "biscuiti", "koekjes": "biscuiti",
        "napolitane": "napolitane", "wafers": "napolitane",
        "chipsuri": "chipsuri", "chips": "chipsuri", "crisps": "chipsuri",
        "inghetata": "inghetata", "icecream": "inghetata", "ijs": "inghetata",
        // drinks
        "apa": "apa", "water": "apa", "minerala": "apa", "eau": "apa",
        "suc": "suc", "juice": "suc", "sap": "suc", "jus": "suc",
        "cafea": "cafea", "coffee": "cafea", "koffie": "cafea", "cafe": "cafea",
        "ceai": "ceai", "tea": "ceai", "thee": "ceai", "the": "ceai",
        "bere": "bere", "beer": "bere", "bier": "bere", "biere": "bere",
        "vin": "vin", "wine": "vin", "wijn": "vin",
        // household & personal care
        "hartie": "hartieigienica", "igienica": "hartieigienica",
        "toilet": "hartieigienica", "toiletpapier": "hartieigienica",
        "wc": "hartieigienica",
        "detergent": "detergent", "wasmiddel": "detergent",
        "sapun": "sapun", "soap": "sapun", "zeep": "sapun", "savon": "sapun",
        "sampon": "sampon", "shampoo": "sampon", "shampooing": "sampon",
        "dinti": "pastadinti", "toothpaste": "pastadinti", "tandpasta": "pastadinti",
        "servetele": "servetele", "napkins": "servetele", "tissues": "servetele",
        // qualifiers kept so "Iaurt grec" matches "IAURT GREC 10%"
        "grec": "grec", "greek": "grec",
    ]

    // MARK: - Canonical tokens

    /// Splits a raw name into folded tokens, drops noise (sizes, brands,
    /// units), and maps synonyms onto canonical product ids.
    static func canonicalTokens(_ raw: String) -> Set<String> {
        // Learned corrections apply here too, so list and pantry matching
        // see the user's name for the product, not the OCR noise.
        let source = ReceiptLexiconMemory.correction(for: raw) ?? raw
        var result: Set<String> = []
        for piece in fold(source).split(separator: " ") {
            let token = String(piece).trimmingCharacters(in: CharacterSet(charactersIn: ".,%-"))
            guard !token.isEmpty, !isNoise(token) else { continue }
            result.insert(synonyms[token] ?? token)
        }
        return result
    }

    // MARK: - Normalization

    /// Cleans a receipt line into a human-friendly product name:
    /// "LAPTE ZUZU 1.5% 1L" → "Lapte", "IAURT GREC 10%" → "Iaurt grec".
    /// Unknown tokens survive, cleaned and capitalized, so nothing is lost.
    static func normalize(_ raw: String) -> String {
        // The household's own corrections outrank every static rule — once
        // the user renames a line, that receipt token resolves instantly.
        if let learned = ReceiptLexiconMemory.correction(for: raw) { return learned }
        var words: [String] = []
        var seen: Set<String> = []
        for piece in fold(raw).split(separator: " ") {
            let token = String(piece).trimmingCharacters(in: CharacterSet(charactersIn: ".,%-"))
            guard !token.isEmpty, !isNoise(token) else { continue }
            let canonical = synonyms[token] ?? token
            guard seen.insert(canonical).inserted else { continue }
            words.append(displayNames[canonical] ?? token)
        }
        guard !words.isEmpty else {
            return raw.trimmingCharacters(in: .whitespaces).localizedCapitalized
        }
        let joined = words.joined(separator: " ")
        return joined.prefix(1).localizedUppercase + String(joined.dropFirst())
    }

    // MARK: - Matching

    /// Scores how likely `receiptItem` (an OCR'd receipt line) and
    /// `listItem` (a shopping-list entry) name the same product. 0…1;
    /// `matchThreshold` and above counts as a match.
    static func match(_ receiptItem: String, against listItem: String) -> Double {
        let a = canonicalTokens(receiptItem)
        let b = canonicalTokens(listItem)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        if a == b { return 1 }

        // Token-set overlap relative to the smaller set: full containment
        // ("Iaurt" ⊂ "Iaurt grec") scores 1.0.
        let overlap = a.intersection(b)
        if !overlap.isEmpty {
            return Double(overlap.count) / Double(min(a.count, b.count))
        }

        // Fuzzy fallback: each token of the smaller set finds its best
        // partner (prefix or bounded Levenshtein) in the larger set.
        let (small, large) = a.count <= b.count ? (a, b) : (b, a)
        var total = 0.0
        for t in small {
            var best = 0.0
            for u in large {
                best = max(best, tokenSimilarity(t, u))
                if best >= 1 { break }
            }
            total += best
        }
        return total / Double(small.count)
    }

    /// Similarity of two folded tokens: exact 1.0; prefix (≥3 chars)
    /// proportional to coverage; otherwise 1 − levenshtein/maxLength.
    static func tokenSimilarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        let maxLen = max(a.count, b.count)
        let minLen = min(a.count, b.count)
        guard maxLen > 0 else { return 0 }
        if minLen >= 3, a.hasPrefix(b) || b.hasPrefix(a) {
            return Double(minLen) / Double(maxLen)
        }
        let distance = levenshtein(a, b, cap: 5)
        return max(0, 1 - Double(distance) / Double(maxLen))
    }

    /// Classic DP Levenshtein, early-exited at `cap` (receipt tokens are
    /// short; anything beyond a few edits is "not the same word").
    static func levenshtein(_ a: String, _ b: String, cap: Int = 5) -> Int {
        let x = Array(a.unicodeScalars), y = Array(b.unicodeScalars)
        if abs(x.count - y.count) >= cap { return cap }
        if x.isEmpty { return min(y.count, cap) }
        if y.isEmpty { return min(x.count, cap) }
        var prev = Array(0...y.count)
        var curr = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            curr[0] = i
            var rowMin = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                curr[j] = Swift.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
                rowMin = Swift.min(rowMin, curr[j])
            }
            if rowMin >= cap { return cap }
            swap(&prev, &curr)
        }
        return Swift.min(prev[y.count], cap)
    }
}
