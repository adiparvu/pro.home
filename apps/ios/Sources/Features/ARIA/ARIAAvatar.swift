import SwiftUI
import UIKit

// MARK: - The assistant's face
//
// One component renders the assistant's identity everywhere it appears —
// chat bubbles, the conversations row, settings. The owner chooses an SF
// icon, an emoji, or their own photo; the choice is device-private, like
// the assistant's custom name.

enum ARIAAvatarStore {
    static var photoURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("aria-avatar.jpg")
    }

    /// Saves a downscaled avatar photo and returns whether it persisted.
    @discardableResult
    static func savePhoto(_ image: UIImage) -> Bool {
        guard let data = image.uploadJPEG(quality: 0.85, maxDimension: 512) else { return false }
        return (try? data.write(to: photoURL, options: .atomic)) != nil
    }

    static func loadPhoto() -> UIImage? {
        UIImage(contentsOfFile: photoURL.path)
    }
}

struct ARIAAvatar: View {
    var size: CGFloat = 28

    @AppStorage("prvio.aria.avatarKind") private var kind = "icon"
    @AppStorage("prvio.aria.avatarIcon") private var icon = "sparkles"
    @AppStorage("prvio.aria.avatarEmoji") private var emoji = "✨"
    /// Bumped whenever the photo file is replaced so views re-read it.
    @AppStorage("prvio.aria.avatarRev") private var revision = 0

    var body: some View {
        ZStack {
            if kind == "photo", let photo = ARIAAvatarStore.loadPhoto() {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .id(revision)
            } else if kind == "emoji" {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: size, height: size)
                Text(emoji.isEmpty ? "✨" : emoji)
                    .font(.system(size: size * 0.52))
            } else {
                Circle()
                    .fill(LinearGradient(colors: [Color.brandPurple, Color.brandPrimaryBlue],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: size, height: size)
                Image(systemName: icon)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
