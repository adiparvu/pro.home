import SwiftUI
import SafariServices

// MARK: - In-app Safari (SFSafariViewController)

/// The system in-app browser, for previewing PRVIO's own public web pages
/// exactly as an outsider sees them (first user: the Lost & Found card's
/// scanned-page preview, IMG_8683). Always the system controller — Done,
/// share sheet and Reader come with it; never a bare WKWebView.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = UIColor(named: "AccentColor")
        return vc
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
