import SwiftUI

// MARK: - Property Tab — "Spațiile casei"
//
// Tab 2 is the estate's spaces page (SpacesTabView, via the DigitalTwinView
// shell). The map/3D Digital Twin was retired by final user decision — no
// 3D, no maps, no digital twin of any kind.

struct PropertyTabView: View {
    var body: some View {
        DigitalTwinView()
            .background(appBackground.ignoresSafeArea())
    }
}
