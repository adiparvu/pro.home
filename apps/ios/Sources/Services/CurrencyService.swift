import Foundation
import Observation

@MainActor
@Observable
final class CurrencyService {

    // Currencies shown in the picker
    static let supported: [(code: String, name: String, symbol: String)] = [
        ("EUR", "Euro",           "€"),
        ("RON", "Lei",            "lei"),
        ("USD", "US Dollar",      "$"),
        ("GBP", "British Pound",  "£"),
        ("CHF", "Swiss Franc",    "CHF"),
    ]

    /// Where today's rates actually came from — shown to the user, never
    /// assumed. BNR is the primary (the official Romanian daily fixing);
    /// the ECB feed is the fallback so rates never silently stop updating.
    enum RateSource: String { case bnr, ecb }

    var rates: [String: Double] = ["RON": 1.0]   // RON per 1 unit of foreign currency
    var lastUpdated: Date?
    var isLoading = false
    var source: RateSource = .bnr

    private let ratesKey  = "prvio.bnr.rates"
    private let dateKey   = "prvio.bnr.ratesDate"
    private let sourceKey = "prvio.bnr.ratesSource"
    private let ttl: TimeInterval = 4 * 3600   // refresh every 4 hours

    // MARK: - Refresh
    // BNR first (bnr.ro daily fixing XML), ECB (api.frankfurter.app) as
    // fallback. `force` bypasses the cache so "refresh now" really refreshes.

    func refresh(force: Bool = false) async {
        if !force, let cached = loadCache() { rates = cached; return }
        isLoading = true
        defer { isLoading = false }
        if let bnr = await Self.fetchBNR() {
            apply(bnr, from: .bnr)
        } else if let ecb = await Self.fetchECB() {
            apply(ecb, from: .ecb)
        } else if let stale = loadCache(ignoreAge: true) {
            rates = stale
        }
    }

    func refreshNow() async { await refresh(force: true) }

    private func apply(_ result: [String: Double], from src: RateSource) {
        rates = result
        source = src
        lastUpdated = Date()
        saveCache(result)
        UserDefaults.standard.set(src.rawValue, forKey: sourceKey)
    }

