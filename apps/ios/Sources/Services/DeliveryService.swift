import Foundation
import Observation
import UserNotifications

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
            let fresh: [Delivery] = try await PropertyRepo.fetch(table: "packages", propertyId: propertyId,
                                                                 scope: .strict, limit: 500)
            // Fire a local notification for any parcel that ADVANCED since we
            // last saw it — the "push on status change" half of tracking, which
            // works for manual edits, the email import and (once configured) the
            // courier aggregator alike, with no external key needed.
            notifyStatusChanges(fresh)
            deliveries = fresh
            ServiceCache.save(deliveries, entity: "deliveries", propertyId: propertyId)
        } catch {
            #if DEBUG
            debugLog("DeliveryService.load error:", error)
            #endif
        }
    }

    // MARK: - Status-change notifications
    //
    // Remembers each parcel's last-seen journey stage (App-independent, in
    // UserDefaults) and notifies when it moves FORWARD to a milestone the user
    // cares about — out for delivery, or delivered. A parcel seen for the first
    // time only records its baseline (no notification), so opening the app never
    // spams alerts for packages that were already on their way.
    private static let lastStageKey = "prvio.deliveries.lastStage"

    private func notifyStatusChanges(_ fresh: [Delivery]) {
        let defaults = UserDefaults.standard
        var map = (defaults.dictionary(forKey: Self.lastStageKey) as? [String: Int]) ?? [:]
        var dirty = false

        for d in fresh {
            let id = d.id.uuidString
            let stage = d.progressStage
            let previous = map[id]
            if let previous, stage > previous {
                switch stage {
                case 2: scheduleDeliveryNotification(d, kind: .outForDelivery)
                case 3: scheduleDeliveryNotification(d, kind: .delivered)
                default: break
                }
            }
            if previous != stage { map[id] = stage; dirty = true }
        }
        // Forget parcels that no longer exist so the map can't grow unbounded.
        let liveIds = Set(fresh.map { $0.id.uuidString })
        for key in map.keys where !liveIds.contains(key) { map.removeValue(forKey: key); dirty = true }

        if dirty { defaults.set(map, forKey: Self.lastStageKey) }
    }

    private enum DeliveryNotificationKind { case outForDelivery, delivered }

    private func scheduleDeliveryNotification(_ delivery: Delivery, kind: DeliveryNotificationKind) {
        let content = UNMutableNotificationContent()
        content.title = delivery.description
        switch kind {
        case .outForDelivery: content.body = String(localized: "deliv_notif_ofd")
        case .delivered:      content.body = String(localized: "deliv_notif_delivered")
        }
        content.sound = .default
        content.categoryIdentifier = "PROACTIVE"
        content.userInfo = ["deepLink": "prvio://deliveries"]
        let request = UNNotificationRequest(
            identifier: "delivery.\(delivery.id.uuidString).\(kind == .delivered ? "d" : "o")",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        UNUserNotificationCenter.current().add(request)
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
