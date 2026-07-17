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
                PRVIOLogoView(size: 100)
                    .shadow(color: Color.brandSkyBlue.opacity(0.60), radius: 28, y: 10)
                    .scaleEffect(scale)
                    .offset(y: logoY)
                    .opacity(opacity)

                VStack(spacing: 4) {
                    Text("PRVIO")
                        .font(AppFont.scaled(26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Property management")
                        .font(AppFont.footnote)
                        .foregroundStyle(.white.opacity(0.45))
                        .tracking(0.5)
                }
                .opacity(opacity)

                ProgressView()
                    .tint(.white.opacity(0.30))
                    .padding(.top, AppSpacing.xs)
                    .opacity(opacity)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(AppMotion.emphasis) {
                scale   = 1.0
                opacity = 1.0
                logoY   = 0
            }
        }
    }
}
