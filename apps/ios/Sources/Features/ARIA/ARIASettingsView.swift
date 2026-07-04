import SwiftUI
import Supabase

// MARK: - ARIA Settings View

struct ARIASettingsView: View {
    // Identity
    @AppStorage("prvio.aria.customName") var assistantName = "ARIA"
    @AppStorage("prvio.aria.avatarIcon") var avatarIcon = "sparkles"

    // Personality
    @AppStorage("prvio.aria.personality") var personality = "balanced"

    // Context toggles
    @AppStorage("prvio.aria.showTasks") var canSeeTasks = true
    @AppStorage("prvio.aria.showFinances") var canSeeFinances = true
    @AppStorage("prvio.aria.showProperty") var canSeeProperty = true
    @AppStorage("prvio.aria.showFamily") var canSeeFamily = true
    @AppStorage("prvio.aria.showPlants") var canSeePlants = true

    // Model / API key
    @AppStorage("prvio.aria.customApiKey") var customApiKey = ""
    @AppStorage("prvio.aria.useCustomModel") var useCustomModel = false

    // UI state
    @State private var showNameEditor = false
    @State private var pendingName = ""
    @State private var showApiKeySheet = false
    @State private var showClearConfirm = false
    @State private var showShareSheet = false
    @State private var exportURL: URL? = nil
    @State private var isDeletingHistory = false

    @Environment(TaskService.self) var taskService
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                identitySection
                personalitySection
                contextSection
                modelSection
                conversationSection
                Spacer(minLength: 100)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("AI Settings")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Rename Assistant", isPresented: $showNameEditor) {
            TextField("Assistant name", text: $pendingName)
                .autocorrectionDisabled()
            Button("Save") {
                let trimmed = pendingName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { assistantName = trimmed }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a custom name for your AI assistant.")
        }
        .sheet(isPresented: $showApiKeySheet) {
            ApiKeyEditorSheet(apiKey: $customApiKey)
        }
        .confirmationDialog(
            "Clear Conversation History",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                Task { await clearHistory() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All messages with \(assistantName) will be permanently deleted.")
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL {
                ShareSheet(url: url)
            }
        }
    }

    // MARK: - Identity Section

