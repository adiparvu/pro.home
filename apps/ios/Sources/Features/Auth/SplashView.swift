import SwiftUI

struct SplashView: View {
    @State private var scale:   CGFloat = 0.82
    @State private var opacity: Double  = 0
    @State private var logoY:   CGFloat = 8

    var body: some View {
        ZStack {
            Color(red: 0.027, green: 0.043, blue: 0.094).ignoresSafeArea()

            // background glow
            RadialGradient(
                colors: [Color(red: 0.18, green: 0.35, blue: 0.90).opacity(0.35), .clear],
                center: .init(x: 0.5, y: 0.38),
                startRadius: 0,
                endRadius: 360
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                PRVHouseLogoView(size: 100)
                    .shadow(color: Color(red: 0.24, green: 0.50, blue: 1.00).opacity(0.60), radius: 28, y: 10)
                    .scaleEffect(scale)
                    .offset(y: logoY)
                    .opacity(opacity)

                VStack(spacing: 4) {
                    Text("PRVHouse")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Property management")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .tracking(0.5)
                }
                .opacity(opacity)

                ProgressView()
                    .tint(.white.opacity(0.30))
                    .padding(.top, 6)
                    .opacity(opacity)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                scale   = 1.0
                opacity = 1.0
                logoY   = 0
            }
        }
    }
}
