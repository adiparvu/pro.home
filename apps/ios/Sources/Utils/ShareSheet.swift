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

// MARK: - Identifiable payload for item-based presentation
//
// `.sheet(isPresented:)` builds its content the instant the flag flips, and
// `UIActivityViewController` is created once in `makeUIViewController`. If the
// items array is a *separate* @State set in the same transaction, the sheet can
// materialize with a still-empty array — a blank share sheet the first time,
// working only on the retry once the state has caught up. Presenting with
// `.sheet(item:)` guarantees SwiftUI only presents after the payload exists and
// always builds the controller from it, so it's correct on the very first tap.
struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
    init(_ items: [Any]) { self.items = items }
}
