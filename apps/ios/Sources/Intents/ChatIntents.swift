import AppIntents
import Foundation

struct OpenChatIntent: AppIntent {
    static var title: LocalizedStringResource = "Chat"
    static var description = IntentDescription("Open the chat in PRVIO")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        SharedDataStore.setIntentFlag("prvio.intent.showChat")
        return .result()
    }
}

// MARK: - Send a message into the house chat (Shortcuts / automations)
//
// The cross-app story for apps on the SAME phone: any Shortcuts automation
// ("when I leave work…", "when app X sends me Y…") can post into the chat
// without opening PRVIO. Runs in the app's process, so the signed-in Supabase
// session is available.

struct SendChatMessageIntent: AppIntent {
    static var title: LocalizedStringResource = "Send message to chat"
    static var description = IntentDescription("Sends a message into the PRVIO house chat")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Message", description: "The text to send")
    var message: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return .result(dialog: "Nothing to send.")
        }
        guard let propertyId = SharedDataStore.contextPropertyId(),
              let senderId = supabase.auth.currentSession?.user.id else {
            return .result(dialog: "Open PRVIO once to finish setup, then try again.")
        }
        let sender = SharedDataStore.contextMyName() ?? String(localized: "Me")

        let payload = NewMessage(
            property_id: propertyId,
            sender_id: senderId,
            sender_name: sender,
            body: text,
            attachment_url: nil,
            attachment_type: nil,
            latitude: nil,
            longitude: nil,
            mentioned_ids: []
        )
        try await supabase.from("messages").insert(payload).execute()
        return .result(dialog: "Sent to the house chat.")
    }
}
