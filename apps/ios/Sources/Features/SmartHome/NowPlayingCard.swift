import SwiftUI
import UIKit
import MediaPlayer

// MARK: - Now Playing card (Smart Home S2.6 — reference fidelity)
//
// The reference's media tile, bound to the REAL system music player
// (`MPMusicPlayerController.systemMusicPlayer`): artwork, title/artist, a
// live progress bar, and transport controls that command the actual system
// queue — never a mock player.
//
// Honest states throughout:
// - Library access `.notDetermined` → requested once on appear.
// - Denied/restricted, or simply nothing queued → the card is NOT shown at
//   all (IMG_8618: a permanent "Nothing playing" placeholder is furniture,
//   not information). The empty-state layout below remains for the brief
//   window while a queued item's metadata resolves; it never fakes a track.
// - Play/pause reflects the player's real `playbackState`, kept fresh by
//   `playbackStateDidChange` / `nowPlayingItemDidChange` notifications
//   (via `beginGeneratingPlaybackNotifications`) plus a lightweight elapsed
//   ticker that only runs while music is actually playing.

// MARK: - System music model

/// Observable projection of the system music player. All state is read from
/// the player itself — commands are optimistic only until the next
/// notification lands, so the UI can never drift from reality.
@MainActor
@Observable
final class SystemMusicModel {
    /// One shared listener: the Smart section observes it to decide whether
    /// the media card exists at all, and the card renders from the same
    /// instance — the two can never disagree.
    static let shared = SystemMusicModel()

    struct NowPlaying {
        var title: String?
        var artist: String?
        var artwork: UIImage?
        var duration: TimeInterval
    }

    /// The current queue item, nil when nothing is queued or access is denied.
    private(set) var nowPlaying: NowPlaying?
    private(set) var isPlaying = false
    private(set) var shuffleOn = false
    private(set) var elapsed: TimeInterval = 0

    /// 0…1 fraction for the progress bar; 0 when the duration is unknown.
    var progress: Double {
        guard let duration = nowPlaying?.duration, duration > 0, duration.isFinite,
              elapsed.isFinite else { return 0 }
        return min(1, max(0, elapsed / duration))
    }

    @ObservationIgnored private let player = MPMusicPlayerController.systemMusicPlayer
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var isActive = false

    // MARK: Lifecycle

    /// Starts notifications + the first snapshot. Idempotent; paired with
    /// `deactivate()` from the card's appear/disappear.
    func activate() {
        guard !isActive else { return }
        isActive = true

        if MPMediaLibrary.authorizationStatus() == .notDetermined {
            MPMediaLibrary.requestAuthorization { [weak self] _ in
                Task { @MainActor in self?.sync() }
            }
        }

        player.beginGeneratingPlaybackNotifications()
        let center = NotificationCenter.default
        let refresh: (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in self?.sync() }
        }
        observers = [
            center.addObserver(forName: .MPMusicPlayerControllerPlaybackStateDidChange,
                               object: player, queue: .main, using: refresh),
            center.addObserver(forName: .MPMusicPlayerControllerNowPlayingItemDidChange,
                               object: player, queue: .main, using: refresh),
        ]
        sync()
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        observers.forEach(NotificationCenter.default.removeObserver(_:))
        observers = []
        player.endGeneratingPlaybackNotifications()
        stopTicker()
    }

    /// Re-reads the player's real state (also called when the scene becomes
    /// active again — playback may have changed while we were backgrounded).
    func sync() {
        isPlaying = player.playbackState == .playing
        shuffleOn = player.shuffleMode != .off

        // Reading the queue item requires media-library authorization; the
        // placeholder layout owns every other status honestly.
        if MPMediaLibrary.authorizationStatus() == .authorized,
           let item = player.nowPlayingItem {
            nowPlaying = NowPlaying(
                title: item.title,
                artist: item.artist ?? item.albumArtist,
                artwork: item.artwork?.image(at: CGSize(width: 160, height: 160)),
                duration: item.playbackDuration)
            let time = player.currentPlaybackTime
            elapsed = time.isFinite ? time : 0
        } else {
            nowPlaying = nil
            elapsed = 0
        }

        if isPlaying { startTicker() } else { stopTicker() }
    }

    // MARK: Transport commands (system player — real)

    func togglePlayPause() {
        if isPlaying { player.pause() } else { player.play() }
        // Optimistic flip; the playbackState notification confirms/corrects.
        isPlaying.toggle()
        if isPlaying { startTicker() } else { stopTicker() }
    }

    func skipForward()  { player.skipToNextItem() }
    func skipBackward() { player.skipToPreviousItem() }

    func toggleShuffle() {
        player.shuffleMode = shuffleOn ? .off : .songs
        shuffleOn = player.shuffleMode != .off
    }

    /// Opens the system Music app — the real action behind the placeholder
    /// state's button (`open` needs no `canOpenURL` scheme declaration).
    static func openMusicApp() {
        guard let url = URL(string: "music://") else { return }
        UIApplication.shared.open(url)
    }

    // MARK: Elapsed ticker (runs only while playing)

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying else { return }
                let time = self.player.currentPlaybackTime
                self.elapsed = time.isFinite ? time : 0
            }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}

