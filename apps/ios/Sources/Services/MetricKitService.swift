import Foundation
import MetricKit
import Supabase

// MARK: - MetricKit → Supabase telemetry
//
// The upload half of the app's telemetry: MetricsMonitor (AppDelegate)
// already persists MetricKit payloads on-device; this second subscriber
// ships each payload to the `app_metrics` table so launch-time, hang,
// memory and crash regressions are visible across the fleet without a
// device in hand. Strictly fire-and-forget: every failure path drops the
// payload silently — telemetry must never block, error or crash the app.

final class MetricKitService: NSObject, MXMetricManagerSubscriber {
    static let shared = MetricKitService()
    private override init() { super.init() }

    private var started = false

    /// Idempotent: MainTabView's startup beat calls this once per sign-in.
    func start() {
        guard !started else { return }
        started = true
        MXMetricManager.shared.add(self)
    }

    // MARK: MXMetricManagerSubscriber
    //
    // MetricKit delivers at most daily, on a background queue — uploads are
    // rare, small, and never touch the main actor.

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads { upload(payload.jsonRepresentation(), kind: "metric") }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        // Crashes and hangs — the signal that matters most.
        for payload in payloads { upload(payload.jsonRepresentation(), kind: "diagnostic") }
    }

    // MARK: Upload

    /// Anything larger is not worth a mobile upload — telemetry must never
    /// cost the user real bandwidth (some diagnostic payloads carry deep
    /// call trees).
    private static let maxPayloadBytes = 200_000

    private struct Row: Encodable {
        let property_id: String?
        let user_id: String
        let kind: String
        let app_version: String
        let os_version: String
        let device_model: String
        let payload: JSONObject
    }

    private func upload(_ data: Data, kind: String) {
        // No session, no owner for the row (RLS would refuse it anyway): drop.
        guard let userId = supabase.auth.currentSession?.user.id else { return }
        guard data.count <= Self.maxPayloadBytes,
              let object = try? JSONDecoder().decode(JSONObject.self, from: data)
        else { return }

        let os = ProcessInfo.processInfo.operatingSystemVersion
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let osVersion = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        let model = Self.deviceModel

        Task.detached(priority: .utility) {
            // The active property lives on the main actor — one cheap hop to
            // read it, then the insert stays off the main thread.
            let propertyId = await MainActor.run { PropertyService.activePropertyId?.uuidString }
            let row = Row(
                property_id: propertyId,
                user_id: userId.uuidString,
                kind: kind,
                app_version: appVersion,
                os_version: osVersion,
                device_model: model,
                payload: object)
            // Fire-and-forget: a failed insert is a lost data point, never
            // a user-visible problem.
            _ = try? await supabase.from("app_metrics").insert(row).execute()
        }
    }

    /// The hardware identifier ("iPhone16,2"), not UIDevice's generic
    /// "iPhone" — the only form that lets a regression be pinned to a chip.
    private static let deviceModel: String = {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: info.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }()
}
