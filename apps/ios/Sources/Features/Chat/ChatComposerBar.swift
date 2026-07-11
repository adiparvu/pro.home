// The ONE chat composer bar — shared by the DM thread, the main group chat
// and every community group (which reuses ChatView). Visually it is the
// iMessage input bar, faithfully: a round "+" in clear Liquid Glass on the
// left, one slim rounded field holding the text and the trailing control
// INSIDE it (the dictation-style mic when empty, the filled send arrow while
// typing — morphing with a spring), the whole row resting on a `.bar`
// material above the home indicator. Capabilities are switched per surface
// through `ChatComposerConfig`: a nil action simply hides its control, so
// each surface renders exactly the features it supports without forking the
// component.
import SwiftUI
import UIKit

// MARK: - Configuration

/// Capability flags/actions for a chat surface. nil hides the control.
struct ChatComposerConfig {
    /// Placeholder inside the text field. iMessage's field says "Mesaj" with
    /// no trailing ellipsis — matching it exactly is a standing requirement.
    var placeholder: LocalizedStringKey = "Message"
    /// Opens the "+" attachment menu (the surface presents its own
    /// ChatAttachmentSheet overlay so the dim can cover the whole screen).
    /// nil hides the + button.
    var onPlus: (() -> Void)? = nil
    /// Throttled typing signal (at most once per `typingThrottle`) — wired to
    /// the surface's realtime typing broadcast.
    var onTyping: (() -> Void)? = nil
    /// Sends the current text. The surface owns the text binding, so the
    /// closure reads/clears it itself (matches the existing send paths).
    var onSendText: () -> Void = {}
    /// Sends a finished voice clip. nil hides the mic — the surface has no
    /// voice messages.
    var onSendAudio: ((URL) -> Void)? = nil
    /// Formatted disappearing-messages duration ("24 hr") when the surface
    /// has an active timer — shows the small timer chip above the field.
    var disappearingLabel: String? = nil
    /// Seconds between typing signals.
    var typingThrottle: TimeInterval = 2
    /// AI surfaces (Yuna): speech-to-text INTO the field, instead of the
    /// voice-clip recorder. When set, the empty-field control dictates.
    var dictation: ChatComposerDictation? = nil
    /// AI surfaces: true while the assistant is answering — the trailing
    /// control becomes a stop button wired to `onStopResponding`.
    var isResponding: Bool = false
    var onStopResponding: (() -> Void)? = nil
}

/// Speech-to-text state + trigger for the composer's dictation control.
struct ChatComposerDictation {
    let isListening: Bool
    let onTap: () -> Void
}

/// Reply-to context shown as the strip above the field.
struct ChatComposerReply {
    let sender: String
    let snippet: String
    let onCancel: () -> Void
}

/// Inline edit context (the group chat edits in the composer): the strip
/// above the field plus the checkmark confirm control inside it.
struct ChatComposerEdit {
    let snippet: String
    let onCancel: () -> Void
    /// Commits the edit. The surface owns the edit-text binding (it passes it
    /// as the bar's `text`), so the closure reads/clears it itself.
    let onConfirm: () -> Void
}

// MARK: - Composer bar

