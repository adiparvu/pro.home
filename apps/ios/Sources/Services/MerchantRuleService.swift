import Foundation
import Observation
import Supabase

// MARK: - Merchant → category rules ("categoriile care învață")
//
// The household's own memory of where each merchant belongs. Two writers:
// the OWNER's corrections (recategorizing an auto-imported expense teaches a
// rule, source "user") and Yuna's one-time classification of merchants no
// static rule knows (source "ai"). User rules always win over AI ones.
// Shared per property via Supabase, so a correction on one phone categorizes
// the same shop on every phone.

struct MerchantRule: Codable, Identifiable {
    let id: UUID
    let propertyId: UUID
    var merchantNorm: String
    var category: String
    var source: String        // "user" | "ai"

    enum CodingKeys: String, CodingKey {
        case id, category, source
        case propertyId   = "property_id"
        case merchantNorm = "merchant_norm"
    }
}

@MainActor
@Observable
final class MerchantRuleService {
    /// merchant_norm → rule, hydrated at startup and after every write.
    private(set) var byMerchant: [String: MerchantRule] = [:]
    var error: String?

    func load() async {
        let pid = PropertyService.activePropertyId
        if byMerchant.isEmpty, let cached = ServiceCache.load([MerchantRule].self, entity: "merchant_rules", propertyId: pid) {
            byMerchant = Dictionary(cached.map { ($0.merchantNorm, $0) }, uniquingKeysWith: { _, b in b })
        }
        do {
            let rules: [MerchantRule] = try await PropertyRepo.fetch(
                table: "merchant_rules", propertyId: pid, order: "updated_at", limit: 2000)
            byMerchant = Dictionary(rules.map { ($0.merchantNorm, $0) }, uniquingKeysWith: { _, b in b })
            ServiceCache.save(rules, entity: "merchant_rules", propertyId: pid)
        } catch {
            if error is CancellationError { return }
            self.error = error.recordableDescription
        }
    }

    /// The learned category for a merchant, if the household taught one.
    func category(for merchant: String) -> String? {
        byMerchant[MerchantCategorizer.normalize(merchant)]?.category
    }

    private struct UpsertRule: Encodable {
        let propertyId: String
        let merchantNorm: String
        let category: String
        let source: String
        let updatedAt: String
        enum CodingKeys: String, CodingKey {
            case category, source
            case propertyId   = "property_id"
            case merchantNorm = "merchant_norm"
            case updatedAt    = "updated_at"
        }
    }

    /// Records a rule. User corrections overwrite anything; AI verdicts never
    /// overwrite a user rule — the owner's word is final.
    func learn(merchant: String, category: String, source: String = "user") async {
        guard let pid = PropertyService.activePropertyId else { return }
        let norm = MerchantCategorizer.normalize(merchant)
        guard !norm.isEmpty, !category.isEmpty else { return }
        if source == "ai", byMerchant[norm]?.source == "user" { return }
        do {
            try await supabase.from("merchant_rules").upsert(
                UpsertRule(propertyId: pid.uuidString, merchantNorm: norm,
                           category: category, source: source,
                           updatedAt: ISODate.string(from: Date())),
                onConflict: "property_id,merchant_norm").execute()
            byMerchant[norm] = MerchantRule(id: byMerchant[norm]?.id ?? UUID(),
                                            propertyId: pid, merchantNorm: norm,
                                            category: category, source: source)
        } catch { self.error = error.recordableDescription }
    }

    // MARK: - Yuna fallback (one call per UNKNOWN merchant, cached forever)

    private struct CategorizePayload: Encodable { let merchants: [String] }
    private struct CategorizeReply: Decodable { let categories: [String: String] }

    /// Classifies merchants no static or learned rule knows, then caches the
    /// verdicts as AI rules so each merchant costs one call per household,
    /// ever. Returns merchant → category for the batch (empty on failure —
    /// callers fall back to "other", never block on the network).
    func classifyUnknown(_ merchants: [String]) async -> [String: String] {
        let unknown = merchants.filter {
            category(for: $0) == nil && MerchantCategorizer.staticCategory(for: $0) == nil
        }
        guard !unknown.isEmpty else { return [:] }
        do {
            let reply: CategorizeReply = try await supabase.functions.invoke(
                "categorize-merchant",
                options: .init(body: CategorizePayload(merchants: Array(unknown.prefix(25)))))
            for (merchant, cat) in reply.categories where cat != "other" {
                await learn(merchant: merchant, category: cat, source: "ai")
            }
            return reply.categories
        } catch {
            debugLog("categorize-merchant failed:", error)
            return [:]
        }
    }
}
