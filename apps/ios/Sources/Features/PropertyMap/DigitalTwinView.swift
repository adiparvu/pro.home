import SwiftUI

// MARK: - Tab 2 root — "Spațiile casei"
//
// The Digital Twin (2D aerial map + 3D maquette) was retired by final user
// decision: no 3D, no maps, no digital twin of any kind. Tab 2 is now the
// full-page home of the estate's spaces — SpacesTabView, in the SmartHome
// feature folder. The legacy twin implementations remain on disk, each
// marked unreferenced at the top of its file, for a future cleanup pass.
// SpacesTabView owns its own data loading (zones + elements), so nothing
// else lives here.

struct DigitalTwinView: View {
    var body: some View {
        SpacesTabView()
    }
}
