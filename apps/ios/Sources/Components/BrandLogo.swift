import SwiftUI
import UIKit

// MARK: - Brand logos (merchants & couriers)
//
// Turns "which parcel is this?" into a glance: the delivery list and dossier
// show the shop's (or courier's) real mark instead of a generic box. Three
// layers, each independent of the app binary so new brands need no update:
//
//   1. DOMAIN — the brand's web domain, resolved from data we already have
//      (the sender address of the shipping emails, or a curated directory of
//      merchants/couriers by name).
//   2. IMAGE — fetched once per domain from Google's public favicon service
//      and cached on disk; no API key, no bundled trademark assets.
//   3. FALLBACK — a monogram of the brand name, then the status icon, so the
//      circle is never empty and never a spinner.

// MARK: Directory

enum BrandDirectory {
    /// Curated name → domain map for brands the family actually meets:
    /// Romanian couriers and the big local + international shops. Keys are
    /// `normalize(_:)`d. This is the only place to grow when a brand's
    /// favicon should appear for manually-entered parcels.
    private static let brands: [String: String] = [
        // Couriers (names, form options and aggregator codes all normalize here)
        "dhl": "dhl.com", "fedex": "fedex.com", "ups": "ups.com",
        "dpd": "dpd.com", "gls": "gls-group.eu", "tnt": "tnt.com",
        "cargus": "cargus.ro", "urgentcargus": "cargus.ro",
        "fancourier": "fancourier.ro", "sameday": "sameday.ro",
        "postaromana": "posta-romana.ro",
        // Marketplaces & electronics
        "emag": "emag.ro", "altex": "altex.ro", "flanco": "flanco.ro",
        "mediagalaxy": "mediagalaxy.ro", "pcgarage": "pcgarage.ro",
        "evomag": "evomag.ro", "f64": "f64.ro", "amazon": "amazon.de",
        "aliexpress": "aliexpress.com", "temu": "temu.com", "ebay": "ebay.com",
        "apple": "apple.com", "samsung": "samsung.com",
        // Home & DIY
        "ikea": "ikea.com", "jysk": "jysk.ro", "dedeman": "dedeman.ro",
        "leroymerlin": "leroymerlin.ro", "hornbach": "hornbach.ro",
        "mobexpert": "mobexpert.ro", "vivre": "vivre.ro", "bonami": "bonami.ro",
        // Fashion & beauty
        "hm": "hm.com", "zara": "zara.com", "aboutyou": "aboutyou.ro",
        "answear": "answear.ro", "fashiondays": "fashiondays.ro",
        "shein": "shein.com", "sinsay": "sinsay.com", "reserved": "reserved.com",
        "ccc": "ccc.eu", "deichmann": "deichmann.com", "epantofi": "epantofi.ro",
        "pepco": "pepco.ro", "notino": "notino.ro", "sephora": "sephora.ro",
        "douglas": "douglas.ro",
        // Groceries, books, kids, sport, telco
        "lidl": "lidl.ro", "kaufland": "kaufland.ro", "carrefour": "carrefour.ro",
        "auchan": "auchan.ro", "megaimage": "mega-image.ro",
        "elefant": "elefant.ro", "libris": "libris.ro", "carturesti": "carturesti.ro",
        "noriel": "noriel.ro", "decathlon": "decathlon.ro",
        "orange": "orange.ro", "vodafone": "vodafone.ro", "digi": "digi.ro",
    ]

    /// Personal-mailbox domains: a manually forwarded email arrives "from" the
    /// family member, and their webmail's logo would be a wrong answer.
    private static let freemail: Set<String> = [
        "gmail.com", "googlemail.com", "yahoo.com", "yahoo.ro", "outlook.com",
        "hotmail.com", "live.com", "icloud.com", "me.com", "proton.me",
        "protonmail.com", "mail.com",
    ]

