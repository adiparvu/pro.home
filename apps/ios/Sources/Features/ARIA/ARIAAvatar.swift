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

    // MARK: Decoded-photo memo
    //
    // The avatar renders in chat rows and headers, and `loadPhoto()` was a
    // synchronous main-thread JPEG decode on every body pass. The decode now
    // happens once per revision, off the main actor, and is memoized.

    private static let decoded = NSCache<NSString, UIImage>()

    /// Cache-only lookup for the current revision — safe on the render path.
    static func cachedPhoto(revision: Int) -> UIImage? {
        decoded.object(forKey: "rev-\(revision)" as NSString)
    }

    /// Decodes the photo off the main actor and memoizes it per revision
    /// (a re-upload bumps the revision, which naturally drops the old decode).
    static func loadPhotoAsync(revision: Int) async -> UIImage? {
        if let hit = cachedPhoto(revision: revision) { return hit }
        let path = photoURL.path
        let img = await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: path)
        }.value
        if let img {
            decoded.removeAllObjects()   // only the current revision matters
            decoded.setObject(img, forKey: "rev-\(revision)" as NSString)
        }
        return img
    }
}

struct ARIAAvatar: View {
    var size: CGFloat = 28

    @AppStorage("prvio.aria.avatarKind") private var kind = "icon"
    @AppStorage("prvio.aria.avatarIcon") private var icon = "sparkles"
    @AppStorage("prvio.aria.avatarEmoji") private var emoji = "✨"
    /// Bumped whenever the photo file is replaced so views re-read it.
    @AppStorage("prvio.aria.avatarRev") private var revision = 0
    @State private var loadedPhoto: UIImage?
    /// True once an async load came back empty — falls through to the icon,
    /// exactly like the old synchronous `loadPhoto()` nil path.
    @State private var photoMissing = false

    var body: some View {
        ZStack {
            if kind == "photo", let photo = loadedPhoto ?? ARIAAvatarStore.cachedPhoto(revision: revision) {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .id(revision)
            } else if kind == "photo" && !photoMissing {
                // Placeholder for the decode's first few milliseconds.
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: size, height: size)
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
        .task(id: "\(kind)-\(revision)") {
            guard kind == "photo" else { return }
            guard ARIAAvatarStore.cachedPhoto(revision: revision) == nil else { return }
            loadedPhoto = nil
            photoMissing = false
            loadedPhoto = await ARIAAvatarStore.loadPhotoAsync(revision: revision)
            photoMissing = loadedPhoto == nil
        }
    }
}
