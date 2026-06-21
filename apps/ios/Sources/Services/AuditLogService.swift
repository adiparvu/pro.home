import Foundation
import UIKit

final class AuditLogService {
    static let shared = AuditLogService()
    private init() {}

    struct AuditEvent: Codable, Identifiable {
        let id: UUID
        let type: String
        let description: String
        let timestamp: Date
        let deviceName: String

        static func record(_ type: String, _ description: String) {
            AuditLogService.shared.add(AuditEvent(
                id: UUID(),
                type: type,
                description: description,
                timestamp: Date(),
                deviceName: UIDevice.current.name
            ))
        }
    }

    private let key = "prvio.auditLog"
    private let maxEvents = 100

    var events: [AuditEvent] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([AuditEvent].self, from: data)
        else { return [] }
        return decoded
    }

    func add(_ event: AuditEvent) {
        var current = events
        current.insert(event, at: 0)
        if current.count > maxEvents { current = Array(current.prefix(maxEvents)) }
        if let data = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
