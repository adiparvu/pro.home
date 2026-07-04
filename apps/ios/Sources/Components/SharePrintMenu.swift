import SwiftUI

// MARK: - SharePrintMenu
//
// A drop-in menu button offering Share and Print of a rendered image. The caller
// supplies a `render` closure (usually an ImageRenderer over a printable layout)
// so the heavy render only runs when an option is actually chosen, and its own
// trigger label. Presentation goes through `SystemActions` for correct iPad
// popover anchoring.

struct SharePrintMenu<Trigger: View>: View {
    var jobName: String = "PRVIO"
    let render: () -> UIImage?
    @ViewBuilder var trigger: () -> Trigger

    // Resolve labels through the app's proven RO/EN switch rather than the
    // xcstrings bundle, so they never fall back to raw keys if the runtime
    // language table hasn't picked up a freshly-added key.
    private var shareTitle: String { Locale.appIsRomanian ? "Partajează" : "Share" }
    private var printTitle: String { Locale.appIsRomanian ? "Printează" : "Print" }

    var body: some View {
        Menu {
            Button {
                HapticFeedback.impact(.light)
                if let image = render() { SystemActions.share([image]) }
            } label: {
                Label(shareTitle, systemImage: "square.and.arrow.up")
            }
            Button {
                HapticFeedback.impact(.light)
                if let image = render() { SystemActions.print(image: image, jobName: jobName) }
            } label: {
                Label(printTitle, systemImage: "printer")
            }
        } label: {
            trigger()
        }
    }
}
