import SwiftUI
import AVKit

// MARK: - Full-screen video player

struct VideoPlayerSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: AVPlayer(url: url))
                .ignoresSafeArea()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(AppFont.scaled(30))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(AppSpacing.lg)
            }
            .accessibilityLabel("Close")
        }
    }
}

// MARK: - Full-screen image viewer (pinch zoom + pan + swipe to dismiss)

struct ImageViewerItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct FilePreviewItem: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
}

struct FullScreenImageViewer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @GestureState private var gestureScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var gestureOffset: CGSize = .zero
    /// The decoded image, captured once it loads so Share sends the actual
    /// photo (SwiftUI.Image is Transferable) instead of a short-lived signed
    /// URL that 403s after it expires.
    @State private var loadedImage: Image?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            StorageImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable()
                        .scaledToFit()
                        .scaleEffect(scale * gestureScale)
                        .offset(x: offset.width + gestureOffset.width,
                                y: offset.height + gestureOffset.height)
                        .gesture(magnification)
                        .simultaneousGesture(dragGesture)
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3)) {
                                if scale > 1 { scale = 1; offset = .zero } else { scale = 2.5 }
                            }
                        }
                        .onAppear { loadedImage = img }
                case .failure:
                    Image(systemName: "photo")
                        .font(AppFont.scaled(60))
                        .foregroundStyle(.white.opacity(0.4))
                default:
                    ProgressView().tint(.white)
                }
            }

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(AppFont.scaled(15, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(AppSpacing.md)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Close")
                    .padding(.trailing, 18)
                    .padding(.top, AppSpacing.sm)
                }
                Spacer()
                if let loadedImage {
                    ShareLink(item: loadedImage,
                              preview: SharePreview(Text("Photo"), image: loadedImage)) {
                        Image(systemName: "square.and.arrow.up")
                            .font(AppFont.headline)
                            .foregroundStyle(.white)
                            .padding(AppSpacing.base)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Share")
                    .padding(.bottom, 30)
                }
            }
        }
    }

    private var magnification: some Gesture {
        MagnificationGesture()
            .updating($gestureScale) { value, state, _ in state = value }
            .onEnded { value in
                scale = max(1, min(4, scale * value))
                if scale <= 1 { withAnimation(.spring(response: 0.3)) { offset = .zero } }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .updating($gestureOffset) { value, state, _ in
                if scale > 1 { state = value.translation }
            }
            .onEnded { value in
                if scale > 1 {
                    offset.width += value.translation.width
                    offset.height += value.translation.height
                } else if value.translation.height > 100 {
                    dismiss()
                }
            }
    }
}
