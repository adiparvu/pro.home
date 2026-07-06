import Foundation
import Observation

@MainActor
@Observable
final class DeliveryService {
    var deliveries: [Delivery] = []
    private(set) var currentPropertyId: UUID?

    // MARK: Computed

    var activeDeliveries: [Delivery] { deliveries.filter { $0.isActive } }
    var todayDeliveries: [Delivery] {
        let todayStr = AppDate.dayString(from: Date())
        return deliveries.filter { $0.expectedDate == todayStr && $0.isActive }
    }

    // MARK: Supabase CRUD

    /// Re-fetches the current property's deliveries (used by pull-to-refresh).
    func reload() async {
        guard let pid = currentPropertyId else { return }
        await load(propertyId: pid)
    }

    // MARK: - Auto-import forwarding address

    var inbox: ParcelInbox?

    /// Loads the property's forwarding address, creating one on first use so the
    /// user always has an address to copy into their email filter.
    func ensureInbox(propertyId: UUID) async -> ParcelInbox? {
        if let inbox, inbox.propertyId == propertyId { return inbox }

        let existing: [ParcelInbox]? = try? await supabase
            .from("parcel_inbox")
            .select("id, property_id, token, active")
            .eq("property_id", value: propertyId.uuidString)
            .limit(1)
            .execute().value
        if let found = existing?.first { inbox = found; return found }

        // Create a fresh, hard-to-guess token.
        let token = "prv" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(9)
        struct NewInbox: Encodable { let property_id: String; let token: String }
        let created: ParcelInbox? = try? await supabase
            .from("parcel_inbox")
            .insert(NewInbox(property_id: propertyId.uuidString, token: String(token)))
            .select("id, property_id, token, active")
            .single()
            .execute().value
        inbox = created
        return created
    }

    func load(propertyId: UUID) async {
        // Paint the last known state instantly; the network refresh follows.
        if deliveries.isEmpty, let cached = ServiceCache.load([Delivery].self, entity: "deliveries", propertyId: propertyId) {
            deliveries = cached
        }
        currentPropertyId = propertyId
        do {
            deliveries = try await PropertyRepo.fetch(table: "packages", propertyId: propertyId,
                                                      scope: .strict, limit: 500)
            ServiceCache.save(deliveries, entity: "deliveries", propertyId: propertyId)
        } catch {
            #if DEBUG
            debugLog("DeliveryService.load error:", error)
            #endif
        }
    }

    func add(_ new: NewDelivery) async {
        do {
            let result: Delivery = try await supabase
                .from("packages")
                .insert(new)
                .select()
                .single()
                .execute()
                .value
            deliveries.insert(result, at: 0)
            // A new active package gets a Live Activity right away.
            LiveActivityService.shared.syncDelivery(result)
            // If it has a tracking number, start live courier tracking.
            if result.trackingNumber?.isEmpty == false {
                await registerTracking(result)
            }
        } catch {
            #if DEBUG
            debugLog("DeliveryService.add error:", error)
            #endif
        }
    }

    func update(_ delivery: Delivery) async {
        // Optional columns must be sent as JSON null, not "". An empty string
        // written to the `expected_date` (date) column is invalid syntax and
        // fails the whole update — which silently broke "Mark as delivered" and
        // editing for any package without a date. Encoding via optionals sends
        // an explicit null (also letting the user clear a previously-set date).
        struct UpdatePayload: Encodable {
            let description: String
            let carrier: String?
            let tracking_number: String?
            let status: String
            let expected_date: String?
            let notes: String?

            // Explicit keys: defining a custom encode(to:) suppresses the
            // compiler-synthesized CodingKeys, so they must be declared.
            enum CodingKeys: String, CodingKey {
                case description, carrier, tracking_number, status, expected_date, notes
            }

            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(description, forKey: .description)
                try c.encode(carrier, forKey: .carrier)
                try c.encode(tracking_number, forKey: .tracking_number)
                try c.encode(status, forKey: .status)
                try c.encode(expected_date, forKey: .expected_date)   // nil → null
                try c.encode(notes, forKey: .notes)
            }
        }
        func nilIfEmpty(_ s: String?) -> String? {
            let t = s?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (t?.isEmpty ?? true) ? nil : t
        }
        let payload = UpdatePayload(
            description: delivery.description,
            carrier: nilIfEmpty(delivery.carrier),
            tracking_number: nilIfEmpty(delivery.trackingNumber),
            status: delivery.status,
            expected_date: nilIfEmpty(delivery.expectedDate),
            notes: nilIfEmpty(delivery.notes)
        )
        do {
            let result: Delivery = try await supabase
                .from("packages")
                .update(payload)
                .eq("id", value: delivery.id.uuidString)
                .select()
                .single()
                .execute()
                .value
            if let i = deliveries.firstIndex(where: { $0.id == delivery.id }) {
                deliveries[i] = result
            }
            // Status changes flow into the Live Activity (ends it when the
            // package is delivered / returned / missed).
            LiveActivityService.shared.syncDelivery(result)
            // A tracking number added to a not-yet-tracked parcel starts tracking.
            if result.trackerId == nil, result.trackingNumber?.isEmpty == false {
                await registerTracking(result)
            }
        } catch {
            #if DEBUG
            debugLog("DeliveryService.update error:", error)
            #endif
        }
    }

    func delete(_ delivery: Delivery) async {
        do {
            try await supabase
                .from("packages")
                .delete()
                .eq("id", value: delivery.id.uuidString)
                .execute()
            deliveries.removeAll { $0.id == delivery.id }
            LiveActivityService.shared.endDelivery(id: delivery.id)
        } catch {
            #if DEBUG
            debugLog("DeliveryService.delete error:", error)
            #endif
        }
    }

    func markDelivered(_ delivery: Delivery) async {
        var updated = delivery
        updated.status = "delivered"
        await update(updated)
    }

    /// Registers a parcel for live courier tracking. The app only ever calls our
    /// own `track-register` Edge Function — the aggregator (Ship24/AfterShip) is
    /// entirely server-side, so switching providers later never touches the app.
    /// The courier is auto-detected from the tracking number, so no client-side
    /// courier mapping is needed.
    func registerTracking(_ delivery: Delivery) async {
        guard let tn = delivery.trackingNumber?.trimmingCharacters(in: .whitespacesAndNewlines),
              !tn.isEmpty else { return }
        struct Payload: Encodable { let package_id: String; let trackingNumber: String }
        do {
            _ = try await supabase.functions.invoke(
                "track-register",
                options: .init(body: Payload(package_id: delivery.id.uuidString, trackingNumber: tn))
            )
        } catch {
            // Tracking is best-effort — a failure here never blocks saving the
            // delivery (e.g. aggregator not yet configured returns 503).
            #if DEBUG
            debugLog("DeliveryService.registerTracking error:", error)
            #endif
        }
    }
}
