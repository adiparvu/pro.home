import SwiftUI
import Supabase
import PhotosUI

// MARK: - Assistant personality — single source of truth
//
// Every case is real behavior: the raw value travels with each aria-chat
// request as `tone`, and the edge function turns it into a system-prompt
// directive. The sample line previews the exact voice the directive produces.

enum ARIAPersonality: String, CaseIterable, Identifiable {
    case balanced, professional, friendly, concise

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .balanced:     return "Balanced"
        case .professional: return "Professional"
        case .friendly:     return "Friendly"
        case .concise:      return "Concise"
        }
    }

    var icon: String {
        switch self {
        case .balanced:     return "person.fill"
        case .professional: return "briefcase.fill"
        case .friendly:     return "heart.fill"
        case .concise:      return "text.alignleft"
        }
    }

    var accent: Color {
        switch self {
        case .balanced:     return .brandPrimaryBlue
        case .professional: return .brandIndigo
        case .friendly:     return .brandPink
        case .concise:      return .brandTeal
        }
    }

    /// The one-line sample reply shown on the card and in the hero preview.
    var sample: String {
        switch self {
        case .balanced:     return String(localized: "aria_sample_balanced")
        case .professional: return String(localized: "aria_sample_professional")
        case .friendly:     return String(localized: "aria_sample_friendly")
        case .concise:      return String(localized: "aria_sample_concise")
        }
    }
}

// MARK: - Assistant response language
//
// "auto" keeps today's behavior (follow the app language); a fixed choice
// overrides the `language` field of every aria-chat request, which the edge
// function converts into a hard "always respond in…" instruction.

enum ARIAResponseLanguage: String, CaseIterable, Identifiable {
    case auto
    case romanian = "ro"
    case english  = "en"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto:     return String(localized: "aria_lang_auto")
        case .romanian: return Language.romanian.nativeName
        case .english:  return Language.english.nativeName
        }
    }
}

// MARK: - ARIA Settings View

struct ARIASettingsView: View {
    // Identity — rendered live by ARIAAvatar everywhere the assistant speaks.
    @AppStorage("prvio.aria.customName") var assistantName = "ARIA"
    @AppStorage("prvio.aria.avatarIcon") var avatarIcon = "sparkles"
    @AppStorage("prvio.aria.avatarKind") var avatarKind = "icon"
    @AppStorage("prvio.aria.avatarEmoji") var avatarEmoji = "✨"
    @AppStorage("prvio.aria.avatarRev") var avatarRevision = 0
    @State private var avatarPhotoItem: PhotosPickerItem?

    // Personality — sent as `tone` with every aria-chat request.
    @AppStorage("prvio.aria.personality") var personality = "balanced"

    // Context access — sent as `allow_*` with every aria-chat request; the
    // edge function skips loading (and offering tools over) gated domains.
    @AppStorage("prvio.aria.showTasks") var canSeeTasks = true
    @AppStorage("prvio.aria.showFinances") var canSeeFinances = true
    @AppStorage("prvio.aria.showProperty") var canSeeProperty = true
    @AppStorage("prvio.aria.showFamily") var canSeeFamily = true
    @AppStorage("prvio.aria.showPlants") var canSeePlants = true

    // Memory — response-language override for aria-chat requests.
    @AppStorage("prvio.aria.responseLanguage") var responseLanguage = "auto"

    // UI state
    @State private var showNameEditor = false
    @State private var pendingName = ""
    @State private var showClearConfirm = false
    @State private var showThemePicker = false
    @State private var showShareSheet = false
    @State private var exportURL: URL? = nil
    @State private var isDeletingHistory = false
    /// Post-deletion feedback (IMG_9284): nil = nothing to report, true =
    /// wiped, false = the delete FAILED (and the count didn't lie to zero).
    @State private var clearSucceeded: Bool? = nil
    /// Real stored-message count from aria_messages; nil while loading.
    @State private var storedMessageCount: Int? = nil

