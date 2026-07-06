import SwiftUI

// MARK: - Property Tab — map-first Digital Twin
//
// "One map, many lenses": the aerial photo IS the Digital Twin screen.
// Zones, object categories, lists and search are lenses layered over the
// same map (see DigitalTwinView.lensBar) instead of separate pages — the
// old Zones/Objects segments live on as sheets reachable from the map.

struct PropertyTabView: View {
    var body: some View {
        DigitalTwinView()
            .background(appBackground.ignoresSafeArea())
    }
}
