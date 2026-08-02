import Foundation

struct Message: Identifiable, Codable {
    let id: UUID
    var propertyId: UUID?
    var senderId: UUID?
    var senderName: String
    var body: String?
    var attachmentUrl: String?
    var attachmentType: String?   // "image" | "file" | "location"
    var latitude: Double?
    var longitude: Double?
    var mentionedIds: [String]
    var replyTo: UUID?
    var pinned: Bool?
    var isMarked: Bool?
    var editedAt: String?
    var deletedForAll: Bool?
    /// Communities: the chat group this message belongs to. nil = property-wide
    /// main group. Decode-only since G4 — rows written by older builds carry
    /// it; new writes put the scope on the conversation instead.
    var groupId: UUID?
    /// Disappearing messages: when set, the server sweep deletes this row after it.
    var expiresAt: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, body, latitude, longitude, pinned
        case groupId       = "group_id"
        case expiresAt     = "expires_at"
        case propertyId    = "property_id"
        case senderId      = "sender_id"
        case senderName    = "sender_name"
        case attachmentUrl = "attachment_url"
        case attachmentType = "attachment_type"
        case mentionedIds  = "mentioned_ids"
        case replyTo       = "reply_to"
        case isMarked      = "is_marked"
        case editedAt      = "edited_at"
        case deletedForAll = "deleted_for_all"
        case createdAt     = "created_at"
    }

    var timeDisplay: String {
        let d = ISODate.date(from: createdAt) ?? Date()
        // Only the time, like WhatsApp — the date is shown by the day separators.
        return ISODate.timeOnly.string(from: d)
    }

    var date: Date? { ISODate.date(from: createdAt) }

    var isLocationMessage: Bool { attachmentType == "location" }
    // Live Photos ride the image pipeline (photo runs, previews, gallery);
    // isLiveMessage adds the badge and the press-to-play viewer on top.
    var isImageMessage: Bool    { attachmentType == "image" || attachmentType == "live" }
    var isLiveMessage: Bool     { attachmentType == "live" }
    var isVideoMessage: Bool    { attachmentType == "video" }
    var isFileMessage: Bool     { attachmentType == "file" }
    var isStickerMessage: Bool  { attachmentType == "sticker" }
    var isAudioMessage: Bool    { attachmentType == "audio" }
    var isPollMessage: Bool     { attachmentType == "poll" }
    var isEventMessage: Bool    { attachmentType == "event" }
}

struct NewMessage: Encodable {
    // Client-generated so the row can be shown optimistically before the
    // server acknowledges it (realtime echoes dedup on this id).
    var id: UUID? = nil
    let property_id: UUID?
    let sender_id: UUID
    let sender_name: String
    let body: String?
    let attachment_url: String?
    let attachment_type: String?
    let latitude: Double?
    let longitude: Double?
    let mentioned_ids: [String]
    var reply_to: UUID? = nil
    /// G4: the conversation IS the scope. Context-free writers (Siri intents)
    /// may omit it — the server stamps it BEFORE INSERT.
    var conversation_id: UUID? = nil
    var expires_at: String? = nil
}

// MARK: - Emoji reactions

struct MessageReaction: Identifiable, Codable {
    let id: UUID
    let messageId: UUID
    let propertyId: UUID?
    let userId: UUID
    let reactorName: String
    let emoji: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, emoji
        case messageId   = "message_id"
        case propertyId  = "property_id"
        case userId      = "user_id"
        case reactorName = "reactor_name"
        case createdAt   = "created_at"
    }
}

// MARK: - Read receipts

struct MessageRead: Identifiable, Codable, Hashable {
    let id: UUID
    var messageId: UUID
    var propertyId: UUID?
    var userId: UUID?
    var readerName: String
    var readAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case messageId  = "message_id"
        case propertyId = "property_id"
        case userId     = "user_id"
        case readerName = "reader_name"
        case readAt     = "read_at"
    }

    var readTimeDisplay: String {
        let d = ISODate.date(from: readAt) ?? Date()
        let out = Calendar.current.isDateInToday(d) ? ISODate.timeOnly : AppDateDisplay.dayMonthTime
        return out.string(from: d)
    }
}

struct MessageDelivery: Identifiable, Codable, Hashable {
    let id: UUID
    var messageId: UUID
    var propertyId: UUID?
    var userId: UUID?
    var delivererName: String
    var deliveredAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case messageId    = "message_id"
        case propertyId   = "property_id"
        case userId       = "user_id"
        case delivererName = "deliverer_name"
        case deliveredAt  = "delivered_at"
    }
}
