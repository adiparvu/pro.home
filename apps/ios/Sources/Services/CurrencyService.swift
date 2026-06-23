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

