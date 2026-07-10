import SwiftUI

// MARK: - iMessage-style invisible chat header
//
// The chat has no opaque bar: the conversation scrolls to the very top and
// a soft progressive blur fades it out under the floating controls — the
// same effect iMessage uses. The blur is a material masked by a vertical
// gradient (SwiftUI's closest public equivalent of a variable blur), and
// it never intercepts touches.

struct ChatTopBlur: View {
    var height: CGFloat = 130

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .mask(
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.45),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            )
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Floating glass toolbar pieces

extension View {
    /// Capsule chrome for a control (or control cluster) hosted in the chat
    /// navigation toolbar. On iOS 26 the system already wraps every
    /// `ToolbarItem`'s content in its own Liquid Glass capsule — drawing our
    /// own material inside it produced two visibly stacked capsules — so
    /// there this adds nothing and lets the system glass be the only chrome.
    /// Pre-26 it applies the hand-drawn glass capsule the chat header has
    /// always used (ultra-thin material + hairline stroke), pixel-identical
    /// to before.
    @ViewBuilder
    func chatToolbarCapsule() -> some View {
        if #available(iOS 26, *) {
            self
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 0.5))
        }
    }
}

/// The centered identity pill (avatar + name + status) — a soft glass
/// capsule like iMessage's contact pill, so it stays readable over any
/// wallpaper without needing a bar behind it.
struct ChatHeaderPill<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, 5)
            .chatToolbarCapsule()
    }
}

/// The trailing action cluster (video / call) in one glass capsule.
struct ChatHeaderActions: View {
    var onVideo: () -> Void
    var onCall: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button {
                HapticFeedback.impact(.light)
                onVideo()
            } label: {
                Image(systemName: "video.fill")
                    .font(AppFont.subheadline)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Video call")

            Button {
                HapticFeedback.impact(.light)
                onCall()
            } label: {
                Image(systemName: "phone.fill")
                    .font(AppFont.subheadline)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Call")
        }
        .chatToolbarCapsule()
    }
}