struct ChatComposerBar<Accessory: View>: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    var isSending: Bool = false
    let config: ChatComposerConfig
    var reply: ChatComposerReply? = nil
    var edit: ChatComposerEdit? = nil
    /// Surface-specific strip above the compose row (the group chat's mention
    /// chips). EmptyView when the surface has none.
    @ViewBuilder var accessory: () -> Accessory

    /// The bar owns the whole voice-message flow (record → review → send);
    /// surfaces only receive the finished clip via `onSendAudio`.
    @State private var audioRecorder = ChatAudioRecorder()
    @State private var lastTypingSent = Date.distantPast

    private var isTextEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// How far the bar sinks into the bottom safe area while the keyboard is
    /// away. The surfaces mount the bar as a bottom `safeAreaInset`, which
    /// places it ABOVE the whole home-indicator inset (~34pt) — added to the
    /// row's own `AppSpacing.sm`, that painted a tall empty `.bar` band
    /// between the pill and the home indicator. iMessage instead rests the
    /// pill ~8pt above the indicator, whose top edge sits ~13pt from the
    /// physical screen bottom: overlapping by (inset − 13) leaves exactly
    /// the row's 8pt of breathing room above it. Devices without a home
    /// indicator report inset 0 → no overlap, nothing changes for them.
    private var homeIndicatorOverlap: CGFloat {
        let inset = (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom) ?? 0
        return max(inset - 13, 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let edit {
                editStrip(edit)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let reply {
                ChatReplyBanner(sender: reply.sender, snippet: reply.snippet,
                                onCancel: reply.onCancel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            accessory()
            if let label = config.disappearingLabel {
                disappearingChip(label)
            }

            if audioRecorder.isRecording {
                // iMessage: the whole compose row becomes the recording pill —
                // live waveform, red timer, red stop. Stop parks the clip for
                // review; nothing sends yet.
                VoiceRecordingPill(recorder: audioRecorder) {
                    audioRecorder.finishRecording()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                .padding(.horizontal, AppSpacing.base)
                .padding(.vertical, AppSpacing.sm)
            } else if let voicePreview = audioRecorder.preview {
                // iMessage review: ✕ discards, play auditions, the arrow sends.
                VoiceReviewRow(preview: voicePreview, isSending: isSending) {
                    audioRecorder.discardPreview()
                } onSend: {
                    if let clip = audioRecorder.takePreview() {
                        config.onSendAudio?(clip.url)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                .padding(.horizontal, AppSpacing.base)
                .padding(.vertical, AppSpacing.sm)
            } else {
                composeRow
            }
        }
        // iMessage geometry: with the keyboard away the row sinks into the
        // bottom safe area (negative padding shrinks the inset the exact
        // amount the content overflows, so the scroll inset stays correct)
        // and the pill rests ~8pt above the home indicator instead of above
        // the whole indicator band. While the keyboard is up the bottom safe
        // area belongs to the keyboard, so the overlap must vanish — the
        // pill then sits its usual 8pt above the keyboard.
        .padding(.bottom, focused.wrappedValue ? 0 : -homeIndicatorOverlap)
        // A proper bar material so the compose row stays legible over any
        // wallpaper (a bare glass pill on its own read as near-transparent).
        // `.bar` turns opaque automatically under Reduce Transparency, and
        // bleeds into the remaining safe area on its own, so the band covers
        // exactly the bar + safe area — no gap, no extra band.
        .background(.bar)
        .animation(.snappy(duration: 0.25), value: focused.wrappedValue)
        .animation(.spring(duration: 0.3), value: reply?.snippet)
        .animation(.spring(duration: 0.3), value: edit?.snippet)
        .animation(.snappy(duration: 0.25), value: audioRecorder.isRecording)
        .animation(.snappy(duration: 0.25), value: audioRecorder.preview)
    }

    // MARK: Compose row (the iMessage bar)

    private var composeRow: some View {
        HStack(alignment: .bottom, spacing: AppSpacing.sm) {
            if config.onPlus != nil { plusButton }

            HStack(alignment: .bottom, spacing: AppSpacing.sm) {
                TextField(config.placeholder, text: $text, axis: .vertical)
                    .font(AppFont.scaled(16))
                    .foregroundStyle(.primary)
                    .tint(.accentColor)
                    .lineLimit(1...6)
                    .focused(focused)
                    .padding(.vertical, 7)
                    .onChange(of: text) { _, val in
                        // The keyboard's return key must be inert while the
                        // pill is empty (IMG_8285): on a vertical-axis field
                        // it would otherwise stack invisible blank lines.
                        // Whitespace-only content snaps straight back to
                        // empty — the SwiftUI equivalent of UIKit's
                        // enablesReturnKeyAutomatically.
                        if !val.isEmpty,
                           val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            text = ""
                            return
                        }
                        let now = Date()
                        if !val.isEmpty,
                           now.timeIntervalSince(lastTypingSent) > config.typingThrottle {
                            lastTypingSent = now
                            config.onTyping?()
                        }
                        // Draft persistence is the surface's job (on disappear) —
                        // a per-keystroke UserDefaults write is typing lag.
                    }

                trailingControl
                    .padding(.bottom, 3)
            }
            .animation(.spring(duration: 0.2), value: isTextEmpty)
            .animation(.spring(duration: 0.2), value: config.isResponding)
            .padding(.leading, 14)
            .padding(.trailing, 5)
            .mediaGlass(in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.sm)
        // iMessage has no separate band behind the compose row — the bar sits
        // directly on the conversation background (the `.bar` material above).
    }

    /// The control inside the pill's trailing edge: the edit checkmark while
    /// editing, the filled send arrow while there is text, otherwise the
    /// dictation-style mic (when the surface supports voice messages).
    @ViewBuilder private var trailingControl: some View {
        if let edit {
            Button {
                edit.onConfirm()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(AppFont.scaled(28))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(isTextEmpty)
            .accessibilityLabel("Confirm edit")
        } else if config.isResponding, let onStop = config.onStopResponding {
            Button(action: onStop) {
                Image(systemName: "stop.circle.fill")
                    .font(AppFont.scaled(28))
                    .foregroundStyle(.white, Color.accentColor)
            }
            .buttonStyle(.plain)
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel("Stop")
        } else if !isTextEmpty {
            sendButton
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.7).combined(with: .opacity),
                    removal: .scale(scale: 0.7).combined(with: .opacity)
                ))
        } else if let dictation = config.dictation {
            dictationButton(dictation)
        } else if config.onSendAudio != nil {
            micButton
        }
    }

    /// iMessage's dictation glyph, red and pulsing while listening — taps
    /// toggle the surface's speech-to-text (Yuna).
    private func dictationButton(_ dictation: ChatComposerDictation) -> some View {
        Button(action: dictation.onTap) {
            Image(systemName: "waveform")
                .font(AppFont.scaled(17, weight: .medium))
                .foregroundStyle(dictation.isListening
                    ? Color.red
                    : Color.primary.opacity(AppOpacity.disabled))
                .symbolEffect(.pulse, isActive: dictation.isListening)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dictation.isListening ? "Stop voice input" : "Voice input")
    }

    private var plusButton: some View {
        Button {
            focused.wrappedValue = false
            config.onPlus?()
        } label: {
            Image(systemName: "plus")
                .font(AppFont.scaled(17, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                // Clear Liquid Glass on iOS 26; legible material fallback
                // earlier (a flat fill vanished against same-brightness
                // wallpapers).
                .mediaGlass(in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add attachment")
    }

    private var sendButton: some View {
        Button {
            guard !isTextEmpty else { return }
            config.onSendText()
        } label: {
            if isSending {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.accentColor))
            } else {
                Image(systemName: "arrow.up.circle.fill")
                    .font(AppFont.scaled(28))
                    .foregroundStyle(.white, Color.accentColor)
            }
        }
        .buttonStyle(.plain)
        .disabled(isSending)
        .accessibilityLabel(Text("Send"))
    }

    // iMessage-style: the dictation waveform glyph (vertical bars) inside the
    // field, no chrome — tap to start recording; the pill becomes the
    // recording surface.
    private var micButton: some View {
        Button {
            focused.wrappedValue = false
            audioRecorder.start()
            HapticFeedback.impact(.medium)
        } label: {
            Image(systemName: "waveform")
                .font(AppFont.scaled(17, weight: .medium))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Record voice message"))
    }

    // MARK: Strips

    private func editStrip(_ edit: ChatComposerEdit) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "pencil")
                .font(AppFont.footnoteEmphasis)
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text("Edit message")
                    .font(AppFont.label).foregroundStyle(Color.accentColor)
                Text(edit.snippet)
                    .font(AppFont.scaled(12))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer()
            Button(action: edit.onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(AppFont.scaled(16))
                    .foregroundStyle(Color.primary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel edit")
        }
        .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.sm)
        .background(Color.primary.opacity(0.05))
    }

    /// Slim, centered timer chip — the quiet reminder that new messages in
    /// this conversation disappear after the configured duration.
    private func disappearingChip(_ label: String) -> some View {
        HStack(spacing: AppSpacing.xxs) {
            Image(systemName: "timer")
                .font(AppFont.scaled(10, weight: .semibold))
            Text(label)
                .font(AppFont.scaled(11, weight: .medium))
        }
        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
        .padding(.horizontal, AppSpacing.sm).padding(.vertical, 3)
        .background(Color.primary.opacity(AppOpacity.hairline), in: Capsule())
        .padding(.top, AppSpacing.xs)
        .accessibilityLabel(Text(String(format: String(localized: "composer_disappearing_a11y"), label)))
    }
}

extension ChatComposerBar where Accessory == EmptyView {
    /// Convenience for surfaces without an accessory strip (the DM thread).
    init(text: Binding<String>,
         focused: FocusState<Bool>.Binding,
         isSending: Bool = false,
         config: ChatComposerConfig,
         reply: ChatComposerReply? = nil,
         edit: ChatComposerEdit? = nil) {
        self.init(text: text, focused: focused, isSending: isSending,
                  config: config, reply: reply, edit: edit) { EmptyView() }
    }
}

// MARK: - Disappearing duration label

/// Formats an active disappearing-messages TTL the iOS-Settings way
/// ("24 hr", "7 days"); nil when the timer is off — the chip then hides.
func chatDisappearingChipLabel(ttl: TimeInterval) -> String? {
    guard ttl > 0 else { return nil }
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = ttl >= 86_400 ? [.day] : (ttl >= 3_600 ? [.hour] : [.minute])
    formatter.unitsStyle = .short
    return formatter.string(from: ttl)
}
