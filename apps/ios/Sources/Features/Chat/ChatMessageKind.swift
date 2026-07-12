import Foundation

// MARK: - Normalized message kind (Chat unification P2)
//
// The two chat engines encode media differently: the group `Message` carries an
// `attachment_type` column, while the DM `DirectMessage` encodes media as inline
// body markers. Every place that must answer "what *kind* of message is this?"
// — reply quotes, pinned banners, conversation-list previews — reimplemented
// that classification per model, and the group side even hardcoded English
// labels ("📷 Photo") instead of the localized `convo_prev_*` vocabulary the
// conversation list already uses.
//
// `ChatMessageKind` is the one normalized vocabulary both models project onto,
// and the single source of the localized preview label. It is the seed of the
// unified `ChatMessage.kind` the later phases converge on.
enum ChatMessageKind: Equatable {
    case text
    case image
    case video
    case audio
    case file
    case location
    case sticker
    case poll
    case event
    case taskShare
    case contactShare

    /// A short, localized, emoji-prefixed label for a non-text message shown in
    /// a reply quote or pinned banner. `.text` has no fixed label — callers show
    /// the (subject-stripped) body instead — so it returns nil.
    ///
    /// These are the canonical `convo_prev_*` strings the conversation list
    /// already uses, so a Romanian user never sees an English preview.
    var previewLabel: String? {
        switch self {
        case .text:         return nil
        case .image:        return String(localized: "convo_prev_image")
        case .video:        return String(localized: "convo_prev_video")
        case .audio:        return String(localized: "convo_prev_audio")
        case .file:         return String(localized: "convo_prev_file")
        case .location:     return String(localized: "convo_prev_location")
        case .sticker:      return String(localized: "convo_prev_sticker")
        case .poll:         return String(localized: "convo_prev_poll")
        case .event:        return String(localized: "convo_prev_event")
        case .taskShare:    return String(localized: "convo_prev_task")
        case .contactShare: return String(localized: "convo_prev_contact")
        }
    }
}

// MARK: - DM snippet authority

extension DirectMessage {
    /// The one-line, marker-free preview of this DM — reply quotes, the
    /// composer reply banner, pinned banner, message details and the starred
    /// list all show this. Rich payloads (location/sticker/event/file) resolve
    /// through `DMRich` and media markers through `ChatMedia`, so a structured
    /// body never leaks its raw marker/JSON; a subject-bearing text body reads
    /// "subject — text". Four per-surface copies of this chain used to drift —
    /// two of them skipped the rich/contact checks entirely and showed the raw
    /// payload.
    var previewSnippet: String {
        if deletedForAll == true { return String(localized: "This message was deleted") }
        if let rich = DMRich.snippet(for: body) { return rich }
        if isContactShare { return String(localized: "convo_prev_contact") }
        switch ChatMedia.dmBodyKind(body) {
        case .audio: return String(localized: "dm_prev_audio")
        case .image: return String(localized: "dm_prev_photo")
        case .video: return String(localized: "dm_prev_video")
        case .text:  return MessageSubject.strip(body)
        }
    }
}

// MARK: - Group message classification

extension Message {
    /// This group message's normalized kind. Structured shares (poll / event /
    /// task / contact) are checked before the raw `attachment_type` so a poll
    /// never previews its JSON payload; the remaining attachment types map
    /// directly. The order mirrors the historical `MessageBubble.replyPreview`
    /// exactly, so classification is unchanged.
    var chatKind: ChatMessageKind {
        if isPollMessage     { return .poll }
        if isEventMessage    { return .event }
        if isTaskShare       { return .taskShare }
        if isContactShare    { return .contactShare }
        if isAudioMessage    { return .audio }
        if isImageMessage    { return .image }
        if isVideoMessage    { return .video }
        if isLocationMessage { return .location }
        if isStickerMessage  { return .sticker }
        if isFileMessage     { return .file }
        return .text
    }
}
