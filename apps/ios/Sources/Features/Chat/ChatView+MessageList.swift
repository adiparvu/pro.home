import SwiftUI
import Supabase

// MARK: - ChatView — message list, pinned banner and action
// overlay (mechanically extracted from ChatView.swift; bodies
// unchanged).

extension ChatView {
    /// What other members are doing right now (nil = idle). Recording wins
    /// over typing; the label carries who, since a group bubble alone is
    /// ambiguous with several senders.
    private var groupActivity: (kind: ChatActivityKind, label: String?)? {
        if !messageService.recordingNames.isEmpty {
            return (.recording, messageService.recordingNames.sorted().joined(separator: ", "))
        }
        if !messageService.typingNames.isEmpty {
            return (.typing, messageService.typingNames.sorted().joined(separator: ", "))
        }
        return nil
    }

    private func sameDay(_ a: Message, _ b: Message) -> Bool {
        let dA = a.date ?? Date()
        let dB = b.date ?? Date()
        return Calendar.current.isDate(dA, inSameDayAs: dB)
    }

    /// Scroll to a message (e.g. from tapping a reply's quote) and flash it. No-op
    /// if it isn't in the loaded window — older pages aren't force-loaded here.
    private func jumpToMessage(_ id: UUID) {
        guard filteredMessages.contains(where: { $0.id == id }) else { return }
        scrollTarget = id
        HapticFeedback.impact(.light)
        withAnimation(.easeInOut(duration: 0.25)) { highlightedMessageId = id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeInOut(duration: 0.4)) {
                if highlightedMessageId == id { highlightedMessageId = nil }
            }
        }
    }

    /// Messages after the "clear conversation" cutoff and disappearing-message
    /// rules, before any search filter. Shared by the list, pins and counts so
    /// none of them show messages the user has cleared or that have expired.
    private var visibleMessages: [Message] {
        // Memoized on the data revision + the two cutoff settings — the body
        // re-runs on every keystroke, and re-filtering the whole chat each
        // pass was the typing lag. The 30s bucket bounds staleness of the
        // time-relative disappearing cutoff between data changes.
        var hasher = Hasher()
        hasher.combine(messageService.revision)
        hasher.combine(ConversationClearStore.clearedAt("group"))
        hasher.combine(ChatDisappearStore.ttl("group"))
        hasher.combine(Int(Date().timeIntervalSince1970 / 30))
        return visibleCache.value(for: hasher.finalize()) {
            let kept = ConversationClearStore.filter(messageService.messages, convId: "group") { $0.date }
            return ChatDisappearStore.filter(kept, convId: "group") { $0.date }
        }
    }
    private var filteredMessages: [Message] {
        guard showSearch && !searchText.isEmpty else { return visibleMessages }
        return visibleMessages.filter {
            ($0.body ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    private var pinnedMessages: [Message] { visibleMessages.filter { $0.pinned == true && $0.deletedForAll != true } }

    @ViewBuilder
    func actionOverlay(_ m: Message) -> some View {
        let own = m.senderId == supabase.auth.currentSession?.user.id
        ChatActionOverlay(
            previewText: m.deletedForAll == true ? String(localized: "This message was deleted") : pinnedSnippet(m),
            isOwn: own,
            bubbleColor: chatTheme.id == "appDefault" ? Color.blue.opacity(0.75) : chatTheme.outgoingBubble,
            myReaction: messageService.reactions[m.id]?.first(where: { $0.userId == supabase.auth.currentSession?.user.id })?.emoji,
            onReact: { e in
                if let pid = propertyId {
                    Task { await messageService.toggleReaction(messageId: m.id, propertyId: pid, emoji: e, reactorName: senderName) }
                }
            },
            actions: messageActions(m),
            onDismiss: { withAnimation(.easeOut(duration: 0.2)) { menuMessage = nil } },
            imageStored: m.isImageMessage ? m.attachmentUrl : nil,
            audioStored: m.isAudioMessage ? m.attachmentUrl : nil,
            reactionsDisabled: m.deletedForAll == true
        )
        .transition(.opacity)
    }

    private func messageActions(_ m: Message) -> [ChatActionItem] {
        // A deleted message is just a tombstone: the only thing left to do
        // with it is remove it from your own view.
        if m.deletedForAll == true {
            return [ChatActionItem("Delete", "trash", destructive: true) { deleteCandidate = m }]
        }
        let own = m.senderId == supabase.auth.currentSession?.user.id
        var items: [ChatActionItem] = [
            ChatActionItem("Reply", "arrowshape.turn.up.left") { withAnimation(.spring(response: 0.3)) { replyingTo = m } },
            ChatActionItem("Forward", "arrowshape.turn.up.right") { forwardingMessage = m },
            ChatActionItem("Copy", "doc.on.doc") { if let b = m.body { UIPasteboard.general.string = MessageSubject.strip(b) } },
            ChatActionItem(m.isMarked == true ? "Unmark" : "Mark", "flag") { Task { await messageService.toggleMark(m) } },
            ChatActionItem(m.pinned == true ? "Unpin" : "Pin", "pin") { Task { await messageService.togglePin(m) } }
        ]
        if own, m.body?.isEmpty == false, m.attachmentType == nil {
            items.append(ChatActionItem("Edit", "pencil") {
                // Edit the TEXT only — a subject stays untouched (re-encoded
                // on confirm), and the marker never enters the field.
                editingMessage = m; editText = MessageSubject.parse(m.body ?? "").text
                replyingTo = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { focused = true }
            })
        }
        items.append(ChatActionItem("Delete", "trash", destructive: true) { deleteCandidate = m })
        return items
    }

    func pinnedSnippet(_ m: Message) -> String {
        // Normalized kind first, so a poll/event never shows its JSON body and
        // the label is localized (RO/EN) via the shared ChatMessageKind — not a
        // hardcoded English string as before.
        if let label = m.chatKind.previewLabel { return label }
        // One line, marker-free — a subject-bearing body reads "subject — text".
        if let b = m.body, !b.isEmpty { return MessageSubject.strip(b) }
        return String(localized: "Attachment")
    }

    // MARK: - Message list

    /// Arms the entry grace window once. `chatDidLoad` may only flip after the
    /// network refresh has had time to land; flipping it on the first count
    /// change let the refresh batch animate — the visible settle on entry.
    private func startLoadGraceIfNeeded() {
        guard chatLoadGraceTask == nil else { return }
        chatLoadGraceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            chatDidLoad = true
        }
    }

    var messageList: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if let pinned = pinnedMessages.last {
                    Button {
                        withAnimation { proxy.scrollTo(pinned.id, anchor: .center) }
                        HapticFeedback.impact(.light)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "pin.fill")
                                .font(AppFont.scaled(12))
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(pinnedMessages.count > 1
                                     ? String(format: String(localized: "%d pinned messages"), pinnedMessages.count)
                                     : String(localized: "Pinned message"))
                                    .font(AppFont.label)
                                    .foregroundStyle(Color.accentColor)
                                Text(pinnedSnippet(pinned))
                                    .font(AppFont.scaled(12))
                                    .foregroundStyle(Color.primary.opacity(0.6))
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                                Task { await messageService.togglePin(pinned) }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(AppFont.scaled(11, weight: .bold))
                                    .foregroundStyle(Color.primary.opacity(0.4))
                                    .frame(width: 26, height: 26)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Unpin message")
                        }
                        .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.sm)
                        .liquidGlass(cornerRadius: 14)
                        .padding(.horizontal, AppSpacing.lg).padding(.top, AppSpacing.sm)
                    }
                    .buttonStyle(.plain)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

            // Capture the list ONCE per render. `filteredMessages` is a computed
            // property that re-runs two filter passes on every access; the rows
            // below read neighbours (idx±1), which made scrolling O(n²). The
            // reply lookup gets the same treatment (dictionary instead of a
            // linear scan per bubble).
            let msgs = filteredMessages
            let messagesById = messagesByIdCache.value(for: messageService.revision) {
                Dictionary(messageService.messages.map { ($0.id, $0) },
                           uniquingKeysWith: { a, _ in a })
            }
            ScrollView(showsIndicators: false) {
                // The family chat used to render a silent black void both
                // while the first load was still in flight (slow network) and
                // when the conversation was genuinely empty/cleared — no
                // spinner, no words. Honest states for both (the DM thread
                // already had them).
                if msgs.isEmpty, !showSearch || searchText.isEmpty {
                    if messageService.isLoading && messageService.messages.isEmpty {
                        VStack(spacing: AppSpacing.md) {
                            ProgressView()
                            Text("Loading conversation…")
                                .font(AppFont.scaled(13))
                                .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 120)
                    } else {
                        EmptyStateView(icon: "bubble.left.and.bubble.right",
                                       title: "chat_empty_title",
                                       message: "chat_empty_subtitle")
                            .padding(.top, 80)
                    }
                }
                LazyVStack(spacing: 2) {
                    if messageService.hasMoreOlder && (!showSearch || searchText.isEmpty) {
                        Button {
                            if let pid = propertyId { Task { await messageService.loadOlder(propertyId: pid) } }
                        } label: {
                            if messageService.isLoadingOlder {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("Load older messages")
                                    .font(AppFont.scaled(13, weight: .medium))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.sm)
                        .disabled(messageService.isLoadingOlder)
                    }
                    if showSearch && !searchText.isEmpty && msgs.isEmpty {
                        EmptyStateView(icon: "magnifyingglass", title: "No results")
                            .padding(.top, AppSpacing.xxl)
                    }
                    ForEach(Array(msgs.enumerated()), id: \.element.id) { idx, msg in
                        let showDate = idx == 0 || !sameDay(msgs[idx - 1], msg)
                        // Consecutive messages from the same sender on the same day form a
                        // visual group: only the first shows the name, only the last the
                        // avatar. Searching yields a sparse subset, so grouping is disabled.
                        let grouping = !(showSearch && !searchText.isEmpty)
                        let prevSameSender = grouping && !showDate && idx > 0
                            && msgs[idx - 1].senderName == msg.senderName
                        let nextSameSender = grouping && idx < msgs.count - 1
                            && sameDay(msg, msgs[idx + 1])
                            && msgs[idx + 1].senderName == msg.senderName
                        if showDate {
                            ChatDateSeparator(dateStr: msg.createdAt)
                        }
                        if grouping, msg.id == unreadDividerId {
                            UnreadDivider().id("UNREAD_DIVIDER")
                        }
                        MessageBubble(
                            message: msg,
                            isOwn: msg.senderId == supabase.auth.currentSession?.user.id,
                            members: familyService.members,
                            outgoingColor: chatTheme.id == "appDefault" ? nil : chatTheme.outgoingBubble,
                            readers: messageService.reads[msg.id] ?? [],
                            deliverers: messageService.deliveries[msg.id] ?? [],
                            persistedReactions: {
                                let rows = messageService.reactions[msg.id] ?? []
                                return Dictionary(rows.map { ($0.emoji, 1) }, uniquingKeysWith: +)
                            }(),
                            persistedMyReaction: messageService.reactions[msg.id]?
                                .first(where: { $0.userId == supabase.auth.currentSession?.user.id })?.emoji,
                            onReact: { emoji in
                                guard let pid = propertyId else { return }
                                Task { await messageService.toggleReaction(
                                    messageId: msg.id, propertyId: pid,
                                    emoji: emoji, reactorName: senderName) }
                            },
                            repliedMessage: msg.replyTo.flatMap { messagesById[$0] },
                            onReply: { withAnimation(.spring(response: 0.3)) { replyingTo = msg } },
                            onPin: { Task { await messageService.togglePin(msg) } },
                            onMark: { Task { await messageService.toggleMark(msg) } },
                            onForward: { forwardingMessage = msg },
                            onEdit: {
                                editingMessage = msg; editText = MessageSubject.parse(msg.body ?? "").text
                                replyingTo = nil
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { focused = true }
                            },
                            onDeleteForEveryone: { Task { await messageService.deleteForEveryone(id: msg.id) } },
                            onDeleteForMe: { messageService.deleteForMe(id: msg.id) },
                            pollVotes: messageService.pollVotes[msg.id] ?? [],
                            myUserId: supabase.auth.currentSession?.user.id,
                            myAvatarURL: profileService.profile?.avatarUrl.flatMap { URL(string: $0) },
                            onPollVote: { idx in
                                guard let pid = propertyId else { return }
                                // Polls carry their multi flag in the body;
                                // event RSVPs are always single-choice.
                                let multi = ChatPoll.decode(msg.body)?.multi ?? false
                                Task { await messageService.togglePollVote(
                                    messageId: msg.id, propertyId: pid,
                                    optionIndex: idx, voterName: senderName, multi: multi) }
                            },
                            onLongPress: { menuMessage = msg },
                            isGroupStart: !prevSameSender,
                            isGroupEnd: !nextSameSender,
                            onQuotedTap: { if let rid = msg.replyTo { jumpToMessage(rid) } },
                            isHighlighted: highlightedMessageId == msg.id
                        )
                        .padding(.top, prevSameSender ? 0 : (showDate ? 0 : 6))
                        .id(msg.id)
                    }
                    // Pending (offline / in-flight / failed) messages — shown
                    // optimistically with a clock while queued, or a red badge +
                    // "tap to retry" once a send attempt has failed.
                    ForEach(pendingOutbox) { pm in
                        let pendingFill = chatTheme.id == "appDefault" ? Color.blue.opacity(0.75) : chatTheme.outgoingBubble
                        let failed = pm.state == .failed || !outbox.isOnline
                        VStack(alignment: .trailing, spacing: 2) {
                            HStack {
                                Spacer(minLength: 60)
                                HStack(spacing: 6) {
                                    Text(pm.previewText)
                                        .font(AppFont.scaled(15))
                                        .foregroundStyle(pendingFill.readableText)
                                    Image(systemName: failed ? "exclamationmark.circle" : "clock")
                                        .font(AppFont.scaled(10))
                                        .foregroundStyle(failed ? Color.brandDanger : pendingFill.readableText.opacity(0.75))
                                }
                                .padding(.horizontal, AppSpacing.base).padding(.vertical, 9)
                                .background(pendingFill,
                                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .opacity(0.85)
                                .onTapGesture { Task { await flushOutbox() } }
                                .contextMenu {
                                    Button { Task { await flushOutbox() } } label: {
                                        Label("Retry", systemImage: "arrow.clockwise")
                                    }
                                    Button(role: .destructive) { outbox.remove(pm.id) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                            if failed {
                                Text("Not delivered · tap to retry")
                                    .font(AppFont.scaled(10))
                                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                                    .padding(.trailing, AppSpacing.xxs)
                            }
                        }
                    }
                    // Live peer activity (typing / recording a voice message)
                    // as an incoming-side bubble, WhatsApp style — labelled
                    // with who, since a group bubble alone is ambiguous.
                    if let activity = groupActivity {
                        HStack {
                            ChatActivityBubble(kind: activity.kind, label: activity.label)
                            Spacer(minLength: 60)
                        }
                        .padding(.top, 6)
                        .transition(.scale(scale: 0.85, anchor: .bottomLeading)
                            .combined(with: .opacity))
                    }
                    // Jump-button + at-bottom sentinel. The compose bar now
                    // rides in the safe-area inset (like the DM thread), so the
                    // scroll view gains the matching bottom inset automatically
                    // and this marker no longer needs to reserve bar clearance.
                    // On iOS 18+ the live scroll geometry (chatAtBottomTracking
                    // below) owns the at-bottom state and the jump button —
                    // lazy-window appearance is NOT viewport visibility, and
                    // the stale flag used to block auto-follow while the
                    // reader sat at the bottom. The sentinel callbacks survive
                    // purely as the pre-iOS-18 fallback.
                    Color.clear.frame(height: 1)
                        .id("CHAT_BOTTOM")
                        .onAppear {
                            // A mounting sentinel is honest in one direction
                            // only: lazy pre-mount fires near (not at) the
                            // bottom, never up-thread — hiding the jump button
                            // here is safe on every OS and corrects any stale
                            // geometry emission. isAtBottom stays geometry-
                            // owned (pre-mount is not visibility; auto-follow
                            // must never yank an up-thread reader).
                            withAnimation(.easeInOut(duration: 0.2)) { scroll.showJumpToLatest = false }
                            guard !ChatAtBottomModifier.isGeometryDriven else { return }
                            isAtBottom = true
                        }
                        .onDisappear {
                            guard !ChatAtBottomModifier.isGeometryDriven else { return }
                            isAtBottom = false
                            withAnimation(.easeInOut(duration: 0.2)) { scroll.showJumpToLatest = true }
                        }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.sm)
                .padding(.bottom, AppSpacing.lg)
                .animation(animateMessageDelta ? .spring(response: 0.35, dampingFraction: 0.86) : nil, value: msgs.count)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.immediately)
            // Live at-bottom detection (iOS 18+): drives auto-follow and the
            // jump button from real viewport geometry instead of the
            // lazy-culled sentinel. The compose bar's safe-area inset counts
            // into contentInsets.bottom, so the default one-bubble threshold
            // matches the DM thread.
            .chatAtBottomTracking { atBottom in
                // The two states are guarded separately: the sentinel's
                // onAppear may hide the button without touching isAtBottom,
                // so a single shared guard would swallow the emission that
                // should bring the button back.
                if atBottom != isAtBottom { isAtBottom = atBottom }
                if scroll.showJumpToLatest != !atBottom {
                    withAnimation(.easeInOut(duration: 0.2)) { scroll.showJumpToLatest = !atBottom }
                }
            }
            .animation(.snappy(duration: 0.25), value: groupActivity?.kind)
            .onChange(of: groupActivity?.kind) { _, kind in
                // The bubble grows the content below the viewport — a reader
                // sitting at the bottom should see it appear, never have to
                // chase it. Up-thread readers are left alone (same contract
                // as message auto-follow).
                guard kind != nil, isAtBottom else { return }
                withAnimation(.snappy(duration: 0.25)) {
                    proxy.scrollTo("CHAT_BOTTOM", anchor: .bottom)
                }
            }
            .onChange(of: isAtBottom) { _, atBottom in
                // Returning to the bottom is the honest "I've now seen these"
                // moment for messages that arrived while reading up-thread.
                // The receipt upsert pushes over realtime, so the sender's
                // ticks flip to "seen" instantly.
                guard atBottom, chatDidLoad, let pid = propertyId else { return }
                Task { await messageService.markRead(propertyId: pid, readerName: senderName) }
            }
            .onChange(of: messageService.messages.count) { old, new in
                guard new > 0 else { return }
                // Decide the animation for THIS change — onChange runs ahead
                // of the body pass that renders it. Spring only small deltas
                // once entry has settled; the network refresh replacing the
                // in-memory page and "load older" pages must land unanimated
                // (a springing bulk merge reads as the whole chat settling).
                animateMessageDelta = chatDidLoad && abs(new - old) <= 3
                startLoadGraceIfNeeded()
                let newest = messageService.messages.last?.id
                let appended = newest != newestMessageId
                newestMessageId = newest
                // Prepends (older pages) keep the reading position; only
                // appends may move the viewport.
                let ownLatest = messageService.messages.last?.senderId
                    == supabase.auth.currentSession?.user.id
                if appended {
                    if !chatDidLoad {
                        // Entry batches: snap straight to the bottom rest,
                        // then re-assert once the lazy rows take their real
                        // heights — the estimated first pass can leave the
                        // newest bubble half-hidden behind the composer
                        // (IMG_8284).
                        proxy.scrollTo("CHAT_BOTTOM", anchor: .bottom)
                        scroll.hide()
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(0.45))
                            if !chatDidLoad || isAtBottom {
                                proxy.scrollTo("CHAT_BOTTOM", anchor: .bottom)
                            }
                        }
                    } else if isAtBottom || ownLatest {
                        // Follow new messages only when already at the bottom
                        // or when we sent it — never yank a reader up-thread.
                        // Gated on the geometry-backed at-bottom state, NOT
                        // the debounced jump-button flag, whose staleness used
                        // to strand the newest message below the fold.
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                            proxy.scrollTo("CHAT_BOTTOM", anchor: .bottom)
                        }
                        // We just parked at the bottom: hide the jump button
                        // explicitly. The geometry signal only re-emits on a
                        // bucket CHANGE, so a programmatic snap that doesn't
                        // cross a bucket boundary used to leave it stranded
                        // visible (IMG_8303).
                        scroll.hide()
                    }
                }
                if let pid = propertyId {
                    // Delivery is device truth (it arrived here) — always.
                    // Read is claimed only when the reader is actually at the
                    // bottom (or just sent a message); scrolling back down
                    // stamps it via the isAtBottom onChange above.
                    Task {
                        await messageService.markDelivered(propertyId: pid, delivererName: senderName)
                        if !chatDidLoad || isAtBottom || ownLatest {
                            await messageService.markRead(propertyId: pid, readerName: senderName)
                        }
                    }
                }
            }
            .onAppear {
                // defaultScrollAnchor(.bottom) already rests on the newest
                // message from the first frame — no corrective jump here.
                newestMessageId = messageService.messages.last?.id
                if !messageService.messages.isEmpty { startLoadGraceIfNeeded() }
            }
            .onChange(of: unreadDividerId) { _, id in
                // Set once, right after the first load completes. (An onAppear
                // check ran before the id existed — dead on entry — and fired
                // again when navigating back from group info, yanking the list
                // to the divider mid-session.)
                guard id != nil else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    proxy.scrollTo("UNREAD_DIVIDER", anchor: .top)
                }
            }
            .onChange(of: scrollTarget) { _, target in
                guard let t = target else { return }
                withAnimation { proxy.scrollTo(t, anchor: .center) }
                scrollTarget = nil
            }
            } // end VStack (search + scroll)
            .overlay(alignment: .bottomTrailing) {
                if scroll.showJumpToLatest {
                    Button {
                        // Idempotent: re-taps mid-flight are ignored instead of
                        // restarting the spring (each restart read as a nudge).
                        guard !isJumpingToLatest else { return }
                        isJumpingToLatest = true
                        HapticFeedback.impact(.light)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            proxy.scrollTo("CHAT_BOTTOM", anchor: .bottom)
                        }
                        // LazyVStack estimates offsets for distant targets, so
                        // one animated pass can land short of the true bottom —
                        // which used to demand a second or third press. Once
                        // the spring settles, re-assert the anchor; a no-op if
                        // the first pass already landed.
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(0.45))
                            if scroll.showJumpToLatest {
                                proxy.scrollTo("CHAT_BOTTOM", anchor: .bottom)
                            }
                            isJumpingToLatest = false
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(AppFont.scaled(13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .glassCircle()
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                    .padding(.trailing, AppSpacing.lg).padding(.bottom, AppSpacing.md)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Jump to latest message")
                }
            }
        } // end ScrollViewReader
    }
}
