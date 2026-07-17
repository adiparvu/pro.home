import SwiftUI

// MARK: - Telegram-style swipe row (round colored action buttons)

struct ConvSwipeAction: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let color: Color
    let action: () -> Void
}

/// How a swipe row dresses: `.card` = its own Liquid Glass rounded card
/// (Send Later queue); `.plain` = naked content in a continuous list —
/// the iOS-Messages look the conversation list uses (IMG_8556), where
/// hairline dividers, not cards, separate rows. Top-level (not nested in
/// the generic row) so the helper modifiers reference one concrete type.
enum SwipeRowStyle { case card, plain }

struct SwipeableRow<Content: View>: View {
    var leading: [ConvSwipeAction] = []
    var trailing: [ConvSwipeAction] = []
    var style: SwipeRowStyle = .card
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
                // `.card`: native Liquid Glass rounded card. `.plain`: naked
                // content on the page background (iOS-Messages look) — the
                // bar material backs it ONLY mid-swipe, so the revealed
                // action buttons never show through the sliding row.
                .modifier(SwipeRowDress(style: style, isSwiping: offset != 0))
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
        .clipShape(SwipeRowClip(style: style))
    }

    private func actionButton(_ a: ConvSwipeAction) -> some View {
        Button {
            HapticFeedback.impact(.medium)
            a.action()
            close()
        } label: {
            VStack(spacing: 5) {
                Image(systemName: a.icon)
                    .font(AppFont.scaled(20, weight: .semibold))
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

/// `.card` keeps the row's own Liquid Glass; `.plain` adds no chrome at
/// rest and backs the content with the bar material only mid-swipe.
private struct SwipeRowDress: ViewModifier {
    let style: SwipeRowStyle
    let isSwiping: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .card:
            content.liquidGlass(cornerRadius: AppRadius.lg)
        case .plain:
            content.background {
                if isSwiping { Rectangle().fill(.thinMaterial) }
            }
        }
    }
}

/// Card rows clip to their rounded rect; plain rows clip to a plain
/// rectangle so the swipe offset stays contained without rounding a
/// continuous list's edges.
private struct SwipeRowClip: Shape {
    let style: SwipeRowStyle

    func path(in rect: CGRect) -> Path {
        switch style {
        case .card:
            return RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous).path(in: rect)
        case .plain:
            return Rectangle().path(in: rect)
        }
    }
}
