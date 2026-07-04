import SwiftUI

private struct ARIABottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

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
    @AppStorage("prvio.avatarRingColorName") private var avatarRingColorName: String = "blue"
    @AppStorage("prvio.aria.customName") private var assistantName: String = "ARIA"
    @AppStorage("prvio.aria.avatarIcon") private var avatarIcon: String = "sparkles"
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
                        .font(AppFont.headline)
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("Close")
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
                        .font(AppFont.headline)
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("Reset messages")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { ARIASettingsView() } label: {
                    Image(systemName: "gearshape")
                        .font(AppFont.headline)
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel("Settings")
            }
        }
        .task { await loadHistory() }
    }

    // MARK: - Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            GeometryReader { outer in
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
                        Color.clear.frame(height: 1).id("ARIA_BOTTOM")
                            .background(GeometryReader { g in
                                Color.clear.preference(key: ARIABottomKey.self,
                                                       value: g.frame(in: .named("ariaScroll")).minY)
                            })
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.sm)
                    .padding(.bottom, AppSpacing.xl)
                }
            }
            .coordinateSpace(name: "ariaScroll")
            .onPreferenceChange(ARIABottomKey.self) { minY in
                withAnimation(.easeInOut(duration: 0.2)) {
                    showJumpToLatest = minY > outer.size.height + 60
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) {
                withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
            }
            .onChange(of: isThinking) {
                if isThinking { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
            }
            .overlay(alignment: .bottom) {
                if showJumpToLatest {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            proxy.scrollTo(messages.last?.id, anchor: .bottom)
                        }
                        HapticFeedback.impact(.light)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(AppFont.headline)
                            .foregroundStyle(.primary)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Jump to latest")
                    .glassCircle()
                    .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
                    .padding(.bottom, 10)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            } // end GeometryReader
        }
    }

    // MARK: - Input bar — matches mockup: text field + [mic|waveform|cloud] + glowing orb

    private var inputBar: some View {
        VStack(spacing: 0) {
            // Action confirmation banner
            if let action = proposedAction {
                ARIAActionBanner(
                    action: action,
                    onConfirm: { confirmAction(action) },
                    onCancel: { proposedAction = nil }
                )
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.sm)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            VStack(spacing: 10) {
                // Text field row
                HStack(spacing: 10) {
                    TextField("aria_placeholder", text: $input, axis: .vertical)
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
                                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, AppSpacing.base)
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
                                    .font(AppFont.headline)
                                    .foregroundStyle(speech.isListening
                                        ? .red
                                        : Color(red: 0.55, green: 0.70, blue: 1.0))
                                    .symbolEffect(.pulse, isActive: speech.isListening)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(speech.isListening ? "Stop voice input" : "Voice input")

                        // Waveform / equalizer button
                        Button {
                            HapticFeedback.impact(.light)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.primary.opacity(0.1))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "waveform")
                                    .font(AppFont.headline)
                                    .foregroundStyle(Color(red: 0.55, green: 0.70, blue: 1.0))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Audio mode")

                        // Cloud / AI mode button
                        Button {
                            HapticFeedback.impact(.light)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.primary.opacity(0.1))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "icloud")
                                    .font(AppFont.headline)
                                    .foregroundStyle(Color(red: 0.55, green: 0.70, blue: 1.0))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cloud mode")
                    }

                    Spacer()

                    // Right: large glowing blue orb (send / stop)
                    Button {
                        speech.stop()
                        if isThinking { isThinking = false } else { sendRaw() }
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
                                            Color.brandSkyBlue.opacity(0.5),
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
                                            Color.brandSkyBlue,
                                            Color(red: 0.30, green: 0.38, blue: 0.98)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 52, height: 52)
                                .shadow(color: Color.brandSkyBlue.opacity(0.8), radius: 14, y: 3)

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
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.md)
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

    private func sendRaw() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        messages.append(ARIAMessage(role: .user, content: text))
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
                }
                let payload = ARIAChatPayload(message: text, property_id: propId, language: lang)
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
                        .font(AppFont.captionStrong)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                }
            }

            Text(LocalizedStringKey(message.content))
                .font(.body)
                .foregroundStyle(isUser ? .white : .primary)
                .padding(.horizontal, AppSpacing.base)
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
                    .font(AppFont.captionStrong)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
            }
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.primary.opacity(AppOpacity.mediumText))
                        .frame(width: 6, height: 6)
                        .scaleEffect(phase == i ? 1.3 : 0.8)
                        .animation(.easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.15), value: phase)
                }
            }
            .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.base)
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
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.sm)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
