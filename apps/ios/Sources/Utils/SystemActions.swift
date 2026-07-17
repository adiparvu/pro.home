import UIKit

// MARK: - SystemActions
//
// Small imperative bridges to the two system sheets SwiftUI has no first-class
// API for: the share sheet (with correct iPad popover anchoring) and the print
// panel. Kept in one place so every screen shares the same presentation and
// top-most-controller logic instead of re-deriving it.

enum SystemActions {

    /// Presents the system share sheet for the given items (URLs, images, strings…).
    @MainActor
    static func share(_ items: [Any], from sourceRect: CGRect? = nil) {
        guard !items.isEmpty, let presenter = topMost() else { return }
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // iPad requires a source for the popover; anchor to the presenter's view.
        if let pop = vc.popoverPresentationController {
            pop.sourceView = presenter.view
            pop.sourceRect = sourceRect ?? CGRect(x: presenter.view.bounds.midX,
                                                   y: presenter.view.bounds.midY,
                                                   width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        presenter.present(vc, animated: true)
    }

    /// Presents the system print panel for a single image.
    @MainActor
    static func print(image: UIImage, jobName: String = "PRVIO") {
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = jobName
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = image
        controller.present(animated: true, completionHandler: nil)
    }

    /// Presents the system print panel for rendered PDF/printable data.
    @MainActor
    static func print(data: Data, jobName: String = "PRVIO") {
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = jobName
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = data
        controller.present(animated: true, completionHandler: nil)
    }

    /// The front-most view controller across the active foreground scene, walking
    /// past presented sheets, navigation and tab containers.
    @MainActor
    static func topMost() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard var top = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
                ?? scene?.windows.first?.rootViewController else { return nil }
        // Never land on a controller mid-dismissal (a closing popover/sheet):
        // presenting from one is silently dropped by UIKit — the caller's
        // share sheet or print panel would simply never appear.
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
