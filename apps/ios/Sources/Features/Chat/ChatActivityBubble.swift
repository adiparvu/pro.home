// The WhatsApp-style in-thread activity indicator: a small incoming-side
// bubble showing three cascading dots while the peer types, or a pulsing mic
// while they record a voice message (IMG_8298/8299). It renders from the same
// realtime typing broadcast the header subtitle uses — never fabricated state.
import SwiftUI

/// What the peer is doing right now, resolved from the typing broadcast's
/// `kind`. Recording wins over typing when both are live for the same name.
enum ChatActivityKind: Equatable {
    case typing
    case recording
}

struct ChatActivityBubble: View {
    let kind: ChatActivityKind
    /// Group chats label the bubble with who is typing (the bubble alone is
    /// ambiguous with several senders); DMs pass nil — the peer is implicit.
    var label: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let label {
                Text(label)
                    .font(AppFont.scaled(11, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                    .padding(.leading, AppSpacing.xs)
            }
            content
                .frame(minWidth: 34, minHeight: 17)
                .padding(.horizontal, 13).padding(.vertical, 9)
                .background(Color.primary.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind == .typing
            ? Text("chat_activity_typing_a11y")
            : Text("chat_activity_recording_a11y"))
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .typing:
            if reduceMotion {
                dots { _ in (1, 0.55) }
            } else {
                // One shared clock, three phase-shifted dots — a single
                // PhaseAnimator invalidation per step instead of three timers.
                PhaseAnimator([0, 1, 2]) { phase in
                    dots { index in
                        index == phase ? (1.25, 0.9) : (1, 0.35)
                    }
                } animation: { _ in .easeInOut(duration: 0.35) }
            }
        case .recording:
            Image(systemName: "mic.fill")
                .font(AppFont.scaled(15))
                .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
        }
    }

    private func dots(_ style: @escaping (Int) -> (scale: CGFloat, opacity: Double)) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                let s = style(i)
                Circle()
                    .fill(Color.primary.opacity(AppOpacity.emphasis))
                    .frame(width: 7, height: 7)
                    .scaleEffect(s.scale)
                    .opacity(s.opacity)
            }
        }
    }
}
