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
// - Denied/restricted, or simply nothing queued → the SAME card layout with
//   a music-note placeholder, a "Nothing playing" title and a real
//   "Open Music" button. The card never disappears and never fakes a track.
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
    @State private var model = SystemMusicModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GlassCard(padding: AppSpacing.base, cornerRadius: AppRadius.xl) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(spacing: AppSpacing.md) {
                    artwork
                    titleBlock
                    Spacer(minLength: 0)
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
        .onAppear { model.activate() }
        .onDisappear { model.deactivate() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.sync() }
        }
    }

    // MARK: Artwork (real, or the honest placeholder)

    @ViewBuilder private var artwork: some View {
        Group {
            if let image = model.nowPlaying?.artwork {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            } else {
                Image(systemName: "music.note")
                    .font(AppFont.scaled(22, weight: .semibold))
                    .foregroundStyle(Color.brandPink)
                    .frame(width: 56, height: 56)
                    .background(Color.brandPink.opacity(AppOpacity.tintedFill),
                                in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let now = model.nowPlaying {
                if let title = now.title {
                    Text(verbatim: title)
                        .font(AppFont.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                } else {
                    Text("media_unknown_title")
                        .font(AppFont.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                if let artist = now.artist {
                    Text(verbatim: artist)
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("media_nothing_playing")
                    .font(AppFont.subheadline)
                    .foregroundStyle(.primary)
                Text("media_nothing_playing_hint")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
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

    private var progressBar: some View {
        ProgressView(value: model.progress)
            .progressViewStyle(.linear)
            .tint(Color.accentColor)
            .animation(reduceMotion ? nil : .linear(duration: 0.5), value: model.progress)
            .accessibilityLabel(Text("media_progress"))
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

    private var playPauseButton: some View {
        Button {
            HapticFeedback.impact(.light)
            model.togglePlayPause()
        } label: {
            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                .font(AppFont.scaled(18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Color.accentColor, in: Circle())
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(model.isPlaying ? "media_pause" : "media_play")))
    }

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
                .foregroundStyle(active ? Color.accentColor
                                        : Color.primary.opacity(AppOpacity.emphasis))
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
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Color.accentColor, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("media_open_music"))
    }
}
