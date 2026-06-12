import Foundation
import Supabase

@MainActor
final class MessageService: ObservableObject {
    @Published var messages: [Message] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var unreadCount = 0

    private var realtimeChannel: RealtimeChannelV2?

    func load(propertyId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            messages = try await supabase
                .from("messages")
                .select()
                .eq("property_id", value: propertyId.uuidString)
                .order("created_at", ascending: true)
                .limit(200)
                .execute()
                .value
        } catch {
            self.error = error.localizedDescription
        }
    }

    func subscribeRealtime(propertyId: UUID) async {
        let channel = await supabase.realtimeV2.channel("messages:\(propertyId.uuidString)")
        let changes = await channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "messages",
            filter: "property_id=eq.\(propertyId.uuidString)"
        )
        await channel.subscribe()
        realtimeChannel = channel

        for await _ in changes {
            await load(propertyId: propertyId)
            unreadCount += 1
        }
    }

    func unsubscribe() async {
        if let ch = realtimeChannel {
            await supabase.realtimeV2.removeChannel(ch)
            realtimeChannel = nil
        }
    }

    func send(propertyId: UUID, senderName: String, body: String?,
              attachmentUrl: String? = nil, attachmentType: String? = nil,
              latitude: Double? = nil, longitude: Double? = nil,
              mentionedIds: [String] = []) async throws {
        guard let senderId = supabase.auth.currentSession?.user.id else { return }

        let payload = NewMessage(
            property_id: propertyId,
            sender_id: senderId,
            sender_name: senderName,
            body: body,
            attachment_url: attachmentUrl,
            attachment_type: attachmentType,
            latitude: latitude,
            longitude: longitude,
            mentioned_ids: mentionedIds
        )

        let sent: Message = try await supabase
            .from("messages")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        messages.append(sent)
    }

    func resetUnread() { unreadCount = 0 }
}
