import Foundation
import Observation
import Supabase
import UIKit

// MARK: - Device sessions — the real registry behind "Active sessions"
//
// Owns the `device_sessions` table (one row per (user, device), RLS
// self-only). Every foreground registration upserts this device's row with a
// fresh `last_seen_at` heartbeat, throttled to one write per 15 minutes so
// opening Settings repeatedly costs nothing. A genuinely NEW device — no row
// for this (user, device_id) while other rows already exist — additionally
// records a `new_device_login` row in `account_security_events`; that signal
// is real, never inferred. Revoking a session deletes its registry row and
// records `session_revoked` — token invalidation stays with
// `auth.signOut(scope: .others)`, which the sheet keeps as its own action.

struct DeviceSession: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let deviceId: String
    let deviceName: String?
    let model: String?
    let osVersion: String?
    let appBuild: String?
    let createdAt: String
    let lastSeenAt: String

    enum CodingKeys: String, CodingKey {
        case id, model
        case userId     = "user_id"
        case deviceId   = "device_id"
        case deviceName = "device_name"
        case osVersion  = "os_version"
        case appBuild   = "app_build"
        case createdAt  = "created_at"
        case lastSeenAt = "last_seen_at"
    }

    var lastSeenDate: Date? { AppDate.timestamp(from: lastSeenAt) }
}

@MainActor
@Observable
final class DeviceSessionService {
    static let shared = DeviceSessionService()
    private init() {}

    private(set) var sessions: [DeviceSession] = []
    var currentDeviceId: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }

    /// Heartbeat throttle: at most one upsert per 15 minutes, except the
    /// first call after launch (lastHeartbeat starts nil).
    @ObservationIgnored private var lastHeartbeat: Date?
    private static let heartbeatInterval: TimeInterval = 15 * 60

    // MARK: Register / heartbeat

    private struct SessionUpsert: Encodable {
        let user_id: String
        let device_id: String
        let device_name: String
        let model: String
        let os_version: String
        let app_build: String?
        let last_seen_at: String
    }

    private struct SecurityEventInsert: Encodable {
        struct Payload: Encodable {
            let device_name: String
            let model: String?
        }
        let user_id: String
        let type: String
        let payload: Payload
    }

    func registerCurrentDevice() async {
        guard let userId = supabase.auth.currentSession?.user.id else { return }
        if let lastHeartbeat,
           Date().timeIntervalSince(lastHeartbeat) < Self.heartbeatInterval {
            return
        }
        lastHeartbeat = Date()

        let device = UIDevice.current
        let deviceId = currentDeviceId
        let deviceName = device.name
        let model = device.model

        do {
            // New-device detection BEFORE the upsert: a device is "new" only
            // when this (user, device_id) has no row yet while the account
            // already has at least one other registered device — a first-ever
            // install on a fresh account is not a security event.
            struct IdRow: Decodable { let device_id: String }
            let existing: [IdRow] = try await supabase.from("device_sessions")
                .select("device_id")
                .eq("user_id", value: userId.uuidString)
                .execute().value
            let isKnown = existing.contains { $0.device_id == deviceId }
            if !isKnown && !existing.isEmpty {
                _ = try? await supabase.from("account_security_events")
                    .insert(SecurityEventInsert(
                        user_id: userId.uuidString,
                        type: "new_device_login",
                        payload: .init(device_name: deviceName, model: model)))
                    .execute()
            }

            try await supabase.from("device_sessions")
                .upsert(SessionUpsert(
                    user_id: userId.uuidString,
                    device_id: deviceId,
                    device_name: deviceName,
                    model: model,
                    os_version: device.systemVersion,
                    app_build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
                    last_seen_at: ISODate.string(from: Date())),
                    onConflict: "user_id,device_id")
                .execute()
        } catch {
            // Best-effort heartbeat — retry on the next eligible call.
            lastHeartbeat = nil
        }
    }

    // MARK: Load

    func load() async {
        guard let userId = supabase.auth.currentSession?.user.id else { return }
        do {
            sessions = try await supabase.from("device_sessions")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("last_seen_at", ascending: false)
                .execute().value
        } catch { /* keep the previous list — next open retries */ }
    }

    // MARK: Revoke

    /// Removes another device's row from the registry (never the current
    /// device's — signing out locally is the honest way to end THIS session)
    /// and records the action as a security event.
    func revoke(_ session: DeviceSession) async {
        guard session.deviceId != currentDeviceId,
              let userId = supabase.auth.currentSession?.user.id else { return }
        do {
            try await supabase.from("device_sessions")
                .delete()
                .eq("id", value: session.id.uuidString)
                .execute()
            _ = try? await supabase.from("account_security_events")
                .insert(SecurityEventInsert(
                    user_id: userId.uuidString,
                    type: "session_revoked",
                    payload: .init(device_name: session.deviceName ?? session.deviceId,
                                   model: session.model)))
                .execute()
        } catch { /* row stays visible — the reload below shows the truth */ }
        await load()
    }
}
