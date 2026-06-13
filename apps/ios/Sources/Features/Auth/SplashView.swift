import SwiftUI

struct SplashView: View {
    @State private var scale: CGFloat = 0.85
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                appIconView
                    .scaleEffect(scale)
                    .opacity(opacity)

                Text("PRVHouse")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .opacity(opacity)

                ProgressView()
                    .tint(.primary.opacity(0.35))
                    .padding(.top, 8)
                    .opacity(opacity)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
                scale = 1.0
                opacity = 1.0
            }
        }
    }

    private var appIconView: some View {
        Group {
            if let img = UIImage(named: "AppIcon") {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .blue.opacity(0.45), radius: 20, y: 8)
            } else {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 96, height: 96)
                    .overlay(
                        Text("P")
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    )
                    .shadow(color: .blue.opacity(0.45), radius: 20, y: 8)
            }
        }
    }
}
