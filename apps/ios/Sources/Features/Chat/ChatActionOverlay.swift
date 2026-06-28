import SwiftUI

// MARK: - WhatsApp-style long-press action overlay
// Full-screen blur, emoji reactions pill above the message, action menu below.

struct ChatActionItem: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let destructive: Bool
    let action: () -> Void
    init(_ label: String, _ icon: String, destructive: Bool = false, action: @escaping () -> Void) {
        self.label = label; self.icon = icon; self.destructive = destructive; self.action = action
    }
}

struct ChatActionOverlay: View {
    let previewText: String
    let isOwn: Bool
    let bubbleColor: Color
    let myReaction: String?
    let onReact: (String) -> Void
    let actions: [ChatActionItem]
    let onDismiss: () -> Void

    private static let emojis = ["👍", "❤️", "😂", "😮", "😢", "🙏"]
    @State private var appear = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(alignment: isOwn ? .trailing : .leading, spacing: 12) {
                reactionPill
                bubble
                menu
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: isOwn ? .trailing : .leading)
            .scaleEffect(reduceMotion ? 1 : (appear ? 1 : 0.92))
            .opacity(appear ? 1 : 0)
        }
        .onAppear {
            if reduceMotion { appear = true }
            else { withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { appear = true } }
        }
    }

    private var reactionPill: some View {
        HStack(spacing: 10) {
            ForEach(Self.emojis, id: \.self) { e in
                Button {
                    HapticFeedback.impact(.light); onReact(e); onDismiss()
                } label: {
                    Text(e)
                        .font(.system(size: 28))
                        .scaleEffect(myReaction == e ? 1.2 : 1)
                        .padding(4)
                        .background(myReaction == e ? Color.accentColor.opacity(0.18) : Color.clear, in: Circle())
                }
                .buttonStyle(.plain)
            }
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.5))
                .frame(width: 34, height: 34)
                .background(Color.primary.opacity(0.08), in: Circle())
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
    }

    private var bubble: some View {
        Text(previewText)
            .font(.system(size: 15))
            .foregroundStyle(isOwn ? .white : .primary)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(isOwn ? bubbleColor : Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .frame(maxWidth: 280, alignment: isOwn ? .trailing : .leading)
            .lineLimit(6)
    }

    private var menu: some View {
        VStack(spacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { idx, item in
                Button {
                    item.action(); onDismiss()
                } label: {
                    HStack {
                        Text(LocalizedStringKey(item.label))
                            .font(.system(size: 17))
                        Spacer()
                        Image(systemName: item.icon)
                            .font(.system(size: 17))
                    }
                    .foregroundStyle(item.destructive ? Color.red : Color.primary)
                    .padding(.horizontal, 16).padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if idx < actions.count - 1 { Divider().padding(.leading, 16) }
            }
        }
        .frame(width: 240)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
}
