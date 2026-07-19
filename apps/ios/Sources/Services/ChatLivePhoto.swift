import SwiftUI
import Photos
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Live Photos in chat (wire format + assembly)
//
// A Live Photo travels as TWO files under ONE uuid stem in the private
// chat-media bucket — `<stem>.jpg` (the recompressed still, stored in
// attachment_url) and `<stem>.mov` (the paired motion) — with
// attachment_type "live". No schema change: the motion path is derived by
// swapping the extension. Recipients see the still instantly (it is a
// plain image bubble with a LIVE badge); opening it downloads the pair
// and rebuilds a PHLivePhoto for the system press-and-hold playback.

enum ChatLivePhoto {
    /// The two halves extracted from a picker-vended Live Photo:
    /// the still recompressed to the chat-display cap, the motion as shot.
    struct Pair {
        let still: Data
        let video: Data
    }

    /// True when a picker item carries a Live Photo.
    static func isLive(_ item: PhotosPickerItem) -> Bool {
        item.supportedContentTypes.contains { $0.conforms(to: .livePhoto) }
    }

    /// Loads the pair from a picker item. Returns nil when the item isn't a
    /// Live Photo or either half can't be read — callers fall back to the
    /// plain-image path so a send never silently drops.
    static func pair(from item: PhotosPickerItem) async -> Pair? {
        guard isLive(item),
              let live = try? await item.loadTransferable(type: PHLivePhoto.self) else { return nil }
        let resources = PHAssetResource.assetResources(for: live)
        guard let photoRes = resources.first(where: { $0.type == .photo }),
              let videoRes = resources.first(where: { $0.type == .pairedVideo }) else { return nil }
        guard let rawStill = await data(for: photoRes),
              let video = await data(for: videoRes),
              let image = UIImage(data: rawStill),
              let jpeg = image.uploadJPEG(quality: 0.8, maxDimension: 2048) else { return nil }
        return Pair(still: jpeg, video: video)
    }

    /// Streams one PHAssetResource into memory (chunks arrive serially).
    private static func data(for resource: PHAssetResource) async -> Data? {
        final class Buffer: @unchecked Sendable { var data = Data() }
        let buffer = Buffer()
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { cont in
            PHAssetResourceManager.default().requestData(for: resource, options: options) { chunk in
                buffer.data.append(chunk)
            } completionHandler: { error in
                cont.resume(returning: error == nil ? buffer.data : nil)
            }
        }
    }

    // MARK: Reassembly (recipient side)

    /// Downloads both halves of a "live" attachment (still path from
    /// attachment_url) into a session cache and rebuilds the PHLivePhoto.
    /// Files are cached by path so reopening the same photo is instant.
    static func load(stillPath: String) async -> PHLivePhoto? {
        guard let stillURL = await ChatMedia.resolve(stillPath),
              let videoURL = await ChatMedia.resolve(ChatMedia.liveVideoPath(for: stillPath)) else { return nil }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-live", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = stillPath.replacingOccurrences(of: "/", with: "_")
        let jpg = dir.appendingPathComponent(safe)
        let mov = dir.appendingPathComponent((safe as NSString).deletingPathExtension + ".mov")
        do {
            if !FileManager.default.fileExists(atPath: jpg.path) {
                let (data, _) = try await URLSession.shared.data(from: stillURL)
                try data.write(to: jpg)
            }
            if !FileManager.default.fileExists(atPath: mov.path) {
                let (data, _) = try await URLSession.shared.data(from: videoURL)
                try data.write(to: mov)
            }
        } catch { return nil }
        let placeholder = UIImage(contentsOfFile: jpg.path)
        return await assemble(still: jpg, video: mov, placeholder: placeholder)
    }

    /// PHLivePhoto.request delivers a degraded pass first — resume only on
    /// the final result, guarded against double resume.
    private static func assemble(still: URL, video: URL, placeholder: UIImage?) async -> PHLivePhoto? {
        final class Flag: @unchecked Sendable { var resumed = false }
        let flag = Flag()
        return await withCheckedContinuation { cont in
            PHLivePhoto.request(withResourceFileURLs: [still, video],
                                placeholderImage: placeholder,
                                targetSize: .zero,
                                contentMode: .aspectFit) { live, info in
                let degraded = (info[PHLivePhotoInfoIsDegradedKey] as? NSNumber)?.boolValue ?? false
                guard !degraded, !flag.resumed else { return }
                flag.resumed = true
                cont.resume(returning: live)
            }
        }
    }
}

// MARK: - Playback view

/// The system Live Photo surface — press and hold plays motion + sound,
/// exactly the Photos-app gesture (the recognizer is the view's own).
struct LivePhotoPlaybackView: UIViewRepresentable {
    let livePhoto: PHLivePhoto

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        view.addGestureRecognizer(view.playbackGestureRecognizer)
        return view
    }

    func updateUIView(_ view: PHLivePhotoView, context: Context) {
        view.livePhoto = livePhoto
    }
}

// MARK: - Full-screen viewer

/// Full-screen Live Photo: the still shows immediately while the pair
/// downloads; once assembled, press-and-hold brings it to life. The hint
/// capsule teaches the gesture and fades after a beat.
struct LivePhotoViewer: View {
    let stored: String
    @Environment(\.dismiss) private var dismiss

    @State private var live: PHLivePhoto?
    @State private var stillURL: URL?
    @State private var failed = false
    @State private var showHint = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let live {
                LivePhotoPlaybackView(livePhoto: live)
                    .ignoresSafeArea()
            } else {
                StorageImage(url: stillURL) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFit()
                    } else {
                        ProgressView().tint(.white)
                    }
                }
                .ignoresSafeArea()
            }

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(AppFont.scaled(15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel(Text("Close"))
                    Spacer()
                    Image(systemName: "livephoto")
                        .font(AppFont.scaled(17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: Circle())
                        .accessibilityHidden(true)
                }
                Spacer()
                if live != nil, showHint {
                    Text(failed ? "live_unavailable" : "live_hold_hint")
                        .font(AppFont.scaled(13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppSpacing.base)
                        .padding(.vertical, AppSpacing.sm)
                        .background(.ultraThinMaterial, in: Capsule())
                        .transition(.opacity)
                } else if failed {
                    Text("live_unavailable")
                        .font(AppFont.scaled(13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, AppSpacing.base)
                        .padding(.vertical, AppSpacing.sm)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding(AppSpacing.lg)
        }
        .task {
            stillURL = await ChatMedia.resolve(stored)
            live = await ChatLivePhoto.load(stillPath: stored)
            if live == nil { failed = true }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation(.smooth(duration: 0.5)) { showHint = false }
        }
    }
}
