import SwiftUI

// MARK: - Proposed action model

struct ARIAProposedAction {
    let tool: String          // "create_task", "mark_plant_watered"
    let input: [String: Any]
    let displayText: String   // e.g. "Create task: Check boiler"
}

struct ARIAView: View {
    var onDismiss: (() -> Void)? = nil

    @Environment(PropertyService.self) private var propertyService
    @Environment(TaskService.self) private var taskService
    @Environment(PlantService.self) private var plantService
    @Environment(ApplianceService.self) private var applianceService
    @Environment(FamilyService.self) private var familyService
    @Environment(ProfileService.self) private var profileService
    @AppStorage("prvio.aria.customName") private var assistantName: String = "ARIA"
    @AppStorage("prvio.aria.avatarIcon") private var avatarIcon: String = "sparkles"
    @AppStorage("prvio.aria.personality") private var aiTone: String = "balanced"
    @State private var showSettings = false
    @State private var themeRefresh = 0

    // The assistant's conversation is a real chat: it takes the same
    // per-conversation theme system as every other conversation (scope
    // "aria"). ChatTheme.effective is the one authority — it applies the
    // "background keys are one setting" rule and falls back to the global
    // default, both of which the old hand-rolled per-key read skipped
    // (the "changing the background does nothing" bug).
    private var chatTheme: ChatTheme {
        _ = themeRefresh
        return .effective(scope: "aria")
    }
    // Same resolution as the group chat: the stock accent bubble for the
    // default theme, the theme's outgoing colour otherwise.
    private var ownBubbleColor: Color {
        chatTheme.id == "appDefault" ? Color.blue.opacity(0.75) : chatTheme.outgoingBubble
    }

    @State private var messages: [ARIAMessage] = []
    @State private var input = ""
    @State private var isThinking = false
    @State private var isLoadingHistory = true
    @State private var proposedAction: ARIAProposedAction? = nil
    @FocusState private var focused: Bool
    @AppStorage("prvio.voiceInput")        private var voiceInputEnabled: Bool = true
    @AppStorage("prvio.locale")            private var currentLocale: String = "en"
    @AppStorage("prvio.followSystemLang")  private var followSystemLanguage: Bool = true
    @State private var speech = SpeechRecognizer()
    @State private var showJumpToLatest = false
    /// False until the first batch of messages lands — the initial fill must
    /// not animate (bubbles springing into place read as an entry flash).
    @State private var chatDidLoad = false

