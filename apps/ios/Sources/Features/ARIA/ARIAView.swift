import SwiftUI

struct ARIAView: View {
    var onDismiss: (() -> Void)? = nil

    @EnvironmentObject private var propertyService: PropertyService
    @EnvironmentObject private var familyService: FamilyService
    @EnvironmentObject private var profileService: ProfileService
    @EnvironmentObject private var taskService: TaskService
    @AppStorage("prvio.avatarRingColorName") private var avatarRingColorName: String = "blue"
    @AppStorage("prvio.aria.customName") private var assistantName: String = "ARIA"
    @AppStorage("prvio.aria.avatarIcon") private var avatarIcon: String = "sparkles"
    @State private var messages: [ARIAMessage] = []
    @State private var input = ""
    @State private var isThinking = false
    @State private var isLoadingHistory = true
    @State private var showSettings = false
    @FocusState private var focused: Bool
    @AppStorage("prvio.voiceInput") private var voiceInputEnabled: Bool = true
    @StateObject private var speech = SpeechRecognizer()

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                messageList
                inputBar
            }
        }
        .navigationTitle(assistantName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    HapticFeedback.selection()
                    onDismiss?()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                MemberAvatarStack(
                    members: familyService.members,
                    ownerAvatarUrl: profileService.profile?.avatarUrl,
                    ownerInitial: String((profileService.profile?.preferredName ?? "U").prefix(1)).uppercased(),
                    ringColor: avatarRingColor(for: avatarRingColorName)
                )
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation { messages = ARIAMessage.welcome }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { ARIASettingsView() } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
        .task { await loadHistory() }
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
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) {
                withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
            }
            .onChange(of: isThinking) {
                if isThinking { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
            }
        }
    }

    // MARK: - Input bar — matches mockup: text field + [mic|waveform|cloud] + glowing orb

    private var inputBar: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                // Text field row
                HStack(spacing: 10) {
                    TextField("Ask about your property...", text: $input, axis: .vertical)
                        .font(.system(size: 15))
                        .lineLimit(1...5)
                        .focused($focused)
                        .onChange(of: speech.transcript) { _, t in
                            if !t.isEmpty { input = t }
                        }
                    if !input.isEmpty {
                        Button {
                            input = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.primary.opacity(0.35))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                // Icon buttons + orb row
                HStack(spacing: 0) {
                    // Left: 3 icon buttons matching mockup
                    HStack(spacing: 16) {
                        // Mic button
                        Button {
                            HapticFeedback.impact(.light)
                            if speech.isListening {
                                speech.stop()
                            } else {
                                focused = false
                                Task { await speech.startListening() }
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(speech.isListening
                                        ? Color.red.opacity(0.2)
                                        : Color.primary.opacity(0.1))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(speech.isListening
                                        ? .red
                                        : Color(red: 0.55, green: 0.70, blue: 1.0))
                                    .symbolEffect(.pulse, isActive: speech.isListening)
                            }
                        }
                        .buttonStyle(.plain)

                        // Waveform / equalizer button
                        Button {
                            HapticFeedback.impact(.light)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.primary.opacity(0.1))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "waveform")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.55, green: 0.70, blue: 1.0))
                            }
                        }
                        .buttonStyle(.plain)

                        // Cloud / AI mode button
                        Button {
                            HapticFeedback.impact(.light)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.primary.opacity(0.1))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "icloud")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.55, green: 0.70, blue: 1.0))
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    // Right: large glowing blue orb (send / stop)
                    Button {
                        speech.stop()
                        if isThinking { isThinking = false } else { send() }
                    } label: {
                        ZStack {
                            // Outer glow ring
                            Circle()
                                .fill(Color(red: 0.25, green: 0.45, blue: 0.95).opacity(0.25))
                                .frame(width: 66, height: 66)
                                .blur(radius: 10)

                            // Mid glow
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            Color(red: 0.40, green: 0.60, blue: 1.0).opacity(0.5),
                                            Color.clear
                                        ],
                                        center: .center, startRadius: 0, endRadius: 32
                                    )
                                )
                                .frame(width: 60, height: 60)

                            // Core orb
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.40, green: 0.62, blue: 1.0),
                                            Color(red: 0.30, green: 0.38, blue: 0.98)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 52, height: 52)
                                .shadow(color: Color(red: 0.35, green: 0.50, blue: 1.0).opacity(0.8), radius: 14, y: 3)

                            // Inner highlight
                            Circle()
                                .fill(Color.white.opacity(0.18))
                                .frame(width: 18, height: 18)
                                .offset(x: -8, y: -8)
                                .blur(radius: 4)

                            if isThinking {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(.white)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isThinking)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Divider().opacity(0.15)
            }
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
                .foregroundStyle(isUser ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    isUser
                        ? AnyShapeStyle(LinearGradient(
                            colors: [Color(red: 0.25, green: 0.45, blue: 0.95), Color(red: 0.35, green: 0.30, blue: 0.90)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(.ultraThinMaterial),
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
            .liquidGlass(cornerRadius: 18)
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
