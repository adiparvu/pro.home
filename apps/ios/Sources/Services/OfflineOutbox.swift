import Foundation
import Network
import Observation

// MARK: - Offline outbox
// Persists messages that failed to send (or were composed offline) and
// automatically retries them when connectivity returns. Additive: the normal
// online send path is unchanged; this only catches the failure case.

struct PendingMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let propertyId: UUID
    let senderName: String
    let recipientName: String?     // nil = group chat; set = DM recipient
    /// family_members.id of the DM recipient. Required for the row to be
    /// visible to the recipient under id-based RLS; nil for group messages.
    let recipientMemberId: UUID?
    let body: String?
    let attachmentUrl: String?
    let attachmentType: String?
    let mentionedIds: [String]
    let replyTo: UUID?
    let createdAt: Date

    init(id: UUID = UUID(), propertyId: UUID, senderName: String, recipientName: String? = nil,
         recipientMemberId: UUID? = nil,
         body: String?, attachmentUrl: String? = nil, attachmentType: String? = nil,
         mentionedIds: [String] = [], replyTo: UUID? = nil, createdAt: Date = Date()) {
        self.id = id; self.propertyId = propertyId; self.senderName = senderName
        self.recipientName = recipientName
        self.recipientMemberId = recipientMemberId
        self.body = body; self.attachmentUrl = attachmentUrl; self.attachmentType = attachmentType
        self.mentionedIds = mentionedIds; self.replyTo = replyTo; self.createdAt = createdAt
    }
}

@MainActor
@Observable
final class OfflineOutbox {
    private(set) var pending: [PendingMessage] = []
    private(set) var isOnline = true

    private let monitor = NWPathMonitor()
    private var flushing = false
    private let filename: String

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(filename)
    }

    init(filename: String = "chat_outbox.json") {
        self.filename = filename
        load()
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
    }

    func pending(for propertyId: UUID) -> [PendingMessage] {
        pending.filter { $0.propertyId == propertyId }.sorted { $0.createdAt < $1.createdAt }
    }

    func enqueue(_ message: PendingMessage) {
        pending.append(message)
        save()
    }

    func remove(_ id: UUID) {
        pending.removeAll { $0.id == id }
        save()
    }

    /// Attempts to send every queued message. `send` returns true on success.
    func flush(_ send: @escaping (PendingMessage) async -> Bool) async {
        guard !flushing, isOnline, !pending.isEmpty else { return }
        flushing = true
        defer { flushing = false }
        for message in pending {
            if await send(message) { remove(message.id) }
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([PendingMessage].self, from: data) else { return }
        pending = items
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
