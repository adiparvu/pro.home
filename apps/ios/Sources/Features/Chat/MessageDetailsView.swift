import SwiftUI

// MARK: - Shared bits

private func detailDateTime(_ iso: String) -> String {
    let d = ISODate.date(from: iso) ?? Date()
    let out = DateFormatter(); out.dateFormat = "dd.MM.yyyy HH:mm"; out.locale = .current
    return out.string(from: d)
}

private struct DeliveryCheck: View {
    let read: Bool
    var body: some View {
        ZStack(alignment: .leading) {
            Image(systemName: "checkmark").font(AppFont.scaled(12, weight: .bold))
            Image(systemName: "checkmark").font(AppFont.scaled(12, weight: .bold)).offset(x: 5)
        }
        .frame(width: 22, alignment: .leading)
        .foregroundStyle(read ? Color.blue : Color.primary.opacity(AppOpacity.secondaryText))
    }
}

private struct DetailRow: View {
    let read: Bool
    let label: String
    let dateTime: String?

    var body: some View {
        HStack(spacing: 12) {
            DeliveryCheck(read: read)
            Text(LocalizedStringKey(label))
                .font(AppFont.scaled(17))
                .foregroundStyle(.primary)
            Spacer()
            if let dateTime {
                Text(dateTime)
                    .font(AppFont.scaled(15))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            } else {
                Text("—").foregroundStyle(Color.primary.opacity(0.3))
            }
        }
        .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.base)
    }
}

/// Per-member receipts for a GROUP message — who has seen it and who only
/// received it (IMG_8301). DMs pass nil: with one peer, the aggregate
/// Read/Delivered rows already say everything.
private struct PerMemberReceipts {
    let readers: [MessageRead]
    let deliverers: [MessageDelivery]
    let members: [FamilyMember]

    /// Members who received the message but have not read it yet.
    var deliveredOnly: [MessageDelivery] {
        let readerNames = Set(readers.map { $0.readerName })
        return deliverers
            .filter { !readerNames.contains($0.delivererName) }
            .sorted { $0.deliveredAt > $1.deliveredAt }
    }
}

private struct DetailsCard<Header: View>: View {
    let themeID: String
    let createdAt: String
    let readTime: String?
    var deliveredTime: String?
    var perMember: PerMemberReceipts? = nil
    @ViewBuilder let header: () -> Header
    @Environment(\.dismiss) private var dismiss

    private var theme: ChatTheme { .theme(for: themeID) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    if let cols = theme.backgroundColors {
                        LinearGradient(colors: cols, startPoint: .top, endPoint: .bottom)
                    } else {
                        Color.primary.opacity(AppOpacity.hairline)
                    }
                    VStack(spacing: 8) {
                        ChatDateSeparator(dateStr: createdAt)
                        header()
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, 18)
                }
                .fixedSize(horizontal: false, vertical: true)

