import SwiftUI

// MARK: - Direct Message View (1-on-1)
// Loads messages from `direct_messages` table; degrades gracefully if table doesn't exist.

struct DirectMessageView: View {
    let member: FamilyMember

    @EnvironmentObject private var profileService: ProfileService
    @State private var messages: [DMMessage] = []
    @State private var input = ""
    @State private var isLoading = false
    @FocusState private var focused: Bool

    private var myName: String { profileService.profile?.preferredName ?? "Me" }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if messages.isEmpty {
                    emptyState
                } else {
                    messageList
                }
                inputBar
            }
        }
        .navigationTitle(member.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task { await loadMessages() }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(messages) { msg in
                        DMBubble(message: msg, isOwn: msg.senderName == myName)
                            .id(msg.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onAppear {
                if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle().fill(member.swiftColor.opacity(0.12)).frame(width: 80, height: 80)
                Text(member.initials)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(member.swiftColor)
            }
            Text("Message \(member.name)")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
            Text("This is the beginning of your direct message conversation.")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Message \(member.name)…", text: $input, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .lineLimit(1...4)
                .focused($focused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .liquidGlass(cornerRadius: 20)

            Button { Task { await sendMessage() } } label: {
                ZStack {
                    Circle()
                        .fill(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              ? Color.primary.opacity(0.12) : Color.blue)
                        .frame(width: 36, height: 36)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                         ? Color.primary.opacity(0.3) : .white)
                }
            }
            .buttonStyle(.plain)
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    // MARK: - Data

    private func loadMessages() async {
        isLoading = true
        defer { isLoading = false }
        // Graceful degradation — if table doesn't exist, just show empty state
        do {
            let rows: [DMMessageRow] = try await supabase
                .from("direct_messages")
                .select()
                .or("sender_name.eq.\(myName),sender_name.eq.\(member.name)")
                .order("created_at")
                .execute()
                .value
            messages = rows.map { DMMessage(id: $0.id, senderName: $0.senderName, content: $0.content, timestamp: Date()) }
        } catch {
            messages = []
        }
    }

    private func sendMessage() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        let msg = DMMessage(id: UUID(), senderName: myName, content: text, timestamp: Date())
        messages.append(msg)
        do {
            try await supabase
                .from("direct_messages")
                .insert(["sender_name": myName, "recipient_name": member.name, "content": text])
                .execute()
        } catch { }
    }
}

// MARK: - DM Bubble

private struct DMBubble: View {
    let message: DMMessage
    let isOwn: Bool

    var body: some View {
        HStack {
            if isOwn { Spacer(minLength: 60) }
            Text(message.content)
                .font(.system(size: 15))
                .foregroundStyle(isOwn ? .white : .primary)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(isOwn ? Color.blue.opacity(0.8) : Color.primary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            if !isOwn { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Models

struct DMMessage: Identifiable {
    let id: UUID
    let senderName: String
    let content: String
    let timestamp: Date
}

private struct DMMessageRow: Decodable {
    let id: UUID
    let senderName: String
    let content: String

    enum CodingKeys: String, CodingKey {
        case id, content
        case senderName = "sender_name"
    }
}
