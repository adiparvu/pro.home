import SwiftUI

// MARK: - Sticker Bubble (rendered inside MessageBubble / DMBubble)
//
// The catalog picker was removed, so stickers can no longer be sent — this
// bubble stays so every already-sent sticker message keeps rendering from
// the static StickerCatalog.

struct StickerBubble: View {
    let stickerId: String
    @State private var appeared = false

    private var sticker: Sticker? { StickerCatalog.sticker(id: stickerId) }

    var body: some View {
        VStack(spacing: 5) {
            Text(sticker?.emoji ?? "🏠")
                .font(AppFont.scaled(84))
                .frame(width: 110, height: 100)
                .scaleEffect(appeared ? 1.0 : 0.6)
                .opacity(appeared ? 1.0 : 0.0)
            if let label = sticker?.label {
                Text(LocalizedStringKey(label))
                    .font(AppFont.caption2)
                    .foregroundStyle(Color.primary.opacity(0.38))
                    .opacity(appeared ? 1.0 : 0.0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                appeared = true
            }
        }
    }
}