    var body: some View {
        messageList
            .overlay(alignment: .bottom) { inputBar }
            .background(chatTheme.background)
            // iMessage-style header, same as the group chat: no bar, the
            // conversation slides under a progressive blur and only the
            // identity pill floats on top.
            .overlay(alignment: .top) { ChatTopBlur() }
            .overlay {
                if isLoadingHistory && messages.isEmpty {
                    MessageSkeleton()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showSettings) { ARIASettingsView() }
            .onChange(of: showSettings) { _, open in
                // Coming back from settings re-reads the (possibly changed) theme.
                if !open { themeRefresh &+= 1 }
            }
            .onAppear { themeRefresh &+= 1 }
            .onReceive(NotificationCenter.default.publisher(for: .ariaHistoryCleared)) { _ in
                withAnimation { messages = ARIAMessage.welcome }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        HapticFeedback.selection()
                        onDismiss?()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(AppFont.headline)
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("Close")
                }
                // One entry point, like a DM: tapping the assistant's identity
                // opens its settings (name, avatar, background, personality,
                // history). No avatar stack, no scattered toolbar buttons.
                ToolbarItem(placement: .principal) {
                    Button {
                        HapticFeedback.selection()
                        showSettings = true
                    } label: {
                        ChatHeaderPill {
                            HStack(spacing: 8) {
                                ARIAAvatar(size: 28)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(assistantName)
                                        .font(AppFont.subheadline)
                                        .foregroundStyle(.primary)
                                    Text("AI Assistant")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                                }
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.primary.opacity(0.35))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Settings")
                }
            }
            .task { await loadHistory() }
    }

    // MARK: - Message list

    /// Clearance so the newest message rests above the overlaid input bar
    /// (which blurs the messages behind it = real glass), same as the chat.
    private let chatBottomInset: CGFloat = 78

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(Array(messages.enumerated()), id: \.element.id) { idx, msg in
                        // Consecutive messages from the same speaker form a
                        // visual group: middle bubbles stay fully rounded, only
                        // the last one carries the tail (and, for the
                        // assistant, the avatar) — same read as the group chat.
                        let prevSame = idx > 0 && messages[idx - 1].role == msg.role
                        let nextSame = idx < messages.count - 1 && messages[idx + 1].role == msg.role
                        ARIAMessageRow(
                            message: msg,
                            isGroupEnd: !nextSame,
                            ownBubbleColor: ownBubbleColor
                        )
                        .padding(.top, prevSame ? 0 : 6)
                        .id(msg.id)
                    }
                    if isThinking {
                        ARIATypingBubble(assistantName: assistantName)
                            .padding(.top, 6)
                            .id("ARIA_TYPING")
                    }
                    Color.clear.frame(height: chatBottomInset)
                    // Jump-button sentinel — visibility follows the marker
                    // entering/leaving the lazy render window.
                    Color.clear.frame(height: 1).id("ARIA_BOTTOM")
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.2)) { showJumpToLatest = false }
                        }
                        .onDisappear {
                            withAnimation(.easeInOut(duration: 0.2)) { showJumpToLatest = true }
                        }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.sm)
                .animation(chatDidLoad ? .spring(response: 0.35, dampingFraction: 0.86) : nil,
                           value: messages.count)
                .animation(chatDidLoad ? .spring(response: 0.35, dampingFraction: 0.86) : nil,
                           value: isThinking)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.immediately)
            .onChange(of: messages.count) { old, _ in
                guard !messages.isEmpty else { return }
                defer { chatDidLoad = true }
                if old == 0 {
                    proxy.scrollTo("ARIA_BOTTOM", anchor: .bottom)
                } else {
                    withAnimation { proxy.scrollTo("ARIA_BOTTOM", anchor: .bottom) }
                }
            }
            .onChange(of: isThinking) {
                if isThinking { withAnimation { proxy.scrollTo("ARIA_BOTTOM", anchor: .bottom) } }
            }
            .overlay(alignment: .bottom) {
                if showJumpToLatest {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            proxy.scrollTo("ARIA_BOTTOM", anchor: .bottom)
                        }
                        HapticFeedback.impact(.light)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(AppFont.headline)
                            .foregroundStyle(.primary)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .glassCircle()
                    .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
                    .padding(.bottom, chatBottomInset + 8)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Jump to latest message")
                }
            }
        }
    }

    // MARK: - Input bar — the chat's compose pill: clear glass, one trailing control

    private var inputBar: some View {
        VStack(spacing: AppSpacing.sm) {
            // Action confirmation banner
            if let action = proposedAction {
                ARIAActionBanner(
                    action: action,
                    onConfirm: { confirmAction(action) },
                    onCancel: { withAnimation { proposedAction = nil } }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Slim pill field with the trailing control INSIDE it — the
            // dictation mic when empty, the filled send arrow while typing,
            // a stop control while the assistant is answering.
            HStack(alignment: .bottom, spacing: AppSpacing.sm) {
                TextField("Message…", text: $input, axis: .vertical)
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)
                    .tint(.accentColor)
                    .lineLimit(1...6)
                    .focused($focused)
                    .padding(.vertical, 7)
                    .onChange(of: speech.transcript) { _, t in
                        if !t.isEmpty { input = t }
                    }

                if isThinking {
                    Button {
                        isThinking = false
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white, Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 4)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Stop")
                } else if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if voiceInputEnabled {
                        // Dictation-style mic (iMessage) — tap to speak to the assistant.
                        Button {
                            HapticFeedback.impact(.light)
                            if speech.isListening {
                                speech.stop()
                            } else {
                                focused = false
                                Task { await speech.startListening() }
                            }
                        } label: {
                            Image(systemName: speech.isListening ? "waveform" : "mic.fill")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(speech.isListening
                                    ? Color.red
                                    : Color.primary.opacity(AppOpacity.disabled))
                                .symbolEffect(.pulse, isActive: speech.isListening)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 4)
                        .accessibilityLabel(speech.isListening ? "Stop voice input" : "Voice input")
                    }
                } else {
                    Button {
                        sendRaw()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white, Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 4)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Send")
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 5)
            .mediaGlass(in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        }
        .animation(.snappy(duration: 0.2), value: input.isEmpty)
        .animation(.snappy(duration: 0.2), value: isThinking)
        .padding(.horizontal, AppSpacing.lg)
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.xs)
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

    private func sendRaw() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        speech.stop()
        input = ""
        messages.append(ARIAMessage(role: .user, content: text))
        MessageSounds.sent()
        isThinking = true

        Task {
            do {
                let propId = propertyService.primary?.id.uuidString
                let lang = followSystemLanguage
                    ? (Language.devicePreferred.rawValue)
                    : currentLocale
                struct ARIAChatPayload: Encodable {
                    let message: String
                    let property_id: String?
                    let language: String
                    let tone: String
                    let assistant_name: String
                }
                let payload = ARIAChatPayload(message: text, property_id: propId, language: lang,
                                              tone: aiTone, assistant_name: assistantName)
                let rawResponse: Data = try await supabase.functions
                    .invoke("aria-chat", options: .init(body: payload))

                isThinking = false

                guard let json = try? JSONSerialization.jsonObject(with: rawResponse) as? [String: Any] else {
                    messages.append(ARIAMessage(role: .aria,
                        content: String(localized: "aria_error_generic")))
                    return
                }

                if let errorMsg = json["error"] as? String {
                    messages.append(ARIAMessage(role: .aria, content: errorMsg))
                    return
                }

                let responseType = json["type"] as? String
                if responseType == "action_required",
                   let tool = json["tool"] as? String,
                   let actionInput = json["input"] as? [String: Any] {
                    let replyText = json["reply"] as? String
                    if let replyText, !replyText.isEmpty {
                        messages.append(ARIAMessage(role: .aria, content: replyText))
                    }
                    withAnimation {
                        proposedAction = buildProposedAction(tool: tool, input: actionInput)
                    }
                } else if let reply = json["reply"] as? String {
                    messages.append(ARIAMessage(role: .aria, content: reply))
                } else {
                    messages.append(ARIAMessage(role: .aria,
                        content: String(localized: "aria_error_generic")))
                }
            } catch {
                isThinking = false
                messages.append(ARIAMessage(role: .aria,
                    content: String(localized: "aria_error_connection")))
            }
        }
    }

    private func buildProposedAction(tool: String, input: [String: Any]) -> ARIAProposedAction {
        let displayText: String
        switch tool {
        case "create_task":
            let name = input["name"] as? String ?? String(localized: "New Task")
            displayText = String(format: String(localized: "aria_create_task_display"), name)
        case "mark_plant_watered":
            let plantName = input["plant_name"] as? String ?? String(localized: "Plants")
            displayText = String(format: String(localized: "aria_water_plant_display"), plantName)
        case "add_appliance":
            let name = input["name"] as? String ?? String(localized: "Appliance")
            displayText = String(format: String(localized: "aria_add_appliance_display"), name)
        case "schedule_maintenance":
            let name = input["name"] as? String ?? String(localized: "Maintenance")
            displayText = String(format: String(localized: "aria_schedule_maintenance_display"), name)
        default:
            displayText = tool.replacingOccurrences(of: "_", with: " ").capitalized
        }
        return ARIAProposedAction(tool: tool, input: input, displayText: displayText)
    }

    private func confirmAction(_ action: ARIAProposedAction) {
        proposedAction = nil
        Task {
            switch action.tool {
            case "create_task":
                guard let propertyId = propertyService.primary?.id else { return }
                let name = action.input["name"] as? String ?? String(localized: "New Task")
                let description = action.input["description"] as? String
                let dueDate = action.input["due_date"] as? String
                let payload = NewTaskPayload(
                    propertyId: propertyId,
                    title: name,
                    description: description,
                    dueDate: dueDate,
                    priority: "medium",
                    category: "general",
                    assigneeIds: [],
                    assigneeNames: []
                )
                do {
                    try await taskService.addTask(payload)
                    messages.append(ARIAMessage(
                        role: .aria,
                        content: String(format: String(localized: "aria_task_created"), name)
                    ))
                } catch {
                    messages.append(ARIAMessage(
                        role: .aria,
                        content: String(localized: "aria_task_error")
                    ))
                }

            case "mark_plant_watered":
                let plantName = action.input["plant_name"] as? String ?? String(localized: "Plants")
                if let plant = plantService.plants.first(where: {
                    $0.name.lowercased().contains(plantName.lowercased())
                }) {
                    await plantService.markWatered(plant)
                }
                messages.append(ARIAMessage(
                    role: .aria,
                    content: String(format: String(localized: "aria_plant_watered"), plantName)
                ))

            case "add_appliance":
                guard let propertyId = propertyService.primary?.id,
                      let ownerId = profileService.profile?.id else { return }
                let applianceName = action.input["name"] as? String ?? String(localized: "Appliance")
                let brand = action.input["brand"] as? String
                let category = action.input["category"] as? String ?? "other"
                let location = action.input["location"] as? String
                let notes = action.input["notes"] as? String
                let now = ISO8601DateFormatter().string(from: Date())
                let appliancePayload = NewAppliancePayload(
                    propertyId: propertyId, ownerId: ownerId,
                    name: applianceName, brand: brand,
                    modelNumber: nil, serialNumber: nil,
                    location: location, category: category,
                    purchaseDate: nil, warrantyUntil: nil, purchasePrice: nil,
                    notes: notes, photoUrl: nil, createdAt: now, updatedAt: now
                )
                await applianceService.add(appliancePayload)
                messages.append(ARIAMessage(
                    role: .aria,
                    content: String(format: String(localized: "aria_appliance_added"), applianceName)
                ))

            case "schedule_maintenance":
                guard let propertyId = propertyService.primary?.id else { return }
                let maintName = action.input["name"] as? String ?? String(localized: "Maintenance")
                let maintDesc = action.input["description"] as? String
                let maintDate = action.input["due_date"] as? String
                let maintPayload = NewTaskPayload(
                    propertyId: propertyId,
                    title: maintName,
                    description: maintDesc,
                    dueDate: maintDate,
                    priority: "medium",
                    category: "maintenance",
                    assigneeIds: [],
                    assigneeNames: []
                )
                do {
                    try await taskService.addTask(maintPayload)
                    messages.append(ARIAMessage(
                        role: .aria,
                        content: String(format: String(localized: "aria_maintenance_scheduled"), maintName)
                    ))
                } catch {
                    messages.append(ARIAMessage(
                        role: .aria,
                        content: String(localized: "aria_maintenance_error")
                    ))
                }

            default:
                break
            }
        }
    }
}

