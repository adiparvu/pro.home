import Foundation

@MainActor
final class CurrencyService: ObservableObject {

    // Currencies shown in the picker
    static let supported: [(code: String, name: String, symbol: String)] = [
        ("EUR", "Euro",           "€"),
        ("RON", "Lei",            "lei"),
        ("USD", "US Dollar",      "$"),
        ("GBP", "British Pound",  "£"),
        ("CHF", "Swiss Franc",    "CHF"),
    ]

    @Published var rates: [String: Double] = ["RON": 1.0]   // RON per 1 unit of foreign currency
    @Published var lastUpdated: Date?
    @Published var isLoading = false

    private let ratesKey = "prvio.bnr.rates"
    private let dateKey  = "prvio.bnr.ratesDate"
    private let ttl: TimeInterval = 4 * 3600   // refresh every 4 hours

    // MARK: - Refresh

    func refresh() async {
        if let cached = loadCache() { rates = cached; return }
        isLoading = true
        defer { isLoading = false }
        do {
            let url = URL(string: "https://www.bnr.ro/nbrfxrates.xml")!
            let (data, _) = try await URLSession.shared.data(from: url)
            var parsed = try await Task.detached(priority: .utility) {
                try BNRXMLParser.parse(data: data)
            }.value
            parsed["RON"] = 1.0
            rates = parsed
            lastUpdated = Date()
            saveCache(parsed)
        } catch {
            if let stale = loadCache(ignoreAge: true) { rates = stale }
        }
    }

    // MARK: - Conversion

    func convert(_ amount: Double, from: String, to: String) -> Double {
        guard from != to else { return amount }
        let fromRate = rates[from] ?? 1.0   // RON per 1 from-unit
        let toRate   = rates[to]   ?? 1.0   // RON per 1 to-unit
        return amount * fromRate / toRate
    }

    func symbol(for code: String) -> String {
        Self.supported.first { $0.code == code }?.symbol ?? code
    }

    func formatted(_ amount: Double, from recordCurrency: String, preferred: String) -> String {
        let v = convert(amount, from: recordCurrency, to: preferred)
        let sym = symbol(for: preferred)
        return preferred == "RON"
            ? String(format: "%.0f %@", v, sym)
            : String(format: "%@%.0f", sym, v)
    }

    func rateDisplay(for code: String) -> String {
        guard code != "RON", let rate = rates[code] else { return "1 RON = 1 lei" }
        return String(format: "1 %@ = %.4f lei", code, rate)
    }

    var lastUpdatedDisplay: String {
        guard let date = lastUpdated else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Cache

    private func loadCache(ignoreAge: Bool = false) -> [String: Double]? {
        guard
            let date = UserDefaults.standard.object(forKey: dateKey) as? Date,
            ignoreAge || Date().timeIntervalSince(date) < ttl,
            let data = UserDefaults.standard.data(forKey: ratesKey),
            let cached = try? JSONDecoder().decode([String: Double].self, from: data)
        else { return nil }
        lastUpdated = date
        return cached
    }

    private func saveCache(_ r: [String: Double]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(r), forKey: ratesKey)
        UserDefaults.standard.set(Date(), forKey: dateKey)
    }
}

// MARK: - BNR XML Parser (runs off main actor)

private final class BNRXMLParser: NSObject, XMLParserDelegate {
    private var result: [String: Double] = [:]
    private var currentCurrency = ""
    private var currentMultiplier = 1.0
    private var currentChars = ""
    private var parseError: Error?

    static func parse(data: Data) throws -> [String: Double] {
        let p = BNRXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = p
        parser.parse()
        if let e = p.parseError { throw e }
        return p.result
    }

    func parser(_ p: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attr: [String: String]) {
        guard name == "Rate" else { return }
        currentCurrency   = attr["currency"] ?? ""
        currentMultiplier = Double(attr["multiplier"] ?? "1") ?? 1.0
        currentChars = ""
    }

    func parser(_ p: XMLParser, foundCharacters string: String) { currentChars += string }

    func parser(_ p: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard name == "Rate", !currentCurrency.isEmpty else { return }
        if let v = Double(currentChars.trimmingCharacters(in: .whitespaces)) {
            result[currentCurrency] = v / currentMultiplier
        }
        currentCurrency = ""
    }

    func parser(_ p: XMLParser, parseErrorOccurred error: Error) { parseError = error }
}
