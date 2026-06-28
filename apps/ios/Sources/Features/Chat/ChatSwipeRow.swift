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
    @State private var lastOffset: CGFloat = 0

    private let slot: CGFloat = 76
    private var leadingWidth: CGFloat { CGFloat(leading.count) * slot }
    private var trailingWidth: CGFloat { CGFloat(trailing.count) * slot }

    private func close() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { offset = 0; lastOffset = 0 }
    }

    var body: some View {
        ZStack {
            // Action buttons only exist while actively swiping — avoids a colour
            // "flash" behind rows during list/filter transitions.
            if offset > 0 {
                HStack(spacing: 0) {
                    ForEach(leading) { actionButton($0) }
                    Spacer(minLength: 0)
                }
            } else if offset < 0 {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ForEach(trailing) { actionButton($0) }
                }
            }

            content()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .offset(x: offset)
                .overlay {
                    if offset != 0 {
                        Color.black.opacity(0.001)
                            .contentShape(Rectangle())
                            .onTapGesture { close() }
                            .offset(x: offset)
                    }
                }
                .highPriorityGesture(
                    DragGesture(minimumDistance: 24)
                        .onChanged { v in
                            guard abs(v.translation.width) > abs(v.translation.height) else { return }
                            let new = lastOffset + v.translation.width
                            offset = max(-trailingWidth, min(leadingWidth, new))
                        }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                if offset < -trailingWidth * 0.4 { offset = -trailingWidth }
                                else if offset > leadingWidth * 0.4 { offset = leadingWidth }
                                else { offset = 0 }
                                lastOffset = offset
                            }
                        }
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func actionButton(_ a: ConvSwipeAction) -> some View {
        Button {
            a.action()
            close()
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