// MARK: - Message row — the chat's bubble anatomy (shape, tail, colors)

private struct ARIAMessageRow: View {
    let message: ARIAMessage
    /// Last bubble of a same-speaker run — carries the tail (and the avatar
    /// for the assistant), exactly like the group chat's grouping.
    let isGroupEnd: Bool
    let ownBubbleColor: Color

    private var isUser: Bool { message.role == .user }
    private var bubbleShape: ChatBubbleShape {
        ChatBubbleShape(isOwn: isUser, hasTail: isGroupEnd)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser {
                Spacer(minLength: 60)
                Text(message.content)
                    .font(.system(size: 15))
                    // Adaptive text: a light custom bubble gets dark text,
                    // not invisible white — same rule as MessageBubble.
                    .foregroundStyle(ownBubbleColor.readableText)
                    .tint(ownBubbleColor.readableText)
                    .padding(.horizontal, AppSpacing.base).padding(.vertical, 9)
                    .background(ownBubbleColor, in: bubbleShape)
            } else {
                if isGroupEnd {
                    ARIAAvatar(size: 28)
                } else {
                    Color.clear.frame(width: 28, height: 1)
                }
                // LocalizedStringKey renders the assistant's inline Markdown
                // (bold, lists, links) the way Text was designed to.
                Text(LocalizedStringKey(message.content))
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .tint(Color.accentColor)
                    .padding(.horizontal, AppSpacing.base).padding(.vertical, 9)
                    .background(Color.primary.opacity(0.08), in: bubbleShape)
                Spacer(minLength: 60)
            }
        }
    }
}

