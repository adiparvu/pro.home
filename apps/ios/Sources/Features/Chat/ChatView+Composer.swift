import SwiftUI

// MARK: - ChatView — composer (input bar + mention chips)
// (mechanically extracted from ChatView.swift; bodies unchanged).

extension ChatView {
    // MARK: - Input bar (the shared iMessage composer)

    var inputBar: some View {
        ChatComposerBar(
            // Inline edit reuses the same field — the binding swaps to the
            // edit text while an edit is active (identical to the old bar).
            text: editingMessage != nil ? $editText : $text,
            focused: $focused,
            isSending: isSending,
            config: ChatComposerConfig(
                onPlus: { showAttachmentSheet = true },
                onTyping: { messageService.sendTyping() },
                onSendText: {
                    // Fold the subject into the body BEFORE the send path runs
                    // (see MessageSubject) — sendText and the offline outbox
                    // then carry one opaque body, exactly as today. An empty
                    // subject encodes to the text unchanged.
                    if showSubjectField {
                        text = MessageSubject.encode(subject: subject, text: text)
                        subject = ""
                    }
                    Task { await sendText() }
                },
                onSendAudio: { url in Task { await sendAudio(url: url) } },
                onRecordingActivity: { messageService.sendRecording() },
                disappearingLabel: chatDisappearingChipLabel(ttl: ChatDisappearStore.ttl("group")),
                showsSubject: showSubjectField
            ),
            edit: editingMessage.map { m in
                // Editing rewrites the TEXT; a subject on the original message
                // is preserved verbatim through re-encoding on confirm.
                let original = MessageSubject.parse(m.body ?? "")
                return ChatComposerEdit(snippet: original.text) {
                    withAnimation { editingMessage = nil; editText = "" }
                } onConfirm: {
                    let newText = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !newText.isEmpty, newText != original.text {
                        let newBody = MessageSubject.encode(subject: original.subject ?? "",
                                                            text: newText)
                        Task { await messageService.editMessage(id: m.id, newBody: newBody) }
                    }
                    editingMessage = nil; editText = ""; focused = false
                }
            },
            subject: showSubjectField ? $subject : nil
        ) {
            mentionChips
        }
    }

    /// The pending @mention chips above the field (group-only accessory).
    @ViewBuilder private var mentionChips: some View {
        if !mentionedNames.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(zip(mentionedIds, mentionedNames)), id: \.0) { id, name in
                        HStack(spacing: 4) {
                            Text("@\(name)")
                                .font(AppFont.caption)
                                .foregroundStyle(Color.accentColor)
                            Button {
                                mentionedIds.removeAll { $0 == id }
                                mentionedNames.removeAll { $0 == name }
                            } label: {
                                Image(systemName: "xmark").font(AppFont.scaled(9, weight: .bold)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                            }
                            .accessibilityLabel("Remove mention of \(name)")
                        }
                        .padding(.horizontal, AppSpacing.sm).padding(.vertical, AppSpacing.xxs)
                        .background(.blue.opacity(0.15), in: Capsule())
                    }
                }
                .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.xs)
            }
        }
    }
}
