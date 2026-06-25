import SwiftUI
import PhotosUI
import Supabase

// MARK: - Direct Message View (1-on-1 private chat)

struct DirectMessageView: View {
    let member: FamilyMember

    @EnvironmentObject private var directMessageService: DirectMessageService
    @EnvironmentObject private var profileService: ProfileService
    @EnvironmentObject private var propertyService: PropertyService
    @EnvironmentObject private var familyService: FamilyService

    @State private var input = ""
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var showProfile = false
    @FocusState private var focused: Bool
    @State private var isSending = false

    private var myName: String {
        profileService.profile?.preferredName ?? profileService.profile?.fullName ?? "Me"
    }

    private var conversationMessages: [DirectMessage] {
        directMessageService.messages(with: member.name, myName: myName)
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                messageList
                inputBar
            }
        }
        .navigationTitle(member.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    showProfile = true
                } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(member.swiftColor.opacity(0.15))
                                .frame(width: 34, height: 34)
                            Text(member.initials)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(member.swiftColor)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(member.name)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(member.roleLabel)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.primary.opacity(0.4))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showProfile) {
            MemberProfileSheet(member: member)
                .environmentObject(familyService)
        }
        .onAppear { directMessageService.markRead(partner: member.name) }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            Group {
                if conversationMessages.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(conversationMessages.enumerated()), id: \.element.id) { idx, msg in
                                let isOwn = msg.senderName == myName
                                let prevSameSender = idx > 0 && conversationMessages[idx - 1].senderName == msg.senderName
                                let showDate = idx == 0 || !sameDay(conversationMessages[idx - 1], msg)

                                if showDate {
                                    ChatDateSeparator(dateStr: msg.createdAt)
                                        .padding(.top, idx == 0 ? 8 : 16)
                                }

                                DMBubble(
                                    message: msg,
                                    isOwn: isOwn,
                                    showSenderBubbleTail: !prevSameSender || showDate
                                )
                                .id(msg.id)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .onChange(of: conversationMessages.count) { _, _ in
                        if let last = conversationMessages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                        directMessageService.markRead(partner: member.name)
                    }
                    .onAppear {
                        if let last = conversationMessages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
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
                    .fill(member.swiftColor.opacity(0.12))
                    .frame(width: 80, height: 80)
                Text(member.initials)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(member.swiftColor)
            }
            Text(member.name)
                .font(.system(size: 18, weight: .bold))
            Text("Începe conversația privată")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.4))
            Spacer()
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            Menu {
                Button {
                    showPhotoPicker = true
                } label: {
                    Label("Fotografie", systemImage: "photo")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.5))
                    .frame(width: 34, height: 34)
                    .background(Color.primary.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)

            TextField("Mesaj…", text: $input, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .lineLimit(1...5)
                .focused($focused)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .liquidGlass(cornerRadius: 20)

            Button {
                Task { await sendMessage() }
            } label: {
                ZStack {
                    Circle()
                        .fill(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              ? Color.primary.opacity(0.1) : Color.accentColor)
                        .frame(width: 34, height: 34)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(
                            input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.primary.opacity(0.3) : .white
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .photosPicker(isPresented: $showPhotoPicker,
                      selection: $photoPickerItems, maxSelectionCount: 1, matching: .images)
        .onChange(of: photoPickerItems) { _, items in
            Task { await sendPhoto(items) }
        }
    }

    // MARK: - Send

    private func sendMessage() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        input = ""
        isSending = true
        defer { isSending = false }

        struct Payload: Encodable {
            let sender_name: String
            let recipient_name: String
            let body: String
            let property_id: String?
        }

        let payload = Payload(
            sender_name: myName,
            recipient_name: member.name,
            body: text,
            property_id: propertyService.primary?.id.uuidString
        )

        do {
            let sent: DirectMessage = try await supabase
                .from("direct_messages")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value
            directMessageService.dms.append(sent)
            HapticFeedback.impact(.light)
        } catch {
#if DEBUG
            print("[DM] send error: \(error)")
#endif
        }
    }

    private func sendPhoto(_ items: [PhotosPickerItem]) async {
        guard let item = items.first else { return }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let filename = "\(UUID().uuidString).jpg"

        guard let propId = propertyService.primary?.id else { return }

        do {
            try await supabase.storage.from("documents").upload(filename, data: data, options: FileOptions(contentType: "image/jpeg", upsert: false))
            let urlStr = (try? supabase.storage.from("documents").getPublicURL(path: filename))?.absoluteString ?? ""
            guard !urlStr.isEmpty else { return }

            struct PhotoPayload: Encodable {
                let sender_name: String
                let recipient_name: String
                let body: String
                let property_id: String
            }

            let payload = PhotoPayload(
                sender_name: myName,
                recipient_name: member.name,
                body: urlStr,
                property_id: propId.uuidString
            )

            let sent: DirectMessage = try await supabase
                .from("direct_messages")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value
            directMessageService.dms.append(sent)
        } catch {
#if DEBUG
            print("[DM] photo error: \(error)")
#endif
        }
    }

    // MARK: - Helpers

    private func sameDay(_ a: DirectMessage, _ b: DirectMessage) -> Bool {
        guard let da = a.date, let db = b.date else { return false }
        return Calendar.current.isDate(da, inSameDayAs: db)
    }
}

// MARK: - DM Bubble

private struct DMBubble: View {
    let message: DirectMessage
    let isOwn: Bool
    let showSenderBubbleTail: Bool

    private var isImageUrl: Bool {
        let lower = message.body.lowercased()
        return lower.contains("supabase") && (lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".png") || lower.hasSuffix(".webp"))
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isOwn { Spacer(minLength: 72) }

            VStack(alignment: isOwn ? .trailing : .leading, spacing: 3) {
                if isImageUrl {
                    imageBubble
                } else {
                    textBubble
                }
                Text(message.timeDisplay)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.primary.opacity(0.35))
                    .padding(.horizontal, 2)
            }

            if !isOwn { Spacer(minLength: 72) }
        }
        .padding(.vertical, 1)
    }

    private var textBubble: some View {
        Text(message.body)
            .font(.system(size: 15))
            .foregroundStyle(isOwn ? .white : .primary)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(
                isOwn
                    ? Color.accentColor
                    : Color.primary.opacity(0.09),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var imageBubble: some View {
        AsyncImage(url: URL(string: message.body)) { phase in
            switch phase {
            case .success(let img):
                img.resizable()
                    .scaledToFill()
                    .frame(maxWidth: 220, maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            case .failure:
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 220, height: 140)
                    .overlay(Image(systemName: "photo").foregroundStyle(Color.primary.opacity(0.3)))
            default:
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 220, height: 140)
                    .overlay(ProgressView())
            }
        }
    }
}

