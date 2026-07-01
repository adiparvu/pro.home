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
            HapticFeedback.impact(.medium)
            a.action()
            close()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: a.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                Text(LocalizedStringKey(a.label))
                    .font(AppFont.label)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: slot - 8)
            .frame(maxHeight: .infinity)
            .background(a.color.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 3).padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}
