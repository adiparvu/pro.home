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
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, body, latitude, longitude
        case propertyId    = "property_id"
        case senderId      = "sender_id"
        case senderName    = "sender_name"
        case attachmentUrl = "attachment_url"
        case attachmentType = "attachment_type"
        case mentionedIds  = "mentioned_ids"
        case createdAt     = "created_at"
    }

    var timeDisplay: String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        let d = f.date(from: createdAt) ?? f2.date(from: createdAt) ?? Date()
        let out = DateFormatter()
        out.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : "dd MMM HH:mm"
        return out.string(from: d)
    }

    var isLocationMessage: Bool { attachmentType == "location" }
    var isImageMessage: Bool    { attachmentType == "image" }
    var isFileMessage: Bool     { attachmentType == "file" }
    var isStickerMessage: Bool  { attachmentType == "sticker" }
    var isAudioMessage: Bool    { attachmentType == "audio" }
}

struct NewMessage: Encodable {
    let property_id: UUID?
    let sender_id: UUID
    let sender_name: String
    let body: String?
    let attachment_url: String?
    let attachment_type: String?
    let latitude: Double?
    let longitude: Double?
    let mentioned_ids: [String]
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
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        let d = f.date(from: readAt) ?? f2.date(from: readAt) ?? Date()
        let out = DateFormatter()
        out.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : "dd MMM HH:mm"
        return out.string(from: d)
    }
}