// MARK: - Card view

struct NowPlayingCard: View {
    private let model = SystemMusicModel.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Artwork footprint / corner radius on the media card, and the soft
    /// shadow that lifts the artwork off the glass.
    private static let artSize: CGFloat = 64
    private static let artRadius: CGFloat = AppRadius.md
    private static let artShadowOpacity: Double = 0.25

    var body: some View {
        GlassCard(padding: AppSpacing.base) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(alignment: .top, spacing: AppSpacing.md) {
                    artwork
                    titleBlock
                    Spacer(minLength: 0)
                    // Source glyph, top-right of the card (the reference's
                    // small provider mark) — decorative, states the source.
                    Image(systemName: "music.note")
                        .font(AppFont.scaled(13, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        .accessibilityHidden(true)
                }

                if model.nowPlaying != nil {
                    progressBar
                    transportRow
                } else {
                    openMusicButton
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Lifecycle lives at the SECTION level (SmartHomeSectionView): the
        // card only exists while something plays, so its own appearance can
        // never be the thing that starts or stops the listener.
    }

    // MARK: Artwork (real, or the honest placeholder)

    @ViewBuilder private var artwork: some View {
        Group {
            if let image = model.nowPlaying?.artwork {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Self.artSize, height: Self.artSize)
                    .clipShape(RoundedRectangle(cornerRadius: Self.artRadius,
                                                style: .continuous))
            } else {
                ZStack {
                    SmartRadialGlow(diameter: 64)
                    Image(systemName: "music.note")
                        .font(AppFont.scaled(22, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: Self.artSize, height: Self.artSize)
                .background(Color.subtleFill,
                            in: RoundedRectangle(cornerRadius: Self.artRadius,
                                                 style: .continuous))
            }
        }
        .shadow(color: .black.opacity(Self.artShadowOpacity), radius: 6, y: 3)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let now = model.nowPlaying {
                if let title = now.title {
                    Text(verbatim: title)
                        .font(AppFont.scaled(15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                } else {
                    Text("media_unknown_title")
                        .font(AppFont.scaled(15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                if let artist = now.artist {
                    Text(verbatim: artist)
                        .font(AppFont.caption)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        .lineLimit(1)
                }
            } else {
                Text("media_nothing_playing")
                    .font(AppFont.scaled(15, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("media_nothing_playing_hint")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.nowPlaying == nil
            ? Text("media_nothing_playing")
            : Text("media_now_playing"))
        .accessibilityValue(Text(verbatim: accessibilityTrackText))
    }

    private var accessibilityTrackText: String {
        guard let now = model.nowPlaying else { return "" }
        return [now.title, now.artist].compactMap { $0 }.joined(separator: " — ")
    }

    // MARK: Progress (live, only meaningful with a real item)

    /// The thin 3pt capsule with an accent fill; elapsed time sits
    /// left-aligned under the bar, the real total (when the player reports
    /// one) right-aligned.
    private static let progressGradient = LinearGradient(
        colors: [Color.accentColor, Color.accentColor.opacity(0.55)],
        startPoint: .leading, endPoint: .trailing)

    private var progressBar: some View {
        VStack(spacing: AppSpacing.xxs) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(AppOpacity.tintedFill))
                    Capsule()
                        .fill(Self.progressGradient)
                        .frame(width: max(3, geo.size.width * model.progress))
                }
            }
            .frame(height: 3)
            .animation(reduceMotion ? nil : .linear(duration: 0.5), value: model.progress)

            HStack {
                Text(verbatim: Self.elapsedText(model.elapsed))
                    .font(AppFont.caption2)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    .monospacedDigit()
                Spacer(minLength: AppSpacing.sm)
                if let duration = model.nowPlaying?.duration,
                   duration > 0, duration.isFinite {
                    Text(verbatim: Self.elapsedText(duration))
                        .font(AppFont.caption2)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        .monospacedDigit()
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("media_progress"))
        .accessibilityValue(Text(verbatim: accessibilityProgressText))
    }

    /// "3:07" alone, or "3:07 / 4:12" when the player reports a duration.
    private var accessibilityProgressText: String {
        let elapsed = Self.elapsedText(model.elapsed)
        guard let duration = model.nowPlaying?.duration,
              duration > 0, duration.isFinite else { return elapsed }
        return "\(elapsed) / \(Self.elapsedText(duration))"
    }

    /// "3:07" — minutes:seconds of real playback time.
    private static func elapsedText(_ elapsed: TimeInterval) -> String {
        let total = max(0, Int(elapsed))
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    // MARK: Transport row — every control commands the system player

    private var transportRow: some View {
        HStack(spacing: 0) {
            transportButton("shuffle", label: "media_shuffle", active: model.shuffleOn) {
                model.toggleShuffle()
            }
            .accessibilityValue(Text(LocalizedStringKey(model.shuffleOn ? "sh_state_on" : "sh_state_off")))
            Spacer(minLength: 0)
            transportButton("backward.fill", label: "media_previous") {
                model.skipBackward()
            }
            Spacer(minLength: 0)
            playPauseButton
            Spacer(minLength: 0)
            transportButton("forward.fill", label: "media_next") {
                model.skipForward()
            }
            Spacer(minLength: 0)
            transportButton("arrow.up.forward.app", label: "media_open_music") {
                SystemMusicModel.openMusicApp()
            }
        }
    }

    /// The plain primary play glyph — no filled disc.
    private var playPauseButton: some View {
        Button {
            HapticFeedback.impact(.light)
            model.togglePlayPause()
        } label: {
            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                .font(AppFont.scaled(26, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(model.isPlaying ? "media_pause" : "media_play")))
    }

    // Controls must NEVER ride hierarchical styles inside glass: `.secondary`
    // resolves through the vibrancy compositor, which ate the skip buttons
    // and timestamps whole on the flat Day wash (IMG_8623 — same failure
    // family as the avatar-ring swatches, IMG_8608). Explicit token colors
    // resolve to real pixels in every backdrop and every OS build.
    private func transportButton(_ icon: String,
                                 label: LocalizedStringKey,
                                 active: Bool = false,
                                 action: @escaping () -> Void) -> some View {
        Button {
            HapticFeedback.impact(.light)
            action()
        } label: {
            Image(systemName: icon)
                .font(AppFont.scaled(15, weight: .semibold))
                .foregroundStyle(active ? AnyShapeStyle(Color.accentColor)
                                        : AnyShapeStyle(Color.primary.opacity(AppOpacity.mediumText)))
                .frame(width: 38, height: 38)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    // MARK: Placeholder action — the one real thing to do when idle

    private var openMusicButton: some View {
        Button {
            HapticFeedback.impact(.light)
            SystemMusicModel.openMusicApp()
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "arrow.up.forward.app")
                    .font(AppFont.captionEmphasis)
                Text("media_open_music")
                    .font(AppFont.footnoteEmphasis)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .mediaGlass(in: Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("media_open_music"))
    }
}
