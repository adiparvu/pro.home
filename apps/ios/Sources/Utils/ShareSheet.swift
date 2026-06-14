import SwiftUI

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    init(url: URL) { self.activityItems = [url] }
    init(activityItems: [Any]) { self.activityItems = activityItems }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
