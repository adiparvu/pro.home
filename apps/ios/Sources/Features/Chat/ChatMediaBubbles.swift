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
    /// Set once the signed-URL resolve completes so we can tell "still loading"
    /// from "resolve returned nil" (an expired/broken link) and stop showing a
    /// spinner that would otherwise spin forever.
    @State private var didResolve = false
    /// Bumping this re-runs the resolve `.task` — the retry affordance.
    @State private var reloadToken = 0

    private var onBubble: Color { ownBubbleColor.readableText }
    private var trailingTint: Color { isOwn ? onBubble.opacity(0.8) : Color.accentColor }
    /// Failed to resolve: the task finished but produced no URL.
    private var didFail: Bool { didResolve && url == nil }
    private var accessoryHint: LocalizedStringKey { didFail ? "chat_file_retry_hint" : "chat_file_open_hint" }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .font(AppFont.scaled(20))
                .foregroundStyle(isOwn ? onBubble : Color.accentColor)
            Text(name ?? String(localized: "chat_file_fallback_name"))
                .font(AppFont.footnote)
                .foregroundStyle(isOwn ? onBubble : .primary)
                .lineLimit(2)
            Spacer(minLength: AppSpacing.xs)
            trailingAccessory
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let url { onPreview(url, name ?? url.lastPathComponent) }
            else if didFail { reloadToken += 1 }
        }
        .padding(.horizontal, AppSpacing.base).padding(.vertical, 10)
        .background(
            isOwn ? ownBubbleColor : Color.primary.opacity(0.08),
            in: ChatBubbleShape(isOwn: isOwn, hasTail: hasTail)
        )
        .frame(maxWidth: 240)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(name ?? String(localized: "chat_file_fallback_name")))
        .accessibilityHint(Text(accessoryHint))
        .task(id: "\(stored ?? "")#\(reloadToken)") {
            guard let stored else { didResolve = true; return }
            didResolve = false
            url = await ChatMedia.resolve(stored)
            didResolve = true
        }
    }

    // Trailing glyph tracks the resolve lifecycle: spinner while resolving, an
    // eye once a signed URL exists, a retry glyph if it failed.
    @ViewBuilder private var trailingAccessory: some View {
        if url != nil {
            Image(systemName: "eye.fill")
                .font(AppFont.scaled(18))
                .foregroundStyle(trailingTint)
                .onTapGesture { if let url { onPreview(url, name ?? url.lastPathComponent) } }
                .accessibilityHidden(true)
        } else if didFail {
            Image(systemName: "arrow.clockwise")
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(trailingTint)
                .onTapGesture { reloadToken += 1 }
                .accessibilityHidden(true)
        } else {
            ProgressView()
                .controlSize(.small)
                .tint(trailingTint)
        }
    }
}

struct ChatVideoBubble: View {
    let stored: String
    var isOwn: Bool = false
    var hasTail: Bool = true
    let onTap: (URL) -> Void
    @State private var url: URL?
    /// Distinguishes "still resolving" from "resolve returned nil" so a broken
    /// or expired video link shows a failure state instead of a silent, no-op
    /// play button.
    @State private var didResolve = false
    /// Bumping this re-runs the resolve `.task` — the retry affordance.
    @State private var reloadToken = 0

    private var shape: ChatBubbleShape { ChatBubbleShape(isOwn: isOwn, hasTail: hasTail) }
    private var didFail: Bool { didResolve && url == nil }
    private var a11yLabel: LocalizedStringKey { didFail ? "chat_video_failed" : "chat_video_play" }

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .frame(width: 200, height: 140)
            overlayContent
        }
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture {
            if let url { onTap(url) }
            else if didFail { reloadToken += 1 }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(a11yLabel))
        .task(id: "\(stored)#\(reloadToken)") {
            didResolve = false
            url = await ChatMedia.resolve(stored)
            didResolve = true
        }
    }

    // Play glyph once resolved, a broken-video glyph with retry on failure, or
    // a spinner while the signed URL is still resolving.
    @ViewBuilder private var overlayContent: some View {
        if url != nil {
            Image(systemName: "play.circle.fill")
                .font(AppFont.scaled(44))
                .foregroundStyle(.white.opacity(0.9))
        } else if didFail {
            VStack(spacing: AppSpacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(AppFont.scaled(28))
                    .foregroundStyle(.white.opacity(0.85))
                Text("chat_media_tap_retry")
                    .font(AppFont.scaled(12))
                    .foregroundStyle(.white.opacity(0.7))
            }
        } else {
            ProgressView().tint(.white)
        }
    }
}

// MARK: - Chat image bubble (resolves private signed URLs; passes legacy URLs through)

struct ChatImageBubble: View {
    let stored: String
    let caption: String?
    let isOwn: Bool
    let ownBubbleColor: Color
    var hasTail: Bool = true
    /// Compact uniform tile for a run of consecutive photos (IMG_8613).
    var compact: Bool = false
    /// A Live Photo still — wears the system LIVE badge; the tap opens the
    /// press-to-play viewer instead of the flat image viewer.
    var isLive: Bool = false
    let onTap: (URL) -> Void
    @State private var url: URL?
    /// Bumping this re-runs the resolve `.task` — the tap-to-retry affordance
    /// for when a signed URL has expired.
    @State private var reloadToken = 0

    private var hasCaption: Bool { (caption?.isEmpty == false) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StorageImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                        .frame(width: compact ? 158 : nil, height: compact ? 158 : nil)
                        .frame(maxWidth: compact ? nil : 220, maxHeight: compact ? nil : 160)
                        .contentShape(Rectangle())
                        .onTapGesture { if let url { onTap(url) } }
                case .failure:
                    // A resolved-but-unloadable image (typically an expired
                    // signed URL) previously fell through to the loading branch
                    // and spun forever. Surface a broken-photo glyph and let a
                    // tap re-resolve, mirroring DMImageBubble.
                    Rectangle().fill(Color.primary.opacity(AppOpacity.subtleFill))
                        .frame(width: 160, height: 120)
                        .overlay {
                            VStack(spacing: AppSpacing.xs) {
                                Image(systemName: "photo.badge.exclamationmark")
                                    .font(AppFont.scaled(24))
                                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                                Text("chat_media_tap_retry")
                                    .font(AppFont.scaled(12))
                                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { reloadToken += 1 }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel(Text("chat_image_failed"))
                        .accessibilityHint(Text("chat_media_tap_retry"))
                default:
                    Rectangle().fill(Color.primary.opacity(AppOpacity.subtleFill))
                        .frame(width: 160, height: 120)
                        .overlay(ProgressView().tint(.white))
                }
            }
            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(AppFont.scaled(15))
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
        .overlay(alignment: .topLeading) {
            if isLive {
                Image(systemName: "livephoto")
                    .font(AppFont.scaled(12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(6)
                    .accessibilityLabel(Text("convo_prev_live"))
            }
        }
        .task(id: "\(stored)#\(reloadToken)") { url = await ChatMedia.resolve(stored) }
    }
}