    @Environment(TaskService.self) var taskService
    @Environment(FinancialService.self) var financialService
    @Environment(PropertyService.self) var propertyService
    @Environment(FamilyService.self) var familyService
    @Environment(PlantService.self) var plantService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) var dismiss

    private var currentPersonality: ARIAPersonality {
        ARIAPersonality(rawValue: personality) ?? .balanced
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: AppSpacing.xxl) {
                heroSection
                identitySection
                personalitySection
                contextSection
                memorySection
                appearanceSection
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
        .sheet(isPresented: $showThemePicker) {
            ChatThemePicker(scope: "aria")
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
        // The moment of truth after the destructive tap (IMG_9284): the row
        // used to delete silently — done or failed, the page looked the same.
        .alert(Text(clearSucceeded == true ? "aria_memory_cleared_title"
                                           : "aria_memory_clear_failed_title"),
               isPresented: Binding(get: { clearSucceeded != nil },
                                    set: { if !$0 { clearSucceeded = nil } })) {
            Button(role: .cancel) {} label: { Text("OK") }
        } message: {
            Text(clearSucceeded == true ? "aria_memory_cleared_body"
                                        : "aria_memory_clear_failed_body")
        }
        .task { await loadStoredMessageCount() }
        .task { await refreshDomainCounts() }
    }

    // MARK: - Hero — live assistant preview
    //
    // The card is the setting made visible: name, avatar and one sample reply
    // in the currently selected tone. Every identity change below re-renders
    // it instantly, so the user sees exactly what the chat will look like.

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                HStack(spacing: AppSpacing.md) {
                    ARIAAvatar(size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(assistantName)
                            .font(AppFont.title3)
                            .foregroundStyle(.primary)
                            .contentTransition(.opacity)
                        Text("AI Assistant")
                            .font(AppFont.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                // One sample reply bubble, morphing with the selected tone.
                HStack(alignment: .bottom, spacing: AppSpacing.sm) {
                    ARIAAvatar(size: 24)
                    Text(currentPersonality.sample)
                        .font(AppFont.scaled(15))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, AppSpacing.base)
                        .padding(.vertical, 9)
                        // Same opaque incoming fill the real thread's bubbles
                        // use (the DM's ChatTextBubbleView incoming variant),
                        // so the preview is faithful.
                        .background(Color(.secondarySystemBackground),
                                    in: ChatBubbleShape(isOwn: false, hasTail: true))
                        .id(personality)
                        .transition(reduceMotion
                            ? AnyTransition.opacity
                            : AnyTransition(BlurReplaceTransition(configuration: .downUp)))
                    Spacer(minLength: AppSpacing.lg)
                }
            }
            .padding(AppSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(cornerRadius: AppRadius.xxl)
            .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: personality)
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: assistantName)
            .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: avatarKind)
            .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: avatarIcon)
            .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: avatarEmoji)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(assistantName)
            .accessibilityValue(Text(currentPersonality.sample))

            Text("aria_hero_footer")
                .font(AppFont.scaled(12))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.leading, AppSpacing.sm)
                .padding(.top, 6)
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
                        .font(AppFont.scaled(15))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(assistantName)
                        .font(AppFont.scaled(14))
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
            .accessibilityLabel(Text("Assistant Name"))
            .accessibilityValue(Text(assistantName))

            rowDivider

            // Avatar — every option here really renders in the conversation
            // (header pill, reply bubbles, typing indicator) via ARIAAvatar.
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "person.crop.circle.fill", color: .purple)
                    Text("Avatar Style")
                        .font(AppFont.scaled(15))
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

                // Beyond icons: the assistant can wear an emoji or a photo of
                // the owner's choosing — same identity everywhere it speaks.
                HStack(spacing: 10) {
                    Button {
                        HapticFeedback.selection()
                        avatarKind = "emoji"
                    } label: {
                        HStack(spacing: 6) {
                            Text(avatarEmoji.isEmpty ? "✨" : avatarEmoji)
                            Text("Emoji").font(AppFont.caption)
                        }
                        .padding(.horizontal, AppSpacing.md).padding(.vertical, 7)
                        .background(avatarKind == "emoji" ? Color.accentColor.opacity(0.18)
                                                          : Color.primary.opacity(AppOpacity.subtleFill),
                                    in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Emoji"))
                    .accessibilityAddTraits(avatarKind == "emoji" ? .isSelected : [])

                    if avatarKind == "emoji" {
                        TextField("✨", text: Binding(
                            get: { avatarEmoji },
                            set: { avatarEmoji = String($0.suffix(1)) }
                        ))
                        .frame(width: 44)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(AppOpacity.subtleFill),
                                    in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                        .accessibilityLabel(Text("Emoji"))
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }

                    PhotosPicker(selection: $avatarPhotoItem, matching: .images) {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.fill").font(AppFont.caption)
                            Text("Photo").font(AppFont.caption)
                        }
                        .padding(.horizontal, AppSpacing.md).padding(.vertical, 7)
                        .background(avatarKind == "photo" ? Color.accentColor.opacity(0.18)
                                                          : Color.primary.opacity(AppOpacity.subtleFill),
                                    in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Photo"))
                    .accessibilityAddTraits(avatarKind == "photo" ? .isSelected : [])
                    .onChange(of: avatarPhotoItem) { _, item in
                        guard let item else { return }
                        Task {
                            if let data = try? await item.loadTransferable(type: Data.self),
                               let image = UIImage(data: data),
                               ARIAAvatarStore.savePhoto(image) {
                                avatarKind = "photo"
                                avatarRevision += 1
                            }
                            avatarPhotoItem = nil
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, AppSpacing.base)
                .padding(.bottom, AppSpacing.md)
                .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: avatarKind)
            }

            rowDivider

            Text("Your AI assistant's identity is private to you")
                .font(AppFont.scaled(12))
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
        // Selected only when the icon is what actually renders right now —
        // an emoji/photo avatar must not leave a stale-highlighted icon.
        let isSelected = avatarKind == "icon" && avatarIcon == option.icon
        return Button {
            HapticFeedback.selection()
            avatarIcon = option.icon
            avatarKind = "icon"
        } label: {
            VStack(spacing: 4) {
                Image(systemName: option.icon)
                    .font(AppFont.scaled(18, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .frame(width: 42, height: 42)
                    .background(
                        isSelected
                            ? AnyShapeStyle(Color.accentColor)
                            : AnyShapeStyle(.regularMaterial),
                        in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    )
                Text(option.label)
                    .font(AppFont.scaled(10, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : Color.primary.opacity(AppOpacity.mediumText))
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(Text(option.label))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Personality Section
    //
    // Cards, not chips: each tone shows the sentence it will actually write.
    // Selection changes the `tone` sent with every request — the hero above
    // morphs to the same sample so cause and effect stay visible.

    private var personalitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Personality")
                .font(AppFont.captionStrong)
                .foregroundStyle(.secondary)
                .padding(.leading, AppSpacing.sm)

            VStack(spacing: 10) {
                ForEach(ARIAPersonality.allCases) { option in
                    personalityCard(option)
                }
            }

            Text("aria_personality_footer \(assistantName)")
                .font(AppFont.scaled(12))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.leading, AppSpacing.sm)
                .padding(.top, 2)
        }
    }

    private func personalityCard(_ option: ARIAPersonality) -> some View {
        let isSelected = currentPersonality == option
        let cardShape = RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
        return Button {
            guard !isSelected else { return }
            HapticFeedback.selection()
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
                personality = option.rawValue
            }
        } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: option.icon)
                    .font(AppFont.scaled(15, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : option.accent)
                    .frame(width: 34, height: 34)
                    .background(
                        isSelected
                            ? AnyShapeStyle(option.accent)
                            : AnyShapeStyle(option.accent.opacity(AppOpacity.tintedFill)),
                        in: Circle()
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.label)
                        .font(AppFont.subheadline)
                        .foregroundStyle(.primary)
                    Text(option.sample)
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(AppFont.scaled(20))
                    .foregroundStyle(isSelected ? option.accent : Color.primary.opacity(0.15))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(AppSpacing.base)
            .contentShape(cardShape)
        }
        .buttonStyle(.plain)
        .liquidGlass(cornerRadius: AppRadius.xl)
        .overlay(
            cardShape.strokeBorder(
                isSelected ? option.accent.opacity(0.55) : Color.clear,
                lineWidth: 1.5
            )
        )
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: isSelected)
        .accessibilityLabel(Text(option.label))
        .accessibilityValue(Text(option.sample))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Context Section
    //
    // Each row states what access means and shows the real live count from
    // the same @Observable service the rest of the app renders. The switch is
    // enforcement, not decoration: `allow_*` flags ride along with every
    // aria-chat request and the edge function refuses to load gated data.

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHAT \(assistantName) CAN SEE")
                .font(AppFont.captionStrong)
                .foregroundStyle(.secondary)
                .padding(.leading, AppSpacing.sm)

            VStack(spacing: 0) {
                contextToggleRow(
                    icon: "checklist", color: .orange, label: "Tasks",
                    detail: "aria_ctx_tasks_desc",
                    count: String(format: String(localized: "aria_count_tasks"), taskService.openCount),
                    value: $canSeeTasks)
                rowDivider
                contextToggleRow(
                    icon: "banknote.fill", color: Color.brandSuccess, label: "Finances",
                    detail: "aria_ctx_finances_desc",
                    count: String(format: String(localized: "aria_count_records"), financialService.records.count),
                    value: $canSeeFinances)
                rowDivider
                contextToggleRow(
                    icon: "house.fill", color: .blue, label: "Property",
                    detail: "aria_ctx_property_desc",
                    count: String(format: String(localized: "aria_count_properties"), propertyService.properties.count),
                    value: $canSeeProperty)
                rowDivider
                contextToggleRow(
                    icon: "person.2.fill", color: .purple, label: "Family",
                    detail: "aria_ctx_family_desc",
                    count: String(format: String(localized: "aria_count_members"), familyService.members.count),
                    value: $canSeeFamily)
                rowDivider
                contextToggleRow(
                    icon: "leaf.fill", color: Color.brandSuccess, label: "Plants",
                    detail: "aria_ctx_plants_desc",
                    count: String(format: String(localized: "aria_count_plants"), plantService.plants.count),
                    value: $canSeePlants)
            }
            .liquidGlass(cornerRadius: AppRadius.xl)

            Text("aria_ctx_footer \(assistantName)")
                .font(AppFont.scaled(12))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.leading, AppSpacing.sm)
                .padding(.top, 2)
        }
    }

    private func contextToggleRow(icon: String, color: Color,
                                  label: LocalizedStringKey,
                                  detail: LocalizedStringKey,
                                  count: String,
                                  value: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: color)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(label)
                        .font(AppFont.scaled(15))
                        .foregroundStyle(.primary)
                    Text(value.wrappedValue ? count : String(localized: "aria_ctx_off"))
                        .font(AppFont.caption)
                        .foregroundStyle(value.wrappedValue
                            ? Color.primary.opacity(AppOpacity.secondaryText)
                            : Color.primary.opacity(AppOpacity.disabled))
                        .contentTransition(.opacity)
                }
                Text(detail)
                    .font(AppFont.scaled(12))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle(isOn: value) { Text(label) }
                .labelsHidden()
                .tint(.accentColor)
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: value.wrappedValue)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(value.wrappedValue ? count : String(localized: "aria_ctx_off")))
    }

    // MARK: - Memory Section
    //
    // Real numbers, real deletion: the count is the live row count of
    // aria_messages, and the destructive action deletes those rows.

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("aria_memory_header")
                .font(AppFont.captionStrong)
                .foregroundStyle(.secondary)
                .padding(.leading, AppSpacing.sm)

            VStack(spacing: 0) {
                // Stored messages count
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "brain.head.profile", color: .pink)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("aria_memory_messages")
                            .font(AppFont.scaled(15))
                            .foregroundStyle(.primary)
                        Text("aria_memory_messages_desc")
                            .font(AppFont.scaled(12))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                    }
                    Spacer()
                    if let count = storedMessageCount {
                        Text(String(format: String(localized: "aria_memory_count"), count))
                            .font(AppFont.scaled(14))
                            .foregroundStyle(Color.primary.opacity(0.38))
                            .contentTransition(.numericText())
                            .animation(reduceMotion ? nil : .snappy(duration: 0.3),
                                       value: storedMessageCount)
                    } else {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .padding(.horizontal, AppSpacing.base)
                .padding(.vertical, AppSpacing.md)
                .accessibilityElement(children: .combine)

                rowDivider

                // Response language — overrides the `language` sent to aria-chat.
                Menu {
                    Picker("aria_lang_title", selection: $responseLanguage) {
                        ForEach(ARIAResponseLanguage.allCases) { lang in
                            Text(lang.label).tag(lang.rawValue)
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        ColoredIconBadge(icon: "globe", color: .indigo)
                        Text("aria_lang_title")
                            .font(AppFont.scaled(15))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text((ARIAResponseLanguage(rawValue: responseLanguage) ?? .auto).label)
                            .font(AppFont.scaled(14))
                            .foregroundStyle(Color.primary.opacity(0.38))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(AppFont.caption)
                            .foregroundStyle(Color.primary.opacity(0.28))
                    }
                    .padding(.horizontal, AppSpacing.base)
                    .padding(.vertical, AppSpacing.md)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("aria_lang_title"))
                .accessibilityValue(Text((ARIAResponseLanguage(rawValue: responseLanguage) ?? .auto).label))

                rowDivider

                // Export — the stored history as a shareable JSON file.
                Button {
                    Task { await exportHistory() }
                } label: {
                    HStack(spacing: 12) {
                        ColoredIconBadge(icon: "square.and.arrow.up", color: .blue)
                        Text("Export conversation history")
                            .font(AppFont.scaled(15))
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

                // Delete — removes every stored aria_messages row.
                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    HStack(spacing: 12) {
                        ColoredIconBadge(icon: "trash.fill", color: .red)
                        Text("aria_delete_memory")
                            .font(AppFont.scaled(15))
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
            .liquidGlass(cornerRadius: AppRadius.xl)

            Text("aria_lang_footer \(assistantName)")
                .font(AppFont.scaled(12))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.leading, AppSpacing.sm)
                .padding(.top, 2)
        }
    }

    // MARK: - Appearance Section

    // The conversation's wallpaper/bubble theme moved here from the chat
    // toolbar — the assistant's header keeps one entry point (the name pill),
    // like a DM.
    private var appearanceSection: some View {
        settingsGroup("APPEARANCE") {
            Button {
                HapticFeedback.selection()
                showThemePicker = true
            } label: {
                HStack(spacing: 12) {
                    ColoredIconBadge(icon: "paintbrush.fill", color: .indigo)
                    Text("Chat background")
                        .font(AppFont.scaled(15))
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

    /// The real number of stored assistant messages (aria_messages rows).
    private func loadStoredMessageCount() async {
        do {
            let response: PostgrestResponse<Void> = try await supabase
                .from("aria_messages")
                .select("id", head: true, count: .exact)
                .execute()
            storedMessageCount = response.count ?? 0
        } catch {
            storedMessageCount = 0
        }
    }

    /// The context counts read live services; refresh any that haven't been
    /// loaded yet this session so the numbers are real, not stale zeros.
    private func refreshDomainCounts() async {
        if taskService.tasks.isEmpty { await taskService.load() }
        if financialService.records.isEmpty { await financialService.load() }
        if familyService.members.isEmpty { await familyService.load() }
        if plantService.plants.isEmpty, let propertyId = propertyService.primary?.id {
            await plantService.load(propertyId: propertyId)
        }
    }

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
            // Honest failure (IMG_9284): the old path swallowed the error AND
            // zeroed the count — a failed delete looked identical to success.
            HapticFeedback.error()
            clearSucceeded = false
            return
        }
        storedMessageCount = 0
        HapticFeedback.success()
        clearSucceeded = true
        // The open conversation resets to the welcome message right away.
        NotificationCenter.default.post(name: .ariaHistoryCleared, object: nil)
    }
}

extension Notification.Name {
    static let ariaHistoryCleared = Notification.Name("prvio.aria.historyCleared")
}