                // Scrolls: with per-member receipts a large household's list
                // outgrows the sheet, and the summary rows must never clip.
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            DetailRow(read: true, label: "Read", dateTime: readTime)
                            Divider().padding(.leading, 50)
                            DetailRow(read: false, label: "Delivered", dateTime: deliveredTime)
                        }
                        .background(Color(.secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                        .padding(AppSpacing.lg)

                        if let perMember, !(perMember.readers.isEmpty && perMember.deliveredOnly.isEmpty) {
                            seenBySection(perMember)
                                .padding(.horizontal, AppSpacing.lg)
                                .padding(.bottom, AppSpacing.lg)
                        }
                    }
                }
            }
            .navigationTitle("Message details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationBackground(.thinMaterial)
    }

    // MARK: Per-member receipts (group messages)

    private func seenBySection(_ receipts: PerMemberReceipts) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("message_seen_by")
                .font(AppFont.captionStrong)
                .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                .padding(.leading, AppSpacing.xs)
            VStack(spacing: 0) {
                ForEach(Array(receipts.readers.sorted { $0.readAt > $1.readAt }.enumerated()),
                        id: \.element.id) { idx, read in
                    if idx > 0 { Divider().padding(.leading, 62) }
                    receiptRow(name: read.readerName,
                               detail: String(format: String(localized: "Seen %@"), read.readTimeDisplay),
                               read: true,
                               member: receipts.members.first { $0.name == read.readerName })
                }
                if !receipts.deliveredOnly.isEmpty {
                    if !receipts.readers.isEmpty { Divider().padding(.leading, 62) }
                    ForEach(Array(receipts.deliveredOnly.enumerated()), id: \.element.id) { idx, d in
                        if idx > 0 { Divider().padding(.leading, 62) }
                        receiptRow(name: d.delivererName,
                                   detail: String(localized: "Delivered"),
                                   read: false,
                                   member: receipts.members.first { $0.name == d.delivererName })
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        }
    }

    private func receiptRow(name: String, detail: String, read: Bool,
                            member: FamilyMember?) -> some View {
        HStack(spacing: 12) {
            let color = member?.swiftColor ?? .blue
            ZStack {
                Circle().fill(color.opacity(0.2))
                Text(member?.initials ?? String(name.prefix(1)).uppercased())
                    .font(AppFont.scaled(13, weight: .bold))
                    .foregroundStyle(color)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? String(localized: "Member") : name)
                    .font(AppFont.subheadline)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(AppFont.scaled(12))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
            }
            Spacer()
            DeliveryCheck(read: read)
        }
        .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Group message details

struct MessageDetailsView: View {
    let message: Message
    let readers: [MessageRead]
    /// Real per-member delivery receipts (same data the SeenBySheet uses). The
    /// Delivered row is derived from these — never fabricated from the send time.
    var deliverers: [MessageDelivery] = []
    /// Roster snapshot for avatars/colors in the per-member "Seen by" list.
    var members: [FamilyMember] = []
    @AppStorage("prvio.chatTheme") private var themeID = "appDefault"

    private var theme: ChatTheme { .theme(for: themeID) }
    private var bubbleColor: Color {
        themeID == "appDefault" ? Color.blue.opacity(0.75) : theme.outgoingBubble
    }
    private var readTime: String? {
        let times = readers.map { $0.readAt }
        guard let latest = times.max() else { return nil }
        return detailDateTime(latest)
    }
    /// The moment the message first reached anyone — the earliest genuine
    /// delivery receipt. `nil` (renders "—") when no one has received it yet,
    /// so an undelivered message never shows a fake "Delivered" timestamp.
    private var deliveredTime: String? {
        guard let earliest = deliverers.map(\.deliveredAt).min() else { return nil }
        return detailDateTime(earliest)
    }
    private var summary: String {
        if let b = message.body, !b.isEmpty { return b }
        if message.isImageMessage { return "📷 Photo" }
        if message.isAudioMessage { return "🎤 Voice message" }
        if message.isLocationMessage { return "📍 Location" }
        if message.isFileMessage { return "📎 File" }
        if message.isPollMessage { return "📊 Poll" }
        if message.isEventMessage { return "📅 Event" }
        if message.isStickerMessage { return "😀 Sticker" }
        return "Message"
    }

    var body: some View {
        DetailsCard(themeID: themeID, createdAt: message.createdAt, readTime: readTime,
                    deliveredTime: deliveredTime,
                    perMember: PerMemberReceipts(readers: readers, deliverers: deliverers,
                                                 members: members)) {
            HStack {
                Spacer(minLength: 50)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(summary)
                        .font(AppFont.scaled(15))
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppSpacing.base).padding(.vertical, 9)
                        .background(bubbleColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    HStack(spacing: 4) {
                        Text(message.timeDisplay)
                            .font(AppFont.scaled(10))
                            .foregroundStyle(Color.primary.opacity(0.4))
                        Image(systemName: "checkmark").font(AppFont.scaled(9, weight: .bold))
                            .foregroundStyle(Color.primary.opacity(0.4))
                    }
                }
            }
        }
    }
}

// MARK: - DM message details

struct DMMessageDetailsView: View {
    let message: DirectMessage
    let isOwn: Bool
    @AppStorage("prvio.chatTheme") private var themeID = "appDefault"

    private var theme: ChatTheme { .theme(for: themeID) }
    private var bubbleColor: Color {
        themeID == "appDefault" ? Color.accentColor : theme.outgoingBubble
    }
    private var readTime: String? {
        guard let r = message.readAt else { return nil }
        return detailDateTime(r)
    }
    private var deliveredTime: String? {
        message.deliveredAt.map(detailDateTime)
    }
    private var summary: String {
        switch ChatMedia.dmBodyKind(message.body) {
        case .audio: return String(localized: "dm_prev_audio")
        case .image: return String(localized: "dm_prev_photo")
        case .video: return String(localized: "dm_prev_video")
        case .text:  return message.body
        }
    }

    var body: some View {
        DetailsCard(themeID: themeID, createdAt: message.createdAt, readTime: readTime,
                    deliveredTime: deliveredTime) {
            HStack {
                if isOwn { Spacer(minLength: 50) }
                VStack(alignment: isOwn ? .trailing : .leading, spacing: 3) {
                    Text(summary)
                        .font(AppFont.scaled(15))
                        .foregroundStyle(isOwn ? .white : .primary)
                        .padding(.horizontal, AppSpacing.base).padding(.vertical, 9)
                        .background(isOwn ? bubbleColor : Color.primary.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Text(message.timeDisplay)
                        .font(AppFont.scaled(10))
                        .foregroundStyle(Color.primary.opacity(0.4))
                }
                if !isOwn { Spacer(minLength: 50) }
            }
        }
    }
}
