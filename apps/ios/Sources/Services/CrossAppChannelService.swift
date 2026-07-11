import Foundation
import Observation

// MARK: - Cross-app messaging channel (real gateway)
//
// Every property gets an inbound channel: a secret token + the cross-app-inbox
// edge function. Anything that can make a POST request — a Shortcuts
// automation, Zapier/IFTTT, a home server, another app — drops messages
// straight into the house chat, delivered live over the existing realtime
// pipeline. This service owns the channel row (on/off, token rotation) and
// the one-tap live test; the Settings screens are presentation only.
//
// (The type keeps its original `CrossAppService` name — the custom
// integrations feature addresses it too — only its home moved out of the
// view layer.)

@MainActor
@Observable
final class CrossAppService {
    struct Channel: Codable {
        var propertyId: UUID
        var token: UUID
        var enabled: Bool
        var notifyRequests: Bool

        enum CodingKeys: String, CodingKey {
            case propertyId = "property_id"
            case token
            case enabled
            case notifyRequests = "notify_requests"
        }
    }

    var channel: Channel?
    var isLoading = false
    var error: String?

    static let endpoint = URL(string: "https://kwcanenheihuylaymwsl.supabase.co/functions/v1/cross-app-inbox")!

    func load(propertyId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let rows: [Channel] = try await supabase
                .from("cross_app_channels")
                .select("property_id, token, enabled, notify_requests")
                .eq("property_id", value: propertyId.uuidString)
                .execute().value
            channel = rows.first
        } catch { self.error = error.localizedDescription }
    }

    /// First enable creates the channel row (token generated server-side).
    func setEnabled(_ on: Bool, propertyId: UUID) async {
        do {
            if channel == nil, on {
                guard let uid = supabase.auth.currentSession?.user.id else { return }
                struct NewChannel: Encodable {
                    let property_id: String
                    let created_by: String
                }
                try await supabase.from("cross_app_channels")
                    .insert(NewChannel(property_id: propertyId.uuidString, created_by: uid.uuidString))
                    .execute()
            } else if channel != nil {
                try await supabase.from("cross_app_channels")
                    .update(["enabled": on])
                    .eq("property_id", value: propertyId.uuidString)
                    .execute()
            }
            await load(propertyId: propertyId)
        } catch { self.error = error.localizedDescription }
    }

    func setNotifyRequests(_ on: Bool, propertyId: UUID) async {
        do {
            try await supabase.from("cross_app_channels")
                .update(["notify_requests": on])
                .eq("property_id", value: propertyId.uuidString)
                .execute()
            channel?.notifyRequests = on
        } catch { self.error = error.localizedDescription }
    }

    /// Rotating the token instantly cuts off every service using the old one.
    func regenerateToken(propertyId: UUID) async {
        do {
            try await supabase.from("cross_app_channels")
                .update(["token": UUID().uuidString])
                .eq("property_id", value: propertyId.uuidString)
                .execute()
            await load(propertyId: propertyId)
        } catch { self.error = error.localizedDescription }
    }

    /// Posts through the PUBLIC endpoint — exactly what an external app does —
    /// so a green result proves the whole path, not just the database.
    func sendTest() async -> Bool {
        guard let token = channel?.token else { return false }
        var req = URLRequest(url: Self.endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode([
            "token": token.uuidString.lowercased(),
            "sender": String(localized: "Test PRVIO"),
            "text": String(localized: "Cross-app messaging works! 🎉"),
        ])
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }
}
