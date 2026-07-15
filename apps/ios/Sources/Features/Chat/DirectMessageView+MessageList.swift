import SwiftUI
import UIKit

// MARK: - DirectMessageView — message list, pinned banner,
// action overlay and empty state (mechanically extracted from
// DirectMessageView.swift; bodies unchanged).

extension DirectMessageView {
    private var displayedMessages: [DirectMessage] {
        let all = conversationMessages
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Searching scans the whole conversation; browsing renders only the
        // most-recent window so a long history doesn't build thousands of rows.
        guard !q.isEmpty else { return Array(all.suffix(visibleCount)) }
        return all.filter { $0.body.localizedCaseInsensitiveContains(q) }
    }

    /// What the peer is doing right now (nil = idle). Recording wins over
    /// typing — the recorder replaces the keyboard, so both can't be true.
    private var peerActivity: ChatActivityKind? {
        if directMessageService.recordingNames.contains(where: matchesPeer) { return .recording }
        if directMessageService.typingNames.contains(where: matchesPeer) { return .typing }
        return nil
    }

    /// Flash a message briefly after jumping to it from a reply.
    private func flashHighlight(_ id: UUID) {
        HapticFeedback.impact(.light)
        withAnimation(.easeInOut(duration: 0.25)) { highlightedId = id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeInOut(duration: 0.4)) {
                if highlightedId == id { highlightedId = nil }
            }
        }
    }

    /// True when older messages exist beyond the current render window —
    /// either already in memory or still on the server.
    private var hasMoreOlder: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (conversationMessages.count > visibleCount
                || (!conversationMessages.isEmpty
                    && !directMessageService.exhaustedOlder.contains(thread.storeKey)))
    }

    private var pinnedMessages: [DirectMessage] {
        conversationMessages.filter { $0.pinned == true && $0.deletedForAll != true }
    }

    /// RSVP handler for a DM event bubble — nil (no chips, no dead controls)
    /// until the property id exists; toggles through DMVoteStore's
    /// single-choice semantics.
    private func dmRSVPHandler(for msg: DirectMessage) -> ((Int) -> Void)? {
        guard let pid = propertyService.primary?.id else { return nil }
        let name = myName
        return { option in
            Task {
                await DMVoteStore.shared.toggle(
                    messageId: msg.id, propertyId: pid,
                    optionIndex: option, voterName: name)
            }
        }
    }

    @ViewBuilder
    func dmActionOverlay(_ m: DirectMessage) -> some View {
        let own = m.isMine(myUserId: directMessageService.myUserId, myName: myName)
        let isImage = m.deletedForAll != true && ChatMedia.dmBodyKind(m.body) == .image
        let isAudio = m.deletedForAll != true && ChatMedia.dmBodyKind(m.body) == .audio
        ChatActionOverlay(
            previewText: m.previewSnippet,
            isOwn: own,
            bubbleColor: chatTheme.id == "appDefault" ? Color.imessageBlue : chatTheme.outgoingBubble,
            myReaction: m.myReaction(myUserId: directMessageService.myUserId, myName: myName),
            onReact: { e in Task { await directMessageService.toggleReaction(m, emoji: e, myName: myName) } },
            actions: dmMessageActions(m, own: own),
            onDismiss: { withAnimation(.easeOut(duration: 0.2)) { menuMessage = nil } },
            imageStored: isImage ? m.body : nil,
            audioStored: isAudio ? m.body : nil,
            reactionsDisabled: m.deletedForAll == true
        )
        .transition(.opacity)
    }

    private func dmMessageActions(_ m: DirectMessage, own: Bool) -> [ChatActionItem] {
        // Deleted messages keep only "Delete" (remove the tombstone for me).
        if m.deletedForAll == true {
            return [ChatActionItem("Delete", "trash", destructive: true) { deleteCandidate = m }]
        }
        // Structured bodies (media, contact card, or a marker-encoded
        // location/sticker/event/file) must not be editable as raw text.
        let isStructured = ChatMedia.dmBodyKind(m.body) != .text
            || m.isContactShare || DMRich.decode(m.body) != nil
        var items: [ChatActionItem] = [
            ChatActionItem("Reply", "arrowshape.turn.up.left") { withAnimation { replyingTo = m } },
            ChatActionItem("Forward", "arrowshape.turn.up.right") { forwarding = m },
            ChatActionItem("Copy", "doc.on.doc") { UIPasteboard.general.string = MessageSubject.strip(m.body) },
            ChatActionItem(m.isMarked == true ? "Unmark" : "Mark", "flag") { Task { await directMessageService.toggleMark(m) } },
            ChatActionItem(m.pinned == true ? "Unpin" : "Pin", "pin") { Task { await directMessageService.togglePin(m) } },
            // Message details now live in the long-press menu (moved off the
            // left-swipe, which peeks the send time iMessage-style).
            ChatActionItem("Details", "info.circle") { detailsMessage = m },
            // Enter iMessage-style multi-select, this message pre-checked.
            ChatActionItem("Select", "checkmark.circle") { enterSelection(m) }
        ]
        if own, m.deletedForAll != true, !isStructured {
            // Edit the TEXT only — a subject stays untouched (re-encoded on
            // save), and the marker never enters the field.
            items.append(ChatActionItem("Edit", "pencil") {
                editingMessage = m; editText = MessageSubject.parse(m.body).text
            })
        }
        items.append(ChatActionItem("Delete", "trash", destructive: true) { deleteCandidate = m })
        return items
    }

    // MARK: - Message List

    var messageList: some View {
        VStack(spacing: 0) {
        if let pinned = pinnedMessages.last {
            Button {
                scrollTarget = pinned.id
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
                        Text(pinned.previewSnippet)
                            .font(AppFont.scaled(12))
                            .foregroundStyle(Color.primary.opacity(0.6))
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        Task { await directMessageService.togglePin(pinned) }
                    } label: {
                        Image(systemName: "xmark")
                            .font(AppFont.scaled(11, weight: .bold))
                            .foregroundStyle(Color.primary.opacity(0.4))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Unpin message"))
                }
                .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.sm)
                .liquidGlass(cornerRadius: 14)
                .padding(.horizontal, AppSpacing.md).padding(.top, AppSpacing.sm)
            }
            .buttonStyle(.plain)
        }
        ScrollViewReader { proxy in
            Group {
                if conversationMessages.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    let shown = displayedMessages
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 2) {
                            if hasMoreOlder {
                                Button {
                                    // Anchor the current top message so inserting
                                    // an older page above it doesn't jump the view.
                                    let anchor = shown.first?.id
                                    let target = visibleCount + Self.pageSize
                                    if target > conversationMessages.count,
                                       let pid = propertyService.primary?.id {
                                        // The window outgrew memory — pull the
                                        // next older page from the server first.
                                        Task {
                                            await directMessageService.loadOlder(
                                                propertyId: pid, myName: myName, thread: thread)
                                            visibleCount = target
                                            if let anchor { proxy.scrollTo(anchor, anchor: .top) }
                                        }
                                    } else {
                                        visibleCount = target
                                        if let anchor {
                                            DispatchQueue.main.async {
                                                proxy.scrollTo(anchor, anchor: .top)
                                            }
                                        }
                                    }
                                } label: {
                                    if directMessageService.isLoadingOlder {
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
                                .disabled(directMessageService.isLoadingOlder)
                            }
                            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                               shown.isEmpty {
                                EmptyStateView(icon: "magnifyingglass", title: "No results")
                                    .padding(.top, AppSpacing.xxl)
                            }
                            ForEach(Array(shown.enumerated()), id: \.element.id) { idx, msg in
                                let isOwn = msg.isMine(myUserId: directMessageService.myUserId, myName: myName)
                                // While searching, `shown` is a sparse subset, so adjacency-based
                                // grouping is meaningless — show each result as a standalone bubble.
                                let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                // Tail on the last bubble of a same-sender run (or when the
                                // next message starts a new day) — matches the group chat.
                                let nextSameSender = !isSearching && idx < shown.count - 1
                                    && shown[idx + 1].senderName == msg.senderName
                                    && sameDay(msg, shown[idx + 1])
                                let showDate = idx == 0 || !sameDay(shown[idx - 1], msg)
                                // First bubble of a same-sender run — drives the
                                // incoming sender-name label for unknown peers.
                                let prevSameSender = !isSearching && !showDate && idx > 0
                                    && shown[idx - 1].senderName == msg.senderName

                                if showDate {
                                    ChatDateSeparator(dateStr: msg.createdAt)
                                        .padding(.top, idx == 0 ? 8 : 16)
                                }
                                if !isSearching, msg.id == unreadDividerId {
                                    UnreadDivider().id("UNREAD_DIVIDER")
                                }

                                DMBubble(
                                    message: msg,
                                    isOwn: isOwn,
                                    hasTail: !nextSameSender,
                                    isFirstInRun: !prevSameSender,
                                    myName: myName,
                                    myUserId: directMessageService.myUserId,
                                    partner: member,
                                    partnerAvatarURL: peerAvatarURL,
                                    partnerInitials: peerInitials,
                                    partnerColor: peerColor,
                                    members: familyService.members,
                                    myAvatarURL: profileService.profile?.avatarUrl.flatMap { URL(string: $0) },
                                    outgoingColor: chatTheme.id == "appDefault" ? nil : chatTheme.outgoingBubble,
                                    repliedMessage: msg.replyTo.flatMap { rid in
                                        conversationMessages.first { $0.id == rid }
                                    },
                                    onReact: { emoji in
                                        Task { await directMessageService.toggleReaction(msg, emoji: emoji, myName: myName) }
                                    },
                                    onReply: { withAnimation { replyingTo = msg } },
                                    onForward: { forwarding = msg },
                                    onEdit: isOwn ? { editingMessage = msg; editText = MessageSubject.parse(msg.body).text } : nil,
                                    onPin: { Task { await directMessageService.togglePin(msg) } },
                                    onMark: { Task { await directMessageService.toggleMark(msg) } },
                                    onDeleteForEveryone: { Task { await directMessageService.deleteForEveryone(id: msg.id) } },
                                    onDeleteForMe: { directMessageService.deleteForMe(id: msg.id) },
                                    onLongPress: { menuMessage = msg },
                                    onQuotedTap: {
                                        guard let rid = msg.replyTo,
                                              displayedMessages.contains(where: { $0.id == rid }) else { return }
                                        withAnimation { proxy.scrollTo(rid, anchor: .center) }
                                        flashHighlight(rid)
                                    },
                                    isHighlighted: highlightedId == msg.id,
                                    pollVotes: DMVoteStore.shared.votes[msg.id] ?? [],
                                    onRSVP: dmRSVPHandler(for: msg)
                                )
                                .chatSelectable(active: selecting,
                                                selected: selectedIDs.contains(msg.id)) {
                                    toggleSelect(msg.id)
                                }
                                .id(msg.id)
                            }
                            ForEach(pendingOutbox) { pm in
                                let pendingFill = chatTheme.id == "appDefault" ? Color.imessageBlue : chatTheme.outgoingBubble
                                let failed = pm.state == .failed || !outbox.isOnline
                                VStack(alignment: .trailing, spacing: 2) {
                                    HStack {
                                        Spacer(minLength: 72)
                                        HStack(spacing: 6) {
                                            Text(pm.previewText)
                                                .font(AppFont.scaled(15))
                                                .foregroundStyle(pendingFill.readableText)
                                            Image(systemName: failed ? "exclamationmark.circle" : "clock")
                                                .font(AppFont.scaled(10))
                                                .foregroundStyle(failed ? Color.brandDanger : pendingFill.readableText.opacity(0.75))
                                        }
                                        .padding(.horizontal, 13).padding(.vertical, 9)
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
                            // Live peer activity (typing / recording a voice
                            // message) as an incoming-side bubble, WhatsApp
                            // style — same broadcast the header subtitle uses.
                            if let activity = peerActivity {
                                HStack {
                                    ChatActivityBubble(kind: activity)
                                    Spacer(minLength: 72)
                                }
                                .padding(.top, 2)
                                .transition(.scale(scale: 0.85, anchor: .bottomLeading)
                                    .combined(with: .opacity))
                            }
                            // Jump-button + at-bottom sentinel. On iOS 18+ the
                            // live scroll geometry (chatAtBottomTracking below)
                            // owns both signals — the sentinel's lazy-window
                            // appearance is NOT viewport visibility and went
                            // stale (keyboard presentation or a tall incoming
                            // bubble culled it while the reader sat at the
                            // bottom, which blocked auto-follow until a manual
                            // scroll). It survives purely as the pre-iOS-18
                            // fallback, debounced via setJumpToLatest.
                            Color.clear.frame(height: 1).id("DM_BOTTOM")
                                .onAppear {
                                    // A mounting sentinel is honest in one
                                    // direction only: lazy pre-mount can fire
                                    // this near (not at) the bottom, never
                                    // up-thread — so hiding the jump button
                                    // here is safe on every OS and corrects
                                    // any stale geometry emission. isAtBottom
                                    // stays geometry-owned (pre-mount is not
                                    // visibility; auto-follow must never yank
                                    // an up-thread reader).
                                    scroll.setJumpToLatest(false)
                                    guard !ChatAtBottomModifier.isGeometryDriven else { return }
                                    isAtBottom = true
                                }
                                .onDisappear {
                                    guard !ChatAtBottomModifier.isGeometryDriven else { return }
                                    isAtBottom = false
                                    scroll.setJumpToLatest(true)
                                }
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.bottom, AppSpacing.lg)
                        .animation(animateMessageDelta ? .spring(response: 0.35, dampingFraction: 0.86) : nil, value: conversationMessages.count)
                    }
                    .defaultScrollAnchor(.bottom)
                    .scrollDismissesKeyboard(.immediately)
                    // Live at-bottom detection (iOS 18+): drives auto-follow
                    // and the jump button from real viewport geometry instead
                    // of the lazy-culled sentinel.
                    .chatAtBottomTracking { atBottom in
                        isAtBottom = atBottom
                        scroll.setJumpToLatest(!atBottom)
                    }
                    .animation(.snappy(duration: 0.25), value: peerActivity)
                    .onChange(of: peerActivity) { _, activity in
                        // The bubble grows the content below the viewport — a
                        // reader sitting at the bottom should see it appear,
                        // never have to chase it. Up-thread readers are left
                        // alone (same contract as message auto-follow).
                        guard activity != nil, isAtBottom else { return }
                        withAnimation(.snappy(duration: 0.25)) {
                            proxy.scrollTo("DM_BOTTOM", anchor: .bottom)
                        }
                    }
                    .onAppear {
                        // The empty state replaces this ScrollView, so it mounts
                        // only once messages already exist and its count-based
                        // onChange never sees the 0→N load. Without an explicit
                        // assert, a non-sender opened mid-thread instead of on the
                        // newest message. Snap to the bottom on first mount (the
                        // grace flag keeps later re-appears from yanking a reader
                        // who has scrolled up). Deferred so the lazy rows lay out
                        // first. Mirrors the group chat's `!chatDidLoad` snap.
                        guard !chatDidLoad else { return }
                        DispatchQueue.main.async {
                            proxy.scrollTo("DM_BOTTOM", anchor: .bottom)
                        }
                        // LazyVStack estimates row heights on the first pass,
                        // so the entry snap can land with the newest bubble
                        // half-hidden behind the composer (IMG_8284). Once
                        // real layout settles, re-assert the anchor — a no-op
                        // when the first pass already landed; skipped if the
                        // reader has already scrolled up-thread.
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(0.45))
                            if !chatDidLoad || isAtBottom {
                                proxy.scrollTo("DM_BOTTOM", anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: conversationMessages.count) { old, new in
                        guard new > 0 else { return }
                        // Decide the animation for THIS change — onChange runs
                        // ahead of the body pass that renders it. Spring only
                        // small deltas once entry has settled; bulk merges
                        // (server refresh, older pages) must land unanimated
                        // (a springing merge reads as the whole chat settling).
                        animateMessageDelta = chatDidLoad && abs(new - old) <= 3
                        startLoadGraceIfNeeded()
                        let newest = conversationMessages.last?.id
                        let appended = newest != newestMessageId
                        newestMessageId = newest
                        // Prepends (older pages) keep the reading position;
                        // only appends may move the viewport.
                        guard appended else { return }
                        let isOwnLatest = conversationMessages.last?.isMine(myUserId: directMessageService.myUserId, myName: myName) == true
                        if !chatDidLoad {
                            // Entry batches: snap straight to the bottom rest,
                            // then re-assert once the lazy rows take their real
                            // heights — the estimated first pass lands short.
                            proxy.scrollTo("DM_BOTTOM", anchor: .bottom)
                            scroll.setJumpToLatest(false)
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(0.45))
                                if !chatDidLoad || isAtBottom {
                                    proxy.scrollTo("DM_BOTTOM", anchor: .bottom)
                                }
                            }
                        } else if isAtBottom || isOwnLatest {
                            // Follow new messages only when already at the
                            // bottom or when we sent it ourselves — never yank
                            // a reader up-thread. Gated on the geometry-backed
                            // at-bottom state, NOT the debounced jump-button
                            // flag, whose staleness used to strand the newest
                            // message below the fold.
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                proxy.scrollTo("DM_BOTTOM", anchor: .bottom)
                            }
                            // We just parked at the bottom: hide the jump
                            // button explicitly, since the geometry signal only
                            // re-emits on a bucket CHANGE and a snap that
                            // doesn't cross one used to leave it stranded
                            // visible (IMG_8303).
                            scroll.setJumpToLatest(false)
                        } else {
                            // Reading up-thread: leave the viewport alone and
                            // don't mark the (unseen) message read.
                            return
                        }
                        directMessageService.markRead(thread: thread)
                        Task { await directMessageService.markReadRemote(thread: thread, myName: myName) }
                    }
                    .onChange(of: scrollTarget) { _, target in
                        guard let t = target else { return }
                        withAnimation { proxy.scrollTo(t, anchor: .center) }
                        scrollTarget = nil
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if scroll.showJumpToLatest {
                    Button {
                        // Idempotent: re-taps mid-flight are ignored instead of
                        // restarting the spring (each restart read as a nudge).
                        guard !isJumpingToLatest else { return }
                        isJumpingToLatest = true
                        HapticFeedback.impact(.light)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            proxy.scrollTo("DM_BOTTOM", anchor: .bottom)
                        }
                        // LazyVStack estimates offsets for distant targets, so
                        // one animated pass can land short of the true bottom —
                        // which used to demand a second or third press. Once
                        // the spring settles, re-assert the anchor; a no-op if
                        // the first pass already landed.
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(0.45))
                            if scroll.showJumpToLatest {
                                proxy.scrollTo("DM_BOTTOM", anchor: .bottom)
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
                    .accessibilityLabel(Text("Jump to latest message"))
                    .glassCircle()
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                    .padding(.trailing, AppSpacing.lg).padding(.bottom, AppSpacing.md)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            ZStack {
                Circle()
                    .fill(peerColor.opacity(0.12))
                    .frame(width: 80, height: 80)
                Text(peerInitials)
                    .font(AppFont.scaled(28, weight: .bold))
                    .foregroundStyle(peerColor)
            }
            Text(peerName)
                .font(AppFont.scaled(18, weight: .bold))
            Text("Start the private conversation")
                .font(AppFont.scaled(14))
                .foregroundStyle(Color.primary.opacity(0.4))
            Spacer()
        }
    }

    // MARK: - Helpers

    private func sameDay(_ a: DirectMessage, _ b: DirectMessage) -> Bool {
        guard let da = a.date, let db = b.date else { return false }
        return Calendar.current.isDate(da, inSameDayAs: db)
    }
}
