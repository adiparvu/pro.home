import SwiftUI

// MARK: - Starred (marked) messages screen

struct StarredMessagesView: View {
    let messages: [Message]
    let members: [FamilyMember]
    let onSelect: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                if messages.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(messages) { msg in
                                Button {
                                    onSelect(msg.id)
                                    dismiss()
                                } label: {
                                    StarredRow(message: msg, members: members)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(AppSpacing.lg)
                    }
                }
            }
            .navigationTitle("Starred messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationBackground(.thinMaterial)
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "flag.slash",
            title: "No starred messages",
            message: "Mark a message to find it here later."
        )
    }
}

private struct StarredRow: View {
    let message: Message
    let members: [FamilyMember]

    private var sender: FamilyMember? { members.first { $0.name == message.senderName } }

    private var snippet: String {
        if let b = message.body, !b.isEmpty { return b }
        if message.isImageMessage { return "📷 Photo" }
        if message.isAudioMessage { return "🎤 Voice message" }
        if message.isLocationMessage { return "📍 Location" }
        if message.isFileMessage { return "📎 File" }
        if message.isStickerMessage { return "😀 Sticker" }
        return "Message"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "flag.fill")
                .font(.system(size: 13))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(message.senderName)
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(sender?.swiftColor ?? .primary)
                Text(snippet)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                    .lineLimit(2)
                Text(message.timeDisplay)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(AppFont.captionStrong)
                .foregroundStyle(Color.primary.opacity(0.25))
        }
        .padding(AppSpacing.base)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
