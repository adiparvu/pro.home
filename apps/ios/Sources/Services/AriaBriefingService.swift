import Foundation
import Observation
import Supabase

// MARK: - Yuna's daily take — the server-side proactive briefing
//
// One AI look per day over the household's aggregated data, produced by the
// `aria-chat` edge function's `briefing` mode (same privacy switches as the
// chat: a domain the owner turned off never reaches the model). The result
// is cached per (day, property) in UserDefaults, so the dashboard renders it
// instantly and the network+model cost is at most one call a day per
// property. Honesty law: on any failure the card simply shows nothing —
// the deterministic facts beneath it are never replaced by an apology.

@MainActor
@Observable
final class AriaBriefingService {
    static let shared = AriaBriefingService()
    private init() { loadCache() }

    /// Today's briefing text for the active property, or nil (not fetched /
    /// failed / different day).
    private(set) var briefing: String?

    private var cachedDayKey: String?
    private var cachedPropertyId: String?
    private var inFlight = false

    private static let cacheKey = "prvio.aria.dailyBriefing_v1"

    /// Fetches today's briefing once. Safe to call from every dashboard
    /// appearance — it early-outs when today's text (for this property) is
    /// already in hand or a fetch is running.
    func refreshIfStale(propertyId: UUID?) async {
        guard let propertyId else { return }
        let today = Self.dayKey(Date())
        if briefing != nil, cachedDayKey == today,
           cachedPropertyId == propertyId.uuidString { return }
        if inFlight { return }
        inFlight = true
        defer { inFlight = false }

        // Mirror the assistant's own settings (AI Settings page): the
        // briefing speaks with the same name, tone, language and sees only
        // the same domains as the chat.
        let d = UserDefaults.standard
        func allow(_ key: String) -> Bool { d.object(forKey: key) == nil ? true : d.bool(forKey: key) }
        let responseLanguage = d.string(forKey: "prvio.aria.responseLanguage") ?? "auto"
        let lang: String
        switch responseLanguage {
        case ARIAResponseLanguage.romanian.rawValue, ARIAResponseLanguage.english.rawValue:
            lang = responseLanguage
        default:
            let followSystem = d.object(forKey: "prvio.followSystemLang") == nil
                ? true : d.bool(forKey: "prvio.followSystemLang")
            lang = followSystem
                ? Language.devicePreferred.rawValue
                : (d.string(forKey: "prvio.locale") ?? "en")
        }

        struct BriefingPayload: Encodable {
            let mode: String
            let message: String
            let property_id: String
            let language: String
            let tone: String
            let assistant_name: String
            let allow_tasks: Bool
            let allow_finances: Bool
            let allow_property: Bool
            let allow_family: Bool
            let allow_plants: Bool
        }
        let payload = BriefingPayload(
            mode: "briefing",
            message: "briefing",
            property_id: propertyId.uuidString,
            language: lang,
            tone: d.string(forKey: "prvio.aria.personality") ?? "balanced",
            assistant_name: d.string(forKey: "prvio.aria.customName") ?? "ARIA",
            allow_tasks: allow("prvio.aria.showTasks"),
            allow_finances: allow("prvio.aria.showFinances"),
            allow_property: allow("prvio.aria.showProperty"),
            allow_family: allow("prvio.aria.showFamily"),
            allow_plants: allow("prvio.aria.showPlants"))

        do {
            let raw: Data = try await supabase.functions
                .invoke("aria-chat", options: .init(body: payload))
            guard let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
                  let reply = json["reply"] as? String,
                  !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return }
            briefing = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            cachedDayKey = today
            cachedPropertyId = propertyId.uuidString
            persistCache()
        } catch {
            // Silent by design — the deterministic facts carry the card.
        }
    }

    // MARK: - Per-day cache

    private static func dayKey(_ date: Date) -> String {
        AppDate.day.string(from: date)
    }

    private func persistCache() {
        guard let briefing, let cachedDayKey, let cachedPropertyId else { return }
        UserDefaults.standard.set(
            [cachedDayKey, cachedPropertyId, briefing], forKey: Self.cacheKey)
    }

    private func loadCache() {
        guard let parts = UserDefaults.standard.stringArray(forKey: Self.cacheKey),
              parts.count == 3, parts[0] == Self.dayKey(Date()) else { return }
        cachedDayKey = parts[0]
        cachedPropertyId = parts[1]
        briefing = parts[2]
    }
}
