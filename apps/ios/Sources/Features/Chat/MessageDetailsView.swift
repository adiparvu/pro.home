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
            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).offset(x: 5)
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
                .font(.system(size: 17))
                .foregroundStyle(.primary)
            Spacer()
            if let dateTime {
                Text(dateTime)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            } else {
                Text("—").foregroundStyle(Color.primary.opacity(0.3))
            }
        }
        .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.base)
    }
}

private struct DetailsCard<Header: View>: View {
    let themeID: String
    let createdAt: String
    let readTime: String?
    var deliveredTime: String?
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

                VStack(spacing: 0) {
                    DetailRow(read: true, label: "Read", dateTime: readTime)
                    Divider().padding(.leading, 50)
                    DetailRow(read: false, label: "Delivered", dateTime: deliveredTime)
                }
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                .padding(AppSpacing.lg)

                Spacer()
            }
            .navigationTitle("Message details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationBackground(.thinMaterial)
    }
}

// MARK: - Group message details

struct MessageDetailsView: View {
    let message: Message
    let readers: [MessageRead]
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
                    deliveredTime: detailDateTime(message.createdAt)) {
            HStack {
                Spacer(minLength: 50)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(summary)
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppSpacing.base).padding(.vertical, 9)
                        .background(bubbleColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    HStack(spacing: 4) {
                        Text(message.timeDisplay)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.primary.opacity(0.4))
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
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
        let lower = message.body.lowercased()
        if lower.contains("/dm-audio/") || lower.hasSuffix(".m4a") { return "🎤 Voice message" }
        if lower.contains("/dm-images/") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") { return "📷 Photo" }
        return message.body
    }

    var body: some View {
        DetailsCard(themeID: themeID, createdAt: message.createdAt, readTime: readTime,
                    deliveredTime: deliveredTime) {
            HStack {
                if isOwn { Spacer(minLength: 50) }
                VStack(alignment: isOwn ? .trailing : .leading, spacing: 3) {
                    Text(summary)
                        .font(.system(size: 15))
                        .foregroundStyle(isOwn ? .white : .primary)
                        .padding(.horizontal, AppSpacing.base).padding(.vertical, 9)
                        .background(isOwn ? bubbleColor : Color.primary.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Text(message.timeDisplay)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.primary.opacity(0.4))
                }
                if !isOwn { Spacer(minLength: 50) }
            }
        }
    }
}
