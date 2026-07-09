import Foundation
import Network
import Observation

// MARK: - Send state + timeout (shared by every chat surface)

/// The delivery state of a message the moment it is shown. Rendered on the
/// optimistic / queued row so the reader always knows whether a message is in
/// flight (clock), queued offline (clock), or failed and awaiting a retry
/// (exclamation + "tap to retry"). `.sent` rows leave the outbox, so the UI
/// never has to draw that case.
enum ChatSendState: String, Codable {
    case sending, sent, failed
}

/// The concrete kind of a queued message, kept so the offline row can show a
/// faithful preview ("📷 Photo", "📊 Poll") instead of a raw storage path or
/// encoded JSON body while the message waits to be retried.
enum PendingKind: String, Codable {
    case text, image, video, audio, file, location, sticker, poll, event, contact
}

/// Minimal decodable for realtime DELETE payloads: under the default replica
/// identity a delete's `oldRecord` carries only the primary key, so a full row
/// decode would fail — we only need the id to drop the row locally.
struct RealtimeRowID: Decodable { let id: UUID }

/// Thrown when a chat network insert exceeds its deadline. A hung insert MUST
/// resolve to a recoverable failure the outbox can retry — never a permanent
/// fake "sent" that leaves the reader believing a stalled message was delivered.
struct ChatSendTimeout: Error {}

/// Races an async operation against a wall-clock deadline. On timeout the
/// operation task is cancelled and `ChatSendTimeout` is thrown, converting a
/// stalled insert into a failure the send pipeline routes to the outbox.
func withChatTimeout<T: Sendable>(
    seconds: Double = 15,
    _ operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw ChatSendTimeout()
        }
        guard let result = try await group.next() else { throw ChatSendTimeout() }
        group.cancelAll()
        return result
    }
}

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
    /// Location payloads (attachmentType == "location") carry their coordinates
    /// here so a queued location survives offline and re-sends intact.
    let latitude: Double?
    let longitude: Double?
    /// What kind of message this is, purely for the offline preview row.
    let kind: PendingKind
    let mentionedIds: [String]
    let replyTo: UUID?
    let createdAt: Date
    /// Live send state, mutated by the outbox flush so the view can distinguish
    /// "still trying" from "failed, tap to retry".
    var state: ChatSendState

    init(id: UUID = UUID(), propertyId: UUID, senderName: String, recipientName: String? = nil,
         recipientMemberId: UUID? = nil,
         body: String?, attachmentUrl: String? = nil, attachmentType: String? = nil,
         latitude: Double? = nil, longitude: Double? = nil,
         kind: PendingKind = .text,
         mentionedIds: [String] = [], replyTo: UUID? = nil, createdAt: Date = Date(),
         state: ChatSendState = .sending) {
        self.id = id; self.propertyId = propertyId; self.senderName = senderName
        self.recipientName = recipientName
        self.recipientMemberId = recipientMemberId
        self.body = body; self.attachmentUrl = attachmentUrl; self.attachmentType = attachmentType
        self.latitude = latitude; self.longitude = longitude
        self.kind = kind
        self.mentionedIds = mentionedIds; self.replyTo = replyTo; self.createdAt = createdAt
        self.state = state
    }

    enum CodingKeys: String, CodingKey {
        case id, propertyId, senderName, recipientName, recipientMemberId
        case body, attachmentUrl, attachmentType, latitude, longitude, kind
        case mentionedIds, replyTo, createdAt, state
    }

    // Custom decode so outbox files written before the new fields existed still
    // load: every field added since the first release is decoded leniently and
    // defaulted, rather than failing the whole persisted queue.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        propertyId = try c.decode(UUID.self, forKey: .propertyId)
        senderName = try c.decode(String.self, forKey: .senderName)
        recipientName = try c.decodeIfPresent(String.self, forKey: .recipientName)
        recipientMemberId = try c.decodeIfPresent(UUID.self, forKey: .recipientMemberId)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        attachmentUrl = try c.decodeIfPresent(String.self, forKey: .attachmentUrl)
        attachmentType = try c.decodeIfPresent(String.self, forKey: .attachmentType)
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        kind = (try c.decodeIfPresent(PendingKind.self, forKey: .kind)) ?? .text
        mentionedIds = (try c.decodeIfPresent([String].self, forKey: .mentionedIds)) ?? []
        replyTo = try c.decodeIfPresent(UUID.self, forKey: .replyTo)
        createdAt = (try c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
        state = (try c.decodeIfPresent(ChatSendState.self, forKey: .state)) ?? .sending
    }

    /// A faithful one-line preview for the offline row — never the raw storage
    /// path or encoded JSON. Mirrors the group chat's pinned-snippet style.
    var previewText: String {
        switch kind {
        case .image:    return "📷 Photo"
        case .video:    return "🎥 Video"
        case .audio:    return "🎤 Voice message"
        case .file:     return body ?? "📎 File"
        case .location: return "📍 Location"
        case .sticker:  return "😀 Sticker"
        case .poll:     return "📊 Poll"
        case .event:    return "📅 Event"
        case .contact:  return "👤 Contact"
        case .text:     return body ?? ""
        }
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

    deinit {
        // Without this, every discarded instance (SwiftUI re-evaluates
        // @State default expressions) left a live dispatch source behind.
        monitor.cancel()
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
    /// Each row is marked `.sending` for the attempt and, on failure, `.failed`
    /// so the view can surface a "tap to retry" affordance without guessing.
    func flush(_ send: @escaping (PendingMessage) async -> Bool) async {
        guard !flushing, isOnline, !pending.isEmpty else { return }
        flushing = true
        defer { flushing = false }
        // Snapshot ids: `pending` mutates as rows are removed mid-loop.
        let ids = pending.map(\.id)
        for id in ids {
            guard let message = pending.first(where: { $0.id == id }) else { continue }
            setState(id, .sending)
            if await send(message) { remove(id) }
            else { setState(id, .failed) }
        }
    }

    /// Updates a queued row's send state in place (persisted so a relaunch
    /// still shows the last known state).
    private func setState(_ id: UUID, _ state: ChatSendState) {
        guard let i = pending.firstIndex(where: { $0.id == id }), pending[i].state != state else { return }
        pending[i].state = state
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([PendingMessage].self, from: data) else { return }
        pending = items
    }

    private func save() {
        // The in-memory copy stays authoritative either way; a failed write
        // must at least say so — these are exactly the messages this class
        // exists to protect.
        do {
            let data = try JSONEncoder().encode(pending)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            debugLog("[Outbox] persist failed: \(error)")
        }
    }
}
