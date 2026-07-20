import Foundation
import MetricKit

// MARK: - MetricKit telemetry
//
// The measured foundation any future self-healing must stand on: Apple's
// own daily metrics (launch time, hangs, memory, battery) and crash/hang
// diagnostics land here and persist as compact JSON on-device — no
// third-party SDK, no network, nothing leaves the phone. Reading them:
// the files sit in Application Support/Metrics, newest last, capped at 30.

final class MetricsMonitor: NSObject, MXMetricManagerSubscriber {
    static let shared = MetricsMonitor()
    private override init() { super.init() }

    private let capacity = 30

    func start() {
        MXMetricManager.shared.add(self)
    }

    private var directory: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("Metrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MetricKit delivers at most daily — writes are rare and tiny.
    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads { persist(payload.jsonRepresentation(), kind: "metrics") }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        // Crashes and hangs — the signal that matters most.
        for payload in payloads { persist(payload.jsonRepresentation(), kind: "diagnostics") }
    }

    private func persist(_ data: Data, kind: String) {
        guard let dir = directory else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = dir.appendingPathComponent("\(kind)-\(stamp).json")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            debugLog("[Metrics] persist failed: \(error)")
        }
        trim(in: dir)
    }

    /// Oldest files fall away past capacity — telemetry must never become
    /// the thing that fills the disk.
    private func trim(in dir: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return }
        let sorted = files.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for stale in sorted.dropLast(capacity) {
            try? FileManager.default.removeItem(at: stale)
        }
    }
}
