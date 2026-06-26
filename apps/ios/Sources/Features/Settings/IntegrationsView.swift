import SwiftUI

struct IntegrationsView: View {
    // No @EnvironmentObject, no @StateObject — absolute minimum to test navigation
    var body: some View {
        Text("Integrations")
            .font(.title2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(appBackground.ignoresSafeArea())
            .navigationTitle("Integrations")
            .navigationBarTitleDisplayMode(.large)
    }
}