    /// The official BNR daily fixing: XML with RON per `multiplier` units.
    nonisolated private static func fetchBNR() async -> [String: Double]? {
        guard let url = URL(string: "https://www.bnr.ro/nbrfxrates.xml"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let parsed = BNRRatesParser().parse(data)
        var result = parsed.filter { ["EUR", "USD", "GBP", "CHF"].contains($0.key) }
        result["RON"] = 1.0
        // All supported currencies or nothing — a partial table would make
        // conversions silently wrong for the missing ones.
        guard result.count == supported.count else { return nil }
        return result
    }

    nonisolated private static func fetchECB() async -> [String: Double]? {
        guard let url = URL(string: "https://api.frankfurter.app/latest?from=EUR&to=RON,USD,GBP,CHF"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        struct FrankfurterResponse: Decodable { let rates: [String: Double] }
        guard let parsed = try? JSONDecoder().decode(FrankfurterResponse.self, from: data),
              let eurToRon = parsed.rates["RON"] else { return nil }
        // Convert to RON-per-unit format (RON = 1.0 base):
        // 1 EUR = eurToRon RON → rates["EUR"] = eurToRon
        // 1 USD = (eurToRon / eurToUSD) RON → rates["USD"] = eurToRon / eurToUSD
        var result: [String: Double] = ["RON": 1.0, "EUR": eurToRon]
        for (code, eurToCode) in parsed.rates where code != "RON" {
            result[code] = eurToRon / eurToCode
        }
        return result
    }

    // MARK: - Conversion

    func convert(_ amount: Double, from: String, to: String) -> Double {
        guard from != to else { return amount }
        let fromRate = rates[from] ?? 1.0   // RON per 1 from-unit
        let toRate   = rates[to]   ?? 1.0   // RON per 1 to-unit
        return amount * fromRate / toRate
    }

    // MARK: - The app's one money display authority
    //
    // Every amount shown to the user goes through here: `Decimal` +
    // `FormatStyle.currency` gives the locale's separators ("1.234,56" in
    // Romanian), the narrow symbol on the locale's side ("1.234 lei",
    // "€1,234"), and *rounds* instead of the `Int(...)` truncation that
    // used to shave cents off displayed totals.

    /// `whole` rounds to whole units — the style for aggregate tiles and
    /// dashboards. Otherwise cents appear only when the amount has them.
    /// Pure function — nonisolated so models and background contexts can
    /// format without hopping to the main actor.
    nonisolated static func money(_ amount: Double, code: String, whole: Bool = false) -> String {
        Decimal(amount).formatted(
            .currency(code: code)
                .presentation(.narrow)
                .precision(.fractionLength(whole ? 0...0 : 0...2))
        )
    }

    /// Locale-grouped plain amount with no symbol or code ("1.200" /
    /// "1.234,56") — for call sites that place the currency code themselves
    /// (e.g. the lease's "1.200 EUR / month"). Whole amounts drop the
    /// fraction entirely; amounts with cents show up to two digits —
    /// matching the previous per-call `NumberFormatter` output exactly.
    nonisolated static func amount(_ value: Double) -> String {
        let f = value.truncatingRemainder(dividingBy: 1) == 0
            ? BareAmountFormat.whole
            : BareAmountFormat.cents
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    nonisolated static func symbol(for code: String) -> String {
        supported.first { $0.code == code }?.symbol ?? code
    }

    func symbol(for code: String) -> String {
        Self.symbol(for: code)
    }

    func formatted(_ amount: Double, from recordCurrency: String, preferred: String) -> String {
        Self.money(convert(amount, from: recordCurrency, to: preferred), code: preferred, whole: true)
    }

    func rateDisplay(for code: String) -> String {
        guard code != "RON", let rate = rates[code] else { return String(localized: "1 RON = 1 lei") }
        return String(format: String(localized: "1 %@ = %.4f lei"), code, rate)
    }

    var lastUpdatedDisplay: String {
        guard let date = lastUpdated else { return String(localized: "Never") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var sourceDisplay: String {
        source == .bnr ? String(localized: "currency_source_bnr")
                       : String(localized: "currency_source_ecb")
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
        if let raw = UserDefaults.standard.string(forKey: sourceKey),
           let cachedSource = RateSource(rawValue: raw) {
            source = cachedSource
        }
        return cached
    }

    private func saveCache(_ r: [String: Double]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(r), forKey: ratesKey)
        UserDefaults.standard.set(Date(), forKey: dateKey)
    }
}

// MARK: - Cached bare-amount formatters

/// `NumberFormatter` is expensive to create and not thread-safe to mutate,
/// but concurrent reads after configuration are safe — both instances are
/// fully configured in their static initializers and never touched again.
/// File-scope (outside the `@MainActor` class) so `CurrencyService.amount`
/// stays nonisolated for models and background contexts.
private enum BareAmountFormat {
    /// Whole amounts ("1.200") — no fraction shown.
    static let whole: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    /// Fractional amounts ("1.234,56") — up to two digits.
    static let cents: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        return f
    }()
}

// MARK: - BNR XML parser

/// Parses bnr.ro/nbrfxrates.xml: `<Rate currency="EUR">5.2310</Rate>`,
/// where some currencies quote per `multiplier` units (e.g. 100 HUF).
/// Returns RON per 1 unit for every rate in the document.
private final class BNRRatesParser: NSObject, XMLParserDelegate {
    private var rates: [String: Double] = [:]
    private var currentCurrency: String?
    private var currentMultiplier: Double = 1
    private var buffer = ""

    func parse(_ data: Data) -> [String: Double] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        return parser.parse() ? rates : [:]
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes attributeDict: [String: String] = [:]) {
        guard elementName == "Rate" else { return }
        currentCurrency = attributeDict["currency"]
        currentMultiplier = attributeDict["multiplier"].flatMap(Double.init) ?? 1
        buffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        guard elementName == "Rate", let currency = currentCurrency,
              let value = Double(buffer.trimmingCharacters(in: .whitespacesAndNewlines)),
              currentMultiplier > 0 else { currentCurrency = nil; return }
        rates[currency] = value / currentMultiplier
        currentCurrency = nil
    }
}

