import SwiftUI
import WebKit

// MARK: - In-app link player (WhatsApp-style)
//
// Tapping a link in chat opens it INSIDE the app — video links (YouTube,
// TikTok, Facebook/Instagram reels, Vimeo) load their inline player, and
// everything else loads as a normal in-app web page. Nothing bounces the
// user out to Safari or another app unless they explicitly ask for it from
// the toolbar menu.

enum VideoEmbed {

    /// The URL actually loaded in the player — a dedicated embed player for
    /// services that have one, the original URL otherwise.
    static func playerURL(for url: URL) -> URL {
        let host = (url.host ?? "").lowercased()
        let path = url.path

        // YouTube: watch?v=ID · youtu.be/ID · /shorts/ID · /live/ID
        if host.contains("youtube.com") || host == "youtu.be" {
            var id: String?
            if host == "youtu.be" {
                id = url.pathComponents.dropFirst().first
            } else if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                      let v = items.first(where: { $0.name == "v" })?.value {
                id = v
            } else {
                let comps = url.pathComponents
                if let i = comps.firstIndex(where: { $0 == "shorts" || $0 == "live" || $0 == "embed" }),
                   i + 1 < comps.count {
                    id = comps[i + 1]
                }
            }
            if let id, !id.isEmpty,
               let embed = URL(string: "https://www.youtube-nocookie.com/embed/\(id)?autoplay=1&playsinline=1") {
                return embed
            }
        }

        // TikTok: /@user/video/1234567890
        if host.contains("tiktok.com"), let i = url.pathComponents.firstIndex(of: "video"),
           i + 1 < url.pathComponents.count {
            let id = url.pathComponents[i + 1]
            if let embed = URL(string: "https://www.tiktok.com/embed/v2/\(id)") {
                return embed
            }
        }

        return url
    }

    static func isVideoLink(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        if host.contains("youtube.com") || host == "youtu.be" { return true }
        if host.contains("tiktok.com") { return true }
        if host.contains("vimeo.com") { return true }
        if host.contains("facebook.com") || host.contains("fb.watch") {
            return path.contains("video") || path.contains("reel") || path.contains("watch") || path.contains("/share/r/")
        }
        if host.contains("instagram.com") {
            return path.contains("reel") || path.contains("/tv/")
        }
        return false
    }
}

// MARK: - WKWebView host

private struct WebPlayerView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.isOpaque = false
        wv.backgroundColor = .black
        wv.scrollView.backgroundColor = .black
        wv.navigationDelegate = context.coordinator
        // The URL comes from another user's chat message — only the web
        // schemes may load inside the app's trusted chrome.
        if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            wv.load(URLRequest(url: url))
        }
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Cancels any navigation that tries to leave the web — custom app
    /// schemes from a redirect would otherwise escape the sandbox of the
    /// player sheet.
    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let scheme = navigationAction.request.url?.scheme?.lowercased()
            decisionHandler(scheme == "http" || scheme == "https" ? .allow : .cancel)
        }
    }
}

// MARK: - Player sheet

struct InAppLinkPlayerSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WebPlayerView(url: VideoEmbed.playerURL(for: url))
                .ignoresSafeArea(edges: .bottom)
                .background(Color.black.ignoresSafeArea())
                .navigationTitle(url.host ?? "")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .accessibilityLabel("Close")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Menu {
                            Button {
                                UIApplication.shared.open(url)
                            } label: {
                                Label("Open in Safari", systemImage: "safari")
                            }
                            ShareLink(item: url) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
        }
    }
}
