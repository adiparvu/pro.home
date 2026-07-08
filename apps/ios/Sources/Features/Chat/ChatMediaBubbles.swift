// File / video / image bubbles (split from ChatComponents).
import SwiftUI
import MapKit
import CoreLocation

// MARK: - Chat file / video bubbles (resolve private signed URLs; legacy URLs pass through)

struct ChatFileBubble: View {
    let stored: String?
    let name: String?
    let isOwn: Bool
    let ownBubbleColor: Color
    var hasTail: Bool = true
    let onPreview: (URL, String) -> Void
    @State private var url: URL?

    private var onBubble: Color { ownBubbleColor.readableText }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .font(.system(size: 20))
                .foregroundStyle(isOwn ? onBubble : Color.accentColor)
            Text(name ?? "File")
                .font(AppFont.footnote)
                .foregroundStyle(isOwn ? onBubble : .primary)
                .lineLimit(2)
            if url != nil {
                Spacer()
                Image(systemName: "eye.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(isOwn ? onBubble.opacity(0.8) : Color.accentColor)
                    .onTapGesture { if let url { onPreview(url, name ?? url.lastPathComponent) } }
                    .accessibilityLabel(Text("Preview"))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if let url { onPreview(url, name ?? url.lastPathComponent) } }
        .padding(.horizontal, AppSpacing.base).padding(.vertical, 10)
        .background(
            isOwn ? ownBubbleColor : Color.primary.opacity(0.08),
            in: ChatBubbleShape(isOwn: isOwn, hasTail: hasTail)
        )
        .frame(maxWidth: 240)
        .task(id: stored ?? "") { if let stored { url = await ChatMedia.resolve(stored) } }
    }
}

struct ChatVideoBubble: View {
    let stored: String
    var isOwn: Bool = false
    var hasTail: Bool = true
    let onTap: (URL) -> Void
    @State private var url: URL?

    private var shape: ChatBubbleShape { ChatBubbleShape(isOwn: isOwn, hasTail: hasTail) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .frame(width: 200, height: 140)
            Image(systemName: "play.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.9))
        }
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture { if let url { onTap(url) } }
        .accessibilityLabel(Text("Play"))
        .task(id: stored) { url = await ChatMedia.resolve(stored) }
    }
}

// MARK: - Chat image bubble (resolves private signed URLs; passes legacy URLs through)

struct ChatImageBubble: View {
    let stored: String
    let caption: String?
    let isOwn: Bool
    let ownBubbleColor: Color
    var hasTail: Bool = true
    let onTap: (URL) -> Void
    @State private var url: URL?

    private var hasCaption: Bool { (caption?.isEmpty == false) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StorageImage(url: url) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFill()
                        .frame(maxWidth: 220, maxHeight: 160)
                } else {
                    Rectangle().fill(Color.primary.opacity(AppOpacity.subtleFill))
                        .frame(width: 160, height: 120)
                        .overlay(ProgressView().tint(.white))
                }
            }
            .onTapGesture { if let url { onTap(url) } }
            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 15))
                    .foregroundStyle(isOwn ? ownBubbleColor.readableText : .primary)
                    .padding(.horizontal, 10).padding(.top, AppSpacing.xs)
                    .frame(maxWidth: 220, alignment: .leading)
            }
        }
        .padding(hasCaption ? 4 : 0)
        .background(hasCaption ? (isOwn ? ownBubbleColor : Color.primary.opacity(0.08)) : Color.clear)
        // Clip the whole card (image + caption) to the bubble so a group ending
        // on a photo carries the same tail as a text bubble.
        .clipShape(ChatBubbleShape(isOwn: isOwn, hasTail: hasTail))
        .task(id: stored) { url = await ChatMedia.resolve(stored) }
    }
}
