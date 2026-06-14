import SwiftUI

struct ARIAView: View {
    var onDismiss: (() -> Void)? = nil

    @EnvironmentObject private var propertyService: PropertyService
    @EnvironmentObject private var familyService: FamilyService
    @EnvironmentObject private var profileService: ProfileService
    @AppStorage("prvio.avatarRingColorName") private var avatarRingColorName: String = "blue"
    @State private var messages: [ARIAMessage] = []
    @State private var input = ""
    @State private var isThinking = false
    @State private var isLoadingHistory = true
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                ariaHeader
                messageList
                inputBar
            }
        }
        .task { await loadHistory() }
    }

    // MARK: - Header

    private var ariaHeader: some View {
        HStack {
            if let onDismiss {
                Button {
                    HapticFeedback.selection()
                    onDismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                }
            }
            VStack(alignment: onDismiss != nil ? .leading : .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("ARIA")
                        .font(.title2.weight(.bold))
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.yellow.opacity(0.85))
                }
                Text("AI Property Assistant")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 10) {
                MemberAvatarStack(
                    members: familyService.members,
                    ownerAvatarUrl: profileService.profile?.avatarUrl,
                    ownerInitial: String((profileService.profile?.preferredName ?? "U").prefix(1)).uppercased(),
                    ringColor: avatarRingColor(for: avatarRingColorName)
                )
                Button {
                    withAnimation { messages = ARIAMessage.welcome }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if isLoadingHistory {
                    VStack { Spacer(minLength: 40); ProgressView().tint(.white); Spacer() }
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { msg in
                            ARIAMessageBubble(message: msg)
                                .id(msg.id)
                        }
                        if isThinking {
                            ThinkingBubble().id("thinking")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .padding(.bottom, 20)
                }
            }
            .onChange(of: messages.count) {
                withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
            }
            .onChange(of: isThinking) {
                if isThinking { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
            }
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about your property...", text: $input, axis: .vertical)
                .font(.body)
                .lineLimit(1...4)
                .focused($focused)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                )

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 40, height: 40)
                    .background(.white, in: Circle())
            }
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isThinking)
            .opacity(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.5)
        }
    }

    // MARK: - Logic

    private func loadHistory() async {
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        do {
            let history: [ARIADBMessage] = try await supabase
                .from("aria_messages")
                .select("id, role, content, created_at")
                .order("created_at", ascending: true)
                .limit(40)
                .execute()
                .value
            if history.isEmpty {
                messages = ARIAMessage.welcome
            } else {
                messages = history.map { ARIAMessage(
                    role: $0.role == "user" ? .user : .aria,
                    content: $0.content
                )}
            }
        } catch {
            messages = ARIAMessage.welcome
        }
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        messages.append(ARIAMessage(role: .user, content: text))
        isThinking = true

        Task {
            do {
                let propId = propertyService.primary?.id.uuidString
                struct ARIAChatPayload: Encodable {
                    let message: String
                    let property_id: String?
                }
                let payload = ARIAChatPayload(message: text, property_id: propId)
                struct ARIAResponse: Decodable { let reply: String?; let error: String? }
                let decoded: ARIAResponse = try await supabase.functions
                    .invoke("aria-chat", options: .init(body: payload))

                isThinking = false
                messages.append(ARIAMessage(
                    role: .aria,
                    content: decoded.reply ?? decoded.error ?? "Something went wrong. Try again."
                ))
            } catch {
                isThinking = false
                messages.append(ARIAMessage(role: .aria, content: "I'm having trouble connecting. Please try again."))
            }
        }
    }
}

// MARK: - Message Bubble

private struct ARIAMessageBubble: View {
    let message: ARIAMessage
    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 48) }

            if !isUser {
                ZStack {
                    Circle().fill(.ultraThinMaterial).frame(width: 28, height: 28)
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.7))
                }
            }

            Text(LocalizedStringKey(message.content))
                .font(.body)
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    isUser ? AnyShapeStyle(Color.primary.opacity(0.12)) : AnyShapeStyle(.ultraThinMaterial),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(isUser ? 0 : 0.08), lineWidth: 0.5)
                )

            if !isUser { Spacer(minLength: 48) }
        }
    }
}

// MARK: - Thinking Bubble

private struct ThinkingBubble: View {
    @State private var phase = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ZStack {
                Circle().fill(.ultraThinMaterial).frame(width: 28, height: 28)
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.7))
            }
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.primary.opacity(0.5))
                        .frame(width: 6, height: 6)
                        .scaleEffect(phase == i ? 1.3 : 0.8)
                        .animation(.easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.15), value: phase)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Spacer(minLength: 48)
        }
        .onAppear { phase = 1 }
    }
}

// MARK: - Models

struct ARIAMessage: Identifiable {
    let id = UUID()
    enum Role { case user, aria }
    let role: Role
    let content: String

    static let welcome = [
        ARIAMessage(role: .aria, content: "Hi! I'm ARIA, your AI property assistant powered by Claude. I can see your tasks, finances, and property data. Ask me anything!")
    ]
}

private struct ARIADBMessage: Decodable {
    let id: UUID
    let role: String
    let content: String
    let createdAt: String
    enum CodingKeys: String, CodingKey {
        case id, role, content; case createdAt = "created_at"
    }
}
