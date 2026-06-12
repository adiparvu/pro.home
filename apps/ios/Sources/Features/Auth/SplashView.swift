import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("🏠")
                    .font(.system(size: 56))
                ProgressView()
                    .tint(.white.opacity(0.4))
            }
        }
        .preferredColorScheme(.dark)
    }
}
