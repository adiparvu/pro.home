import Foundation
import Supabase

// MARK: - DirectMessage model

struct DirectMessage: Identifiable, Codable {
    let id: UUID
    let senderName: String
    let recipientName: String
    let body: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, body
        case senderName    = "sender_name"
        case recipientName = "recipient_name"
        case createdAt     = "created_at"
    }

    var timeDisplay: String {
        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
        let d = f1.date(from: createdAt) ?? f2.date(from: createdAt) ?? Date()
        let out = DateFormatter()
        out.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : "dd MMM HH:mm"
        return out.string(from: d)
    }

    var date: Date? {
        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
        return f1.date(from: createdAt) ?? f2.date(from: createdAt)
    }
}

// MARK: - DirectMessageService

@MainActor
final class DirectMessageService: ObservableObject {
    @Published var dms: [DirectMessage] = []
    @Published var isLoading = false

    private var channel: RealtimeChannelV2?

    // MARK: - Queries

    func messages(with partner: String, myName: String) -> [DirectMessage] {
        dms.filter {
            ($0.senderName == partner && $0.recipientName == myName) ||
            ($0.senderName == myName   && $0.recipientName == partner)
        }
    }

    func lastMessage(with partner: String, myName: String) -> DirectMessage? {
        messages(with: partner, myName: myName).max { $0.createdAt < $1.createdAt }
    }

    func unreadCount(from partner: String, myName: String) -> Int {
        let lastSeen = lastSeenDate(for: partner)
        return dms.filter {
            $0.senderName == partner &&
            $0.recipientName == myName &&
            ($0.date ?? .distantPast) > lastSeen
        }.count
    }

    func markRead(partner: String) {
        UserDefaults.standard.set(Date(), forKey: "dm.lastseen.\(partner)")
        objectWillChange.send()
    }

    // MARK: - Persistence

    func load(propertyId: UUID, myName: String) async {
        isLoading = true
        defer { isLoading = false }
        guard !myName.isEmpty else { return }
        do {
            dms = try await supabase
                .from("direct_messages")
                .select()
                .eq("property_id", value: propertyId.uuidString)
                .or("sender_name.eq.\(myName),recipient_name.eq.\(myName)")
                .order("created_at", ascending: true)
                .limit(1000)
                .execute()
                .value
        } catch {
            // table may not exist yet — fail silently
        }
    }

    func subscribeRealtime(propertyId: UUID, myName: String) async {
        let ch = await supabase.realtimeV2.channel("direct_messages:\(propertyId.uuidString)")
        let changes = await ch.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "direct_messages",
            filter: "property_id=eq.\(propertyId.uuidString)"
        )
        await ch.subscribe()
        channel = ch

        for await _ in changes {
            await load(propertyId: propertyId, myName: myName)
        }
    }

    func unsubscribe() async {
        if let ch = channel {
            await supabase.realtimeV2.removeChannel(ch)
            channel = nil
        }
    }

    func deleteMessage(id: UUID) async {
        do {
            try await supabase
                .from("direct_messages")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
            dms.removeAll { $0.id == id }
        } catch {
#if DEBUG
            print("[DM] delete error: \(error)")
#endif
        }
    }

    // MARK: - Private helpers

    private func lastSeenDate(for partner: String) -> Date {
        UserDefaults.standard.object(forKey: "dm.lastseen.\(partner)") as? Date ?? .distantPast
    }
}
