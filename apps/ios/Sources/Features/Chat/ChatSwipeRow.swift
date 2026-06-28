import SwiftUI

// MARK: - Telegram-style swipe row (round colored action buttons)

struct ConvSwipeAction: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let color: Color
    let action: () -> Void
}

struct SwipeableRow<Content: View>: View {
    var leading: [ConvSwipeAction] = []
    var trailing: [ConvSwipeAction] = []
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    @GestureState private var translation: CGFloat = 0

    private let slot: CGFloat = 72
    private var leadingWidth: CGFloat { CGFloat(leading.count) * slot }
    private var trailingWidth: CGFloat { CGFloat(trailing.count) * slot }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                ForEach(leading) { actionButton($0) }
                Spacer(minLength: 0)
                ForEach(trailing) { actionButton($0) }
            }

            content()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .offset(x: offset + translation)
                .overlay {
                    if offset != 0 {
                        Color.black.opacity(0.001)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { offset = 0 }
                            }
                    }
                }
                .highPriorityGesture(
                    DragGesture(minimumDistance: 20)
                        .updating($translation) { v, state, _ in
                            guard abs(v.translation.width) > abs(v.translation.height) else { return }
                            let proposed = offset + v.translation.width
                            let clamped = max(-trailingWidth, min(leadingWidth, proposed))
                            state = clamped - offset
                        }
                        .onEnded { v in
                            let total = offset + v.translation.width
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                if total < -trailingWidth * 0.4 { offset = -trailingWidth }
                                else if total > leadingWidth * 0.4 { offset = leadingWidth }
                                else { offset = 0 }
                            }
                        }
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func actionButton(_ a: ConvSwipeAction) -> some View {
        Button {
            a.action()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { offset = 0 }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle().fill(a.color.gradient)
                    Image(systemName: a.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 46, height: 46)
                .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
                .shadow(color: a.color.opacity(0.45), radius: 5, y: 2)
                Text(LocalizedStringKey(a.label))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.55))
            }
            .frame(width: slot)
        }
        .buttonStyle(.plain)
    }
}
