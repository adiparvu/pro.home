import SwiftUI

// MARK: - Loading skeleton for the message list

struct MessageSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmer = false

    private let rows: [(own: Bool, width: CGFloat)] = [
        (false, 170), (false, 120), (true, 150), (false, 200),
        (true, 110), (true, 180), (false, 140), (true, 160)
    ]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack {
                    if row.own { Spacer(minLength: 60) }
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: row.width, height: 34)
                    if !row.own { Spacer(minLength: 60) }
                }
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.top, AppSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(shimmer ? 0.55 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { shimmer = true }
        }
        .accessibilityHidden(true)
    }
}