    private var identitySection: some View {
        settingsGroup("IDENTITY") {
            Button {
                pendingName = assistantName
                showNameEditor = true
            } label: {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "person.text.rectangle.fill", color: .blue)
                    Text("Assistant Name")
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(assistantName)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.primary.opacity(0.38))
                    Image(systemName: "chevron.right")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.primary.opacity(0.28))
                }
                .padding(.horizontal, AppSpacing.base)
                .padding(.vertical, AppSpacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            rowDivider

            // Avatar style picker
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: avatarIcon, color: .purple)
                    Text("Avatar Style")
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, AppSpacing.base)
                .padding(.top, AppSpacing.md)

                HStack(spacing: 10) {
                    ForEach(avatarOptions, id: \.icon) { option in
                        avatarChip(option: option)
                    }
                }
                .padding(.horizontal, AppSpacing.base)
                .padding(.bottom, AppSpacing.md)
            }

            rowDivider

            Text("Your AI assistant's identity is private to you")
                .font(.system(size: 12))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.horizontal, AppSpacing.base)
                .padding(.vertical, 10)
        }
    }

    private struct AvatarOption {
        let icon: String
        let label: LocalizedStringKey
    }

    private var avatarOptions: [AvatarOption] {
        [
            AvatarOption(icon: "sparkles", label: "Sparkles"),
            AvatarOption(icon: "brain", label: "Brain"),
            AvatarOption(icon: "cpu", label: "CPU"),
            AvatarOption(icon: "person.wave.2", label: "Guide")
        ]
    }

    private func avatarChip(option: AvatarOption) -> some View {
        let isSelected = avatarIcon == option.icon
        return Button {
            HapticFeedback.selection()
            avatarIcon = option.icon
        } label: {
            VStack(spacing: 4) {
                Image(systemName: option.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .frame(width: 42, height: 42)
                    .background(
                        isSelected
                            ? AnyShapeStyle(Color.accentColor)
                            : AnyShapeStyle(.regularMaterial),
                        in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    )
                Text(option.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : Color.primary.opacity(AppOpacity.mediumText))
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Personality Section

    private var personalitySection: some View {
        settingsGroup("PERSONALITY") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(personalityOptions, id: \.id) { option in
                    personalityChip(id: option.id, label: option.label, icon: option.icon)
                }
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.base)
        }
    }

    private struct PersonalityOption {
        let id: String
        let label: LocalizedStringKey
        let icon: String
    }

    private var personalityOptions: [PersonalityOption] {
        [
            PersonalityOption(id: "balanced", label: "Balanced", icon: "person.fill"),
            PersonalityOption(id: "professional", label: "Professional", icon: "briefcase.fill"),
            PersonalityOption(id: "friendly", label: "Friendly", icon: "heart.fill"),
            PersonalityOption(id: "concise", label: "Concise", icon: "text.alignleft")
        ]
    }

    private func personalityChip(id: String, label: LocalizedStringKey, icon: String) -> some View {
        let isActive = personality == id
        return Button {
            HapticFeedback.selection()
            personality = id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(AppFont.footnoteEmphasis)
                Text(label)
                    .font(AppFont.captionEmphasis)
            }
            .foregroundStyle(isActive ? .white : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.md)
            .background(
                isActive
                    ? AnyShapeStyle(Color.accentColor)
                    : AnyShapeStyle(.regularMaterial),
                in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Context Section

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHAT \(assistantName) CAN SEE")
                .textCase(.uppercase)
                .font(AppFont.captionStrong)
                .foregroundStyle(.secondary)
                .padding(.leading, AppSpacing.sm)

            VStack(spacing: 0) {
                contextToggleRow(icon: "checklist", color: .orange,
                                 label: "Tasks", value: $canSeeTasks)
                rowDivider
                contextToggleRow(icon: "banknote.fill",
                                 color: Color.brandSuccess,
                                 label: "Finances", value: $canSeeFinances)
                rowDivider
                contextToggleRow(icon: "house.fill", color: .blue,
                                 label: "Property", value: $canSeeProperty)
                rowDivider
                contextToggleRow(icon: "person.2.fill", color: .purple,
                                 label: "Family", value: $canSeeFamily)
                rowDivider
                contextToggleRow(icon: "leaf.fill",
                                 color: Color(red: 0.3, green: 0.75, blue: 0.4),
                                 label: "Plants", value: $canSeePlants)
            }
            .liquidGlass(cornerRadius: AppRadius.xl)

            Text("Disable to prevent \(assistantName) from accessing this data type in conversations")
                .font(.system(size: 12))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.leading, AppSpacing.sm)
                .padding(.top, 2)
        }
    }

    private func contextToggleRow(icon: String, color: Color, label: LocalizedStringKey, value: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color)
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
            Spacer()
            Toggle("", isOn: value)
                .labelsHidden()
                .tint(.accentColor)
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
    }

    // MARK: - Model Section

    private var modelSection: some View {
        settingsGroup("AI MODEL") {
            // Default Claude row
            Button {
                HapticFeedback.selection()
                useCustomModel = false
            } label: {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "sparkles", color: .blue)
                    Text("Claude (Default)")
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                    Spacer()
                    if !useCustomModel {
                        Image(systemName: "checkmark")
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.horizontal, AppSpacing.base)
                .padding(.vertical, AppSpacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            rowDivider

            // Custom API Key row
            Button {
                showApiKeySheet = true
            } label: {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "key.fill", color: .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Custom API Key")
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                        Text("Advanced")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.primary.opacity(0.4))
                    }
                    Spacer()
                    Text(LocalizedStringKey(customApiKey.isEmpty ? "Not set" : "Configured"))
                        .font(.system(size: 13))
                        .foregroundStyle(customApiKey.isEmpty
                            ? Color.primary.opacity(AppOpacity.disabled)
                            : Color.brandSuccess)
                    Image(systemName: "chevron.right")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.primary.opacity(0.28))
                }
                .padding(.horizontal, AppSpacing.base)
                .padding(.vertical, AppSpacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            rowDivider

            // Use custom model toggle
            HStack(spacing: 12) {
                ColoredIconBadge(icon: "cpu", color: .indigo)
                Text("Use Custom Model")
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                Spacer()
                Toggle("", isOn: $useCustomModel)
                    .labelsHidden()
                    .tint(.accentColor)
                    .disabled(customApiKey.isEmpty)
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.md)
            .opacity(customApiKey.isEmpty ? 0.45 : 1.0)
        }
    }

    // MARK: - Conversation Section

    private var conversationSection: some View {
        settingsGroup("CONVERSATIONS") {
            Button {
                Task { await exportHistory() }
            } label: {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "square.and.arrow.up", color: .blue)
                    Text("Export conversation history")
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.primary.opacity(0.28))
                }
                .padding(.horizontal, AppSpacing.base)
                .padding(.vertical, AppSpacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            rowDivider

            Button(role: .destructive) {
                showClearConfirm = true
            } label: {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "trash.fill", color: .red)
                    Text("Clear conversation history")
                        .font(.system(size: 15))
                        .foregroundStyle(.red)
                    Spacer()
                    if isDeletingHistory {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .padding(.horizontal, AppSpacing.base)
                .padding(.vertical, AppSpacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDeletingHistory)
        }
    }

    // MARK: - Layout Helpers

    private func settingsGroup<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppFont.captionStrong)
                .foregroundStyle(.secondary)
                .padding(.leading, AppSpacing.sm)
            VStack(spacing: 0) { content() }
                .liquidGlass(cornerRadius: AppRadius.xl)
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(AppOpacity.hairline))
            .frame(height: 0.4)
            .padding(.leading, 52)
    }

    // MARK: - Actions

    private func exportHistory() async {
        struct ExportMessage: Decodable, Encodable {
            let id: UUID
            let role: String
            let content: String
            let createdAt: String
            enum CodingKeys: String, CodingKey {
                case id, role, content; case createdAt = "created_at"
            }
        }
        do {
            let messages: [ExportMessage] = try await supabase
                .from("aria_messages")
                .select("id, role, content, created_at")
                .order("created_at", ascending: true)
                .execute()
                .value
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(messages)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("aria_conversation.json")
            try data.write(to: url, options: .atomic)
            exportURL = url
            showShareSheet = true
        } catch {
            // silently ignore — no messages to export or encoding failed
        }
    }

    private func clearHistory() async {
        isDeletingHistory = true
        defer { isDeletingHistory = false }
        do {
            // Delete all rows by matching every row (neq on a nil-able uuid sentinel)
            try await supabase
                .from("aria_messages")
                .delete()
                .neq("id", value: UUID(uuidString: "00000000-0000-0000-0000-000000000000") ?? UUID())
                .execute()
        } catch {
            // ignore — table may already be empty
        }
    }
}

