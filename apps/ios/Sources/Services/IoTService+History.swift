import Foundation
import os

// MARK: - Sensor history (Smart Control R4)
//
// iot_events stops being write-only: the same per-account event log the
// iot-event edge function fills (webhook alerts, "Phone Alert" automations)
// now also feeds history charts, and the app itself mirrors HomeKit
// indoor-climate readings into it — added as an extension so the frozen
// IoTService.swift stays untouched (the HomeKitService+Rooms pattern).
//
// Two writers, one log:
// - the edge function (service role) persists webhook events, as before;
// - the signed-in app inserts `event = "reading"` rows for HomeKit sensors
//   (owner-only RLS insert policy, migration 154), throttled to at most one
//   point per sensor per 30 minutes.
//
// Honesty: history reads return only rows the server actually has; the
// mirror never blocks UI and never surfaces its failures to the user — it
// logs them and tries again on a later refresh.

/// One measurement out of `iot_events` — the history chart's raw point.
struct IoTHistoryPoint: Decodable, Identifiable, Sendable {
    let id: UUID
    /// nil for events that carried no numeric value (e.g. a bare alert);
    /// the chart skips them, min/max ignore them.
    let value: Double?
    let unit: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, value, unit
        case createdAt = "created_at"
    }
}

extension IoTService {

    // MARK: History reads

    /// The widest window the history surface offers (30 days) and the
    /// explicit row cap on its one query (constitution P0-D — PostgREST
    /// truncates silently without a limit). 30 days of 30-minute mirror
    /// points is ~1 440 rows per sensor, so the cap only ever bites on a
    /// firmware that floods the webhook.
    static let historyWindow: TimeInterval = 30 * 86_400
    static let historyQueryLimit = 2_000

    /// Every event for one sensor inside the trailing 30-day window,
    /// oldest-first, capped at `historyQueryLimit` NEWEST rows. When the
    /// cap bites, the result is honestly the newest slice — callers use
    /// `count == historyQueryLimit` to know the window is partial.
    func sensorHistory(sensorId: String) async throws -> [IoTHistoryPoint] {
        guard let uid = supabase.auth.currentSession?.user.id else { return [] }
        let since = Date().addingTimeInterval(-Self.historyWindow)
        let rows: [IoTHistoryPoint] = try await supabase.from("iot_events")
            .select("id, value, unit, created_at")
            .eq("user_id", value: uid.uuidString)
            .eq("sensor_id", value: sensorId)
            .gte("created_at", value: ISODate.string(from: since))
            .order("created_at", ascending: false)
            .limit(Self.historyQueryLimit)
            .execute().value
        return rows.reversed()
    }

    /// The `iot_events.sensor_id` under which a HomeKit accessory's metric
    /// accrues history — stable because `HMAccessory.uniqueIdentifier` is.
    static func homeKitSensorId(accessory id: UUID, metric: String) -> String {
        "hk:\(id.uuidString):\(metric)"
    }

    // MARK: HomeKit mirroring (fire-and-forget from IndoorClimateStore)

    /// Minimum spacing between two mirrored points for the same sensor.
    static let mirrorInterval: TimeInterval = 30 * 60