    /// Case-, diacritic- and punctuation-insensitive brand key:
    /// "Fan Courier" / "fan-courier" / "FAN Courier" all meet at "fancourier".
    private static func normalize(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Directory lookup by any brand string — merchant name, carrier name
    /// from the form, or an aggregator courier code.
    static func domain(forBrand name: String) -> String? {
        let key = normalize(name)
        guard !key.isEmpty else { return nil }
        return brands[key]
    }

    /// The registrable domain of an email sender ("news.jysk.ro" → "jysk.ro"),
    /// or nil for personal mailboxes. Accepts raw headers ("JYSK <no-reply@…>").
    static func senderDomain(_ from: String?) -> String? {
        guard let from = from?.lowercased(),
              let match = from.range(of: "@[a-z0-9.-]+\\.[a-z]{2,}", options: .regularExpression)
        else { return nil }
        var labels = from[match].dropFirst().split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return nil }
        // Keep three labels for compound TLDs (co.uk, com.au), two otherwise.
        let keep = (labels.count >= 3 && ["co", "com", "net", "org", "gov", "edu"].contains(labels[labels.count - 2])) ? 3 : 2
        labels.removeFirst(labels.count - keep)
        let domain = labels.joined(separator: ".")
        return freemail.contains(domain) ? nil : domain
    }
}

// MARK: Image store

/// One favicon fetch per domain per install: memory → disk → network, with
/// in-flight de-duplication and a per-launch negative cache so a brand
/// without a usable icon costs exactly one request per session.
actor BrandLogoStore {
    static let shared = BrandLogoStore()

    private let memory = NSCache<NSString, UIImage>()
    private var misses: Set<String> = []
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    func logo(for domain: String) async -> UIImage? {
        if let hit = memory.object(forKey: domain as NSString) { return hit }
        if misses.contains(domain) { return nil }
        if let running = inFlight[domain] { return await running.value }

        let task = Task<UIImage?, Never> { await Self.load(domain) }
        inFlight[domain] = task
        let result = await task.value
        inFlight[domain] = nil
        if let result { memory.setObject(result, forKey: domain as NSString) }
        else { misses.insert(domain) }
        return result
    }

    private static let cacheDir = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("BrandLogos", isDirectory: true)

    private static func load(_ domain: String) async -> UIImage? {
        let file = cacheDir.appendingPathComponent("\(domain).png")
        if let data = try? Data(contentsOf: file), let cached = UIImage(data: data) {
            return cached
        }
        guard let url = URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=128"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data),
              // The service answers unknown domains with a 16 px placeholder
              // globe — anything that small is not a brand mark.
              min(image.size.width, image.size.height) * image.scale >= 32
        else { return nil }
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try? data.write(to: file)
        return image
    }
}

// MARK: View

/// The brand circle: real logo when one resolves, the brand's monogram while
/// offline or unknown-favicon, the status icon when there is no brand at all.
/// Purely decorative — the row/hero text next to it carries the information.
struct BrandLogoCircle: View {
    let domain: String?
    let monogram: String?
    let fallbackIcon: String
    let tint: Color
    var size: CGFloat = 44

    @State private var logo: UIImage?

    var body: some View {
        ZStack {
            if let logo {
                // White chip under the mark — favicons are drawn for light
                // ground, and this is how Wallet/Mail present brand avatars.
                Circle().fill(.white)
                Circle().strokeBorder(Color.hairline)
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.58, height: size * 0.58)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.08, style: .continuous))
            } else {
                Circle().fill(tint.opacity(0.15))
                if let monogram, let initial = monogram.first {
                    Text(String(initial).uppercased())
                        .font(AppFont.scaled(size * 0.4, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                } else {
                    Image(systemName: fallbackIcon)
                        .font(AppFont.scaled(size * 0.38, weight: .medium))
                        .foregroundStyle(tint)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: domain) {
            guard let domain else { logo = nil; return }
            logo = await BrandLogoStore.shared.logo(for: domain)
        }
    }
}
