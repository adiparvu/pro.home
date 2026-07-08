import SwiftUI
import LinkPresentation
import UIKit

// MARK: - URL detection

func firstDetectedURL(in text: String) -> URL? {
    guard !text.isEmpty,
          let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = detector.firstMatch(in: text, options: [], range: range),
          let url = match.url,
          url.scheme == "http" || url.scheme == "https"
    else { return nil }
    return url
}

// MARK: - Metadata cache (one fetch per URL, in-memory)

@MainActor
final class LinkMetadataCache {
    static let shared = LinkMetadataCache()
    private var cache: [URL: LPLinkMetadata] = [:]
    private var waiters: [URL: [(LPLinkMetadata?) -> Void]] = [:]

    func fetch(_ url: URL, completion: @escaping (LPLinkMetadata?) -> Void) {
        if let m = cache[url] { completion(m); return }
        // A fetch is already running for this URL: queue this caller so it gets
        // the same result instead of being dropped with nil.
        if waiters[url] != nil { waiters[url]?.append(completion); return }
        waiters[url] = [completion]
        let provider = LPMetadataProvider()
        provider.startFetchingMetadata(for: url) { [weak self] meta, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if let meta { self.cache[url] = meta }
                let pending = self.waiters[url] ?? []
                self.waiters[url] = nil
                pending.forEach { $0(meta) }
            }
        }
    }
}

// MARK: - Link preview card

struct LinkPreviewView: View {
    let url: URL

    @State private var title: String?
    @State private var image: UIImage?
    @State private var loaded = false
    @State private var showPlayer = false

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            showPlayer = true
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: 240, maxHeight: 120)
                        .clipped()
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title ?? (url.host ?? url.absoluteString))
                        .font(AppFont.captionEmphasis)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(url.host ?? url.absoluteString)
                        .font(AppFont.scaled(11))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        .lineLimit(1)
                }
                .padding(.horizontal, 10).padding(.vertical, AppSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: 240, alignment: .leading)
            .background(Color.primary.opacity(AppOpacity.hairline), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .onAppear(perform: load)
        .overlay {
            // Video links advertise themselves with a play badge, WhatsApp-style.
            if VideoEmbed.isVideoLink(url), image != nil {
                Image(systemName: "play.circle.fill")
                    .font(AppFont.scaled(40))
                    .foregroundStyle(.white, .black.opacity(0.45))
                    .allowsHitTesting(false)
                    .offset(y: -14)
            }
        }
        .sheet(isPresented: $showPlayer) {
            InAppLinkPlayerSheet(url: url)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        LinkMetadataCache.shared.fetch(url) { meta in
            guard let meta else { loaded = false; return }
            title = meta.title
            if let provider = meta.imageProvider {
                provider.loadObject(ofClass: UIImage.self) { obj, _ in
                    if let img = obj as? UIImage {
                        DispatchQueue.main.async { self.image = img }
                    }
                }
            }
        }
    }
}
