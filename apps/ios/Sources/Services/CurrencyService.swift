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

    var rates: [String: Double] = ["RON": 1.0]   // RON per 1 unit of foreign currency
    var lastUpdated: Date?
    var isLoading = false

    private let ratesKey = "prvio.bnr.rates"
    private let dateKey  = "prvio.bnr.ratesDate"
    private let ttl: TimeInterval = 4 * 3600   // refresh every 4 hours

    // MARK: - Refresh
    // Uses api.frankfurter.app — free, no key, updated daily by ECB.
    // Requests EUR as base, computes RON-per-unit rates for all other currencies.

    func refresh() async {
        if let cached = loadCache() { rates = cached; return }
        isLoading = true
        defer { isLoading = false }
        do {
            guard let url = URL(string: "https://api.frankfurter.app/latest?from=EUR&to=RON,USD,GBP,CHF") else { return }
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw URLError(.badServerResponse)
            }
            struct FrankfurterResponse: Decodable {
                let rates: [String: Double]
            }
            let parsed = try JSONDecoder().decode(FrankfurterResponse.self, from: data)
            guard let eurToRon = parsed.rates["RON"] else { throw URLError(.cannotParseResponse) }
            // Convert to RON-per-unit format (RON = 1.0 base):
            // 1 EUR = eurToRon RON → rates["EUR"] = eurToRon
            // 1 USD = (eurToRon / eurToUSD) RON → rates["USD"] = eurToRon / eurToUSD
            var result: [String: Double] = ["RON": 1.0, "EUR": eurToRon]
            for (code, eurToCode) in parsed.rates where code != "RON" {
                result[code] = eurToRon / eurToCode
            }
            rates = result
            lastUpdated = Date()
            saveCache(result)
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