// MARK: - API Key Editor Sheet

private struct ApiKeyEditorSheet: View {
    @Binding var apiKey: String
    @State private var draft = ""
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .frame(width: 64, height: 64)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(AppOpacity.hairline), lineWidth: 0.5)
                                )
                            Image(systemName: "key.fill")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(.orange)
                        }
                        Text("Custom API Key")
                            .font(.system(size: 20, weight: .bold))
                        Text("Bring your own Anthropic API key")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    }
                    .padding(.top, AppSpacing.lg)

                    // Input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("API KEY")
                            .font(AppFont.label)
                            .foregroundStyle(.secondary)
                            .padding(.leading, AppSpacing.xxs)

                        SecureField("sk-ant-api03-...", text: $draft)
                            .font(.system(size: 14, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding(.horizontal, AppSpacing.base)
                            .padding(.vertical, AppSpacing.base)
                            .liquidGlass(cornerRadius: 14)
                    }

                    // Security notice
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.green)
                        Text("Your API key is stored securely on this device and never shared with PRVIO servers.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.primary.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, AppSpacing.base)
                    .padding(.vertical, AppSpacing.base)
                    .liquidGlass(cornerRadius: 14)

                    // Save / Clear buttons
                    VStack(spacing: 10) {
                        Button {
                            let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                            apiKey = trimmed
                            dismiss()
                        } label: {
                            Text("Save Key")
                                .font(AppFont.subheadline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppSpacing.base)
                                .background(
                                    draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        ? Color.accentColor.opacity(0.4)
                                        : Color.accentColor,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if !apiKey.isEmpty {
                            Button(role: .destructive) {
                                apiKey = ""
                                draft = ""
                                dismiss()
                            } label: {
                                Text("Clear Key")
                                    .font(AppFont.subheadline)
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, AppSpacing.base)
                                    .background(.regularMaterial,
                                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, AppSpacing.xl)
            }
            .background(appBackground.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear { draft = apiKey }
    }
}