    /// Inserts fresh HomeKit indoor readings into `iot_events` so HomeKit
    /// sensors accrue the same history as webhook-fed ones.
    ///
    /// Throttle design — two layers, both cheap:
    /// 1. A local last-mirrored map (UserDefaults) answers "did THIS device
    ///    mirror this sensor in the last 30 minutes?" without any network.
    /// 2. Survivors get one indexed server read of the account's newest
    ///    events inside the window, so a second signed-in device (or a
    ///    reinstall that lost the local map) still can't double-write.
    /// Failures are logged and swallowed — background mirroring must never
    /// raise a user-facing error; the next scene-active refresh retries.
    func mirrorIndoorClimate(_ readings: [IndoorClimateReading]) async {
        guard !readings.isEmpty,
              let uid = supabase.auth.currentSession?.user.id,
              !IoTHistoryMirror.isRunning else { return }
        IoTHistoryMirror.isRunning = true
        defer { IoTHistoryMirror.isRunning = false }

        let now = Date()

        // Layer 1 — local throttle map.
        var candidates = readings.flatMap { Self.mirrorSamples(for: $0) }.filter { sample in
            guard let last = IoTHistoryMirror.lastMirrored[sample.sensorId] else { return true }
            return now.timeIntervalSince(last) >= Self.mirrorInterval
        }
        guard !candidates.isEmpty else { return }

        // Layer 2 — the server's word on what was already written inside
        // the window (by any device). One indexed read, explicit limit.
        struct RecentRow: Decodable {
            let sensorId: String?
            let createdAt: Date
            enum CodingKeys: String, CodingKey {
                case sensorId = "sensor_id"
                case createdAt = "created_at"
            }
        }
        do {
            let cutoff = now.addingTimeInterval(-Self.mirrorInterval)
            let recent: [RecentRow] = try await supabase.from("iot_events")
                .select("sensor_id, created_at")
                .eq("user_id", value: uid.uuidString)
                .gte("created_at", value: ISODate.string(from: cutoff))
                .order("created_at", ascending: false)
                .limit(300)
                .execute().value
            let freshOnServer = Set(recent.compactMap(\.sensorId))
            candidates.removeAll { sample in
                guard freshOnServer.contains(sample.sensorId) else { return false }
                IoTHistoryMirror.remember(sample.sensorId, at: now)
                return true
            }
        } catch {
            IoTHistoryMirror.logger.error("freshness check failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard !candidates.isEmpty else { return }

        // One batch insert for everything that survived both gates.
        struct NewEvent: Encodable {
            let user_id: String
            let sensor_id: String
            let name: String
            let type: String
            let value: Double
            let unit: String
            let zone: String?
            let display: String
            let event: String
        }
        let rows = candidates.map { sample in
            NewEvent(user_id: uid.uuidString,
                     sensor_id: sample.sensorId,
                     name: sample.name,
                     type: sample.type,
                     value: sample.value,
                     unit: sample.unit,
                     zone: sample.zone,
                     display: sample.display,
                     event: "reading")
        }
        do {
            try await supabase.from("iot_events").insert(rows).execute()
            for sample in candidates {
                IoTHistoryMirror.remember(sample.sensorId, at: now)
            }
        } catch {
            IoTHistoryMirror.logger.error("mirror insert failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// One reading → up to two samples (temperature always, humidity when
    /// the accessory reports one), typed/united like the IoT hub's sensors.
    private struct MirrorSample {
        let sensorId: String
        let name: String
        let type: String
        let value: Double
        let unit: String
        let zone: String?
        let display: String
    }

    private static func mirrorSamples(for reading: IndoorClimateReading) -> [MirrorSample] {
        var out: [MirrorSample] = [
            MirrorSample(sensorId: homeKitSensorId(accessory: reading.id, metric: "temperature"),
                         name: reading.accessoryName,
                         type: "temperature",
                         value: reading.celsius,
                         unit: "°C",
                         zone: reading.roomName,
                         display: String(format: "%.1f °C", reading.celsius)),
        ]
        if let humidity = reading.humidity {
            out.append(
                MirrorSample(sensorId: homeKitSensorId(accessory: reading.id, metric: "humidity"),
                             name: reading.accessoryName,
                             type: "humidity",
                             value: humidity,
                             unit: "%",
                             zone: reading.roomName,
                             display: String(format: "%.0f %%", humidity)))
        }
        return out
    }

    // MARK: Webhook secret (setup surface)

    /// The per-account secret embedded in `webhookURL` — surfaced by the
    /// webhook setup page (treated like a password there). nil until
    /// `ensureWebhook()` has succeeded.
    var webhookSecret: String? {
        guard let url = webhookURL,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        return components.queryItems?.first { $0.name == "token" }?.value
    }
}

// MARK: - Mirror state
//
// The frozen IoTService.swift can't grow stored properties, so the mirror's
// tiny state lives here: the persisted last-mirrored map and a re-entrancy
// gate. Main-actor only (every caller is), so plain statics are safe.

@MainActor
private enum IoTHistoryMirror {
    static let logger = Logger(subsystem: "com.prvio.app", category: "iot-history")
    static var isRunning = false

    private static let mapKey = "prvio.iot.history.lastMirrored"

    static var lastMirrored: [String: Date] = {
        guard let data = UserDefaults.standard.data(forKey: mapKey),
              let map = try? JSONDecoder().decode([String: Date].self, from: data) else { return [:] }
        return map
    }()

    static func remember(_ sensorId: String, at date: Date) {
        lastMirrored[sensorId] = date
        // Drop entries far outside the throttle window so the map can't
        // grow unboundedly across years of accessory churn.
        let horizon = date.addingTimeInterval(-IoTService.historyWindow)
        lastMirrored = lastMirrored.filter { $0.value > horizon }
        if let data = try? JSONEncoder().encode(lastMirrored) {
            UserDefaults.standard.set(data, forKey: mapKey)
        }
    }
}