// MARK: - Typing indicator — the chat's three-dot bubble while the AI thinks

private struct ARIATypingBubble: View {
    let assistantName: String
    @State private var bounce = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ARIAAvatar(size: 28)
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.primary.opacity(AppOpacity.mediumText))
                        .frame(width: 7, height: 7)
                        .scaleEffect(bounce ? 1.0 : 0.55)
                        .animation(reduceMotion ? nil
                                   : .easeInOut(duration: 0.5).repeatForever(autoreverses: true)
                                       .delay(Double(i) * 0.16),
                                   value: bounce)
                }
            }
            .padding(.horizontal, AppSpacing.base).padding(.vertical, 12)
            .background(Color.primary.opacity(0.08),
                        in: ChatBubbleShape(isOwn: false, hasTail: true))
            Spacer(minLength: 60)
        }
        .onAppear { bounce = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(assistantName) \(String(localized: "typing…"))"))
    }
}

// MARK: - Models

struct ARIAMessage: Identifiable {
    let id = UUID()
    enum Role { case user, aria }
    let role: Role
    let content: String

    static var welcome: [ARIAMessage] {
        [ARIAMessage(role: .aria, content: String(localized: "aria_welcome"))]
    }
}

// MARK: - Action Banner

private struct ARIAActionBanner: View {
    let action: ARIAProposedAction
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.yellow)
                Text(action.displayText)
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Button(action: onConfirm) {
                    Text("Confirm")
                        .font(AppFont.captionEmphasis)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.sm)
                        .mediaGlass(in: RoundedRectangle(cornerRadius: 10, style: .continuous), interactive: true)
                }
                .buttonStyle(.plain)

                Button(action: onCancel) {
                    Text("Cancel")
                        .font(AppFont.captionEmphasis)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.sm)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .strokeBorder(Color.yellow.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - DB Message model

private struct ARIADBMessage: Decodable {
    let id: UUID
    let role: String
    let content: String
    let createdAt: String
    enum CodingKeys: String, CodingKey {
        case id, role, content; case createdAt = "created_at"
    }
}
