import Foundation
import Observation

// MARK: - Custom integrations ("connect anything")
//
// Each external service the household connects gets its own named integration
// with a dedicated secret token: a Zapier zap, a Home Assistant automation, a
// Raspberry Pi script, an alarm panel — anything that can POST JSON. Tokens
// are individually toggleable and revocable without disturbing the others,
// and last_used_at shows at a glance whether a service is actually alive.
// Delivery goes through the same cross-app-inbox edge function as the shared
// channel token; the property's channel switch remains the master kill switch.

struct CustomIntegration: Codable, Identifiable, Hashable {
    let id: UUID
    var propertyId: UUID
    var name: String
    var icon: String
    var color: String
    var token: UUID
    var enabled: Bool
    var lastUsedAt: Date?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case propertyId = "property_id"
        case name
        case icon
        case color
        case token
        case enabled
        case lastUsedAt = "last_used_at"
        case createdAt = "created_at"
    }
}

@MainActor
@Observable
final class CustomIntegrationService {
    var integrations: [CustomIntegration] = []
    var isLoading = false
    var error: String?

    private static let columns = "id, property_id, name, icon, color, token, enabled, last_used_at, created_at"

    func load(propertyId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            integrations = try await supabase
                .from("custom_integrations")
                .select(Self.columns)
                .eq("property_id", value: propertyId.uuidString)
                .order("created_at", ascending: true)
                .execute().value
            error = nil
        } catch { self.error = error.recordableDescription }
    }

    func create(propertyId: UUID, name: String, icon: String, color: String) async {
        guard let uid = supabase.auth.currentSession?.user.id else { return }
        struct NewIntegration: Encodable {
            let property_id: String
            let name: String
            let icon: String
            let color: String
            let created_by: String
        }
        do {
            try await supabase.from("custom_integrations")
                .insert(NewIntegration(
                    property_id: propertyId.uuidString,
                    name: name,
                    icon: icon,
                    color: color,
                    created_by: uid.uuidString
                ))
                .execute()
            await load(propertyId: propertyId)
        } catch { self.error = error.recordableDescription }
    }

    func setEnabled(_ integration: CustomIntegration, _ on: Bool) async {
        do {
            try await supabase.from("custom_integrations")
                .update(["enabled": on])
                .eq("id", value: integration.id.uuidString)
                .execute()
            if let i = integrations.firstIndex(where: { $0.id == integration.id }) {
                integrations[i].enabled = on
            }
        } catch { self.error = error.recordableDescription }
    }

    func rename(_ integration: CustomIntegration, name: String, icon: String, color: String) async {
        do {
            try await supabase.from("custom_integrations")
                .update(["name": name, "icon": icon, "color": color])
                .eq("id", value: integration.id.uuidString)
                .execute()
            if let i = integrations.firstIndex(where: { $0.id == integration.id }) {
                integrations[i].name = name
                integrations[i].icon = icon
                integrations[i].color = color
            }
        } catch { self.error = error.recordableDescription }
    }

    /// Rotating a token cuts off only THIS integration's old token.
    func rotateToken(_ integration: CustomIntegration) async {
        do {
            try await supabase.from("custom_integrations")
                .update(["token": UUID().uuidString])
                .eq("id", value: integration.id.uuidString)
                .execute()
            await load(propertyId: integration.propertyId)
        } catch { self.error = error.recordableDescription }
    }

    func delete(_ integration: CustomIntegration) async {
        do {
            try await supabase.from("custom_integrations")
                .delete()
                .eq("id", value: integration.id.uuidString)
                .execute()
            integrations.removeAll { $0.id == integration.id }
        } catch { self.error = error.recordableDescription }
    }

    /// Posts through the PUBLIC endpoint with this integration's own token —
    /// exactly what the external service does — then refreshes last_used_at.
    func sendTest(_ integration: CustomIntegration) async -> Bool {
        var req = URLRequest(url: CrossAppService.endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode([
            "token": integration.token.uuidString.lowercased(),
            "text": String(localized: "Integration test — everything works! 🎉"),
        ])
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return false }
        await load(propertyId: integration.propertyId)
        return true
    }
}
