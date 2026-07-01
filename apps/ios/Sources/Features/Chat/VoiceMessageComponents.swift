import SwiftUI
import Observation
import AVFoundation
import CoreMedia

// MARK: - Audio Recorder

@MainActor
@Observable
final class ChatAudioRecorder: NSObject, AVAudioRecorderDelegate {
    var isRecording = false
    var duration: TimeInterval = 0

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var timer: Timer?
    private(set) var recordingURL: URL?

    func start() {
        let status = AVAudioApplication.shared.recordPermission
        if status == .denied { return }
        if status == .undetermined {
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                guard granted else { return }
                Task { @MainActor [weak self] in self?.beginRecording() }
            }
            return
        }
        beginRecording()
    }

    private func beginRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
#if DEBUG
            print("[Recorder] session error: \(error)")
#endif
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            recorder = try AVAudioRecorder(url: url, settings: settings)
        } catch {
#if DEBUG
            print("[Recorder] init error: \(error)")
#endif
            try? session.setActive(false)
            return
        }
        recorder?.delegate = self
        guard recorder?.record() == true else {
            recorder = nil
            try? session.setActive(false)
            return
        }
        recordingURL = url
        isRecording = true
        duration = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.duration += 0.1 }
        }
    }

    // Returns nil if recording was shorter than 0.5 s — AVAudioRecorder writes a valid
    // M4A container but AVURLAsset reads 0 duration for very short clips, causing the
    // play button to crash when AVPlayer tries to load them.
    func stop() -> URL? {
        timer?.invalidate(); timer = nil
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false
        let url = recordingURL
        let capturedDuration = duration
        recordingURL = nil
        duration = 0
        guard capturedDuration >= 0.5 else { return nil }
        return url
    }

    deinit {
        // Timer was scheduled on the main RunLoop — must be invalidated there.
        // Capture both so we don't reference self in the async block. Timer and
        // AVAudioRecorder aren't Sendable; nonisolated(unsafe) is sound here
        // because deinit holds the last reference — no concurrent access exists.
        nonisolated(unsafe) let t = timer   // Timer isn't Sendable; recorder is
        let r = recorder
        DispatchQueue.main.async { t?.invalidate(); r?.stop() }
    }

    var durationText: String {
        let s = Int(duration)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Hold-to-record button

struct VoiceRecordButton: View {
    var recorder: ChatAudioRecorder
    let onSend: (URL) -> Void

    @State private var cancelled = false

    var body: some View {
        ZStack {
            if recorder.isRecording {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .symbolEffect(.pulse)
                    Text(recorder.durationText)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary)
                    Text("Slide to cancel")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.4))
                }
                .padding(.horizontal, AppSpacing.md)
                .transition(.opacity.combined(with: .scale))
            }

            Image(systemName: recorder.isRecording ? "waveform" : "mic.fill")
                .font(AppFont.headline)
                .foregroundStyle(recorder.isRecording ? Color.red : Color.primary.opacity(0.55))
                .symbolEffect(.pulse, isActive: recorder.isRecording)
                .frame(width: 30, height: 30)
                .opacity(recorder.isRecording ? 0 : 1)
        }
        .gesture(
            LongPressGesture(minimumDuration: 0.3)
                .onEnded { _ in
                    guard !recorder.isRecording else { return }
                    cancelled = false
                    recorder.start()
                    HapticFeedback.impact(.medium)
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { val in
                    if val.translation.width < -60 && recorder.isRecording && !cancelled {
                        cancelled = true
                        _ = recorder.stop()
                        HapticFeedback.warning()
                    }
                }
                .onEnded { _ in
                    guard recorder.isRecording, !cancelled else { cancelled = false; return }
                    if let url = recorder.stop() { onSend(url) }
                }
        )
    }
}

// MARK: - Audio playback bubble

struct AudioBubble: View {
    /// Stored attachment value — a chat-media path or a legacy public URL. It is
    /// resolved to a short-lived signed URL for playback.
    let audioValue: String?
    let isOwn: Bool
    var avatarURL: URL? = nil
    var initials: String = ""
    var avatarColor: Color = .secondary
    var timeText: String = ""
    var tick: AudioTick = .none
    /// Outgoing-bubble fill — driven by the selected chat theme.
    var bubbleColor: Color = Color.blue.opacity(0.75)

    enum AudioTick { case none, sent, delivered, read }

    @State private var player = AudioPlayer()
    @State private var loadedDuration: TimeInterval = 0
    /// Signed URL resolved from `audioValue` (nil while resolving).
    @State private var url: URL?

    private var subFg: Color { isOwn ? Color.white.opacity(0.7) : Color.primary.opacity(AppOpacity.mediumText) }

    var body: some View {
        HStack(spacing: 10) {
            avatar
            playButton
            VStack(alignment: .leading, spacing: 5) {
                waveform
                bottomRow
            }
        }
        .padding(.horizontal, AppSpacing.md).padding(.vertical, 9)
        .background(
            isOwn ? bubbleColor : Color.primary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .frame(minWidth: 230, maxWidth: 290)
        .task(id: audioValue ?? "") {
            guard let audioValue else { url = nil; return }
            url = await ChatMedia.resolve(audioValue)
        }
        .task(id: url) {
            guard let url, loadedDuration == 0 else { return }
            let asset = AVURLAsset(url: url)
            if let cmTime = try? await asset.load(.duration) {
                let secs = CMTimeGetSeconds(cmTime)
                if secs.isFinite && secs > 0 {
                    loadedDuration = secs
                    player.totalDuration = secs
                }
            }
        }
        .onDisappear { player.stop() }
    }

    // Sender avatar with the WhatsApp-style mic badge.
    private var avatar: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let avatarURL {
                    AsyncImage(url: avatarURL) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                        } else {
                            avatarPlaceholder
                        }
                    }
                } else {
                    avatarPlaceholder
                }
            }
            .frame(width: 46, height: 46)
            .clipShape(Circle())

            Image(systemName: "mic.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isOwn ? bubbleColor.opacity(1) : Color.accentColor)
                .padding(AppSpacing.xxs)
                .background(Circle().fill(.white))
                .offset(x: 3, y: 3)
        }
    }

    private var avatarPlaceholder: some View {
        Circle().fill(avatarColor.opacity(0.25))
            .overlay(
                Text(initials)
                    .font(AppFont.headline)
                    .foregroundStyle(avatarColor)
            )
    }

    private var playButton: some View {
        Button {
            if player.isPlaying { player.pause() }
            else if let url { player.play(url: url) }
        } label: {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(isOwn ? .white : Color.accentColor)
                .frame(width: 26)
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
        .accessibilityLabel(player.isPlaying ? "Pause" : "Play voice message")
    }

    // Waveform with a draggable scrubber dot.
    private var waveform: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                VoiceWaveform(progress: player.progress, isOwn: isOwn, seed: Self.seed(for: url))
                Circle()
                    .fill(isOwn ? Color.white : Color.accentColor)
                    .frame(width: 11, height: 11)
                    .offset(x: max(0, min(geo.size.width - 11, geo.size.width * player.progress - 5.5)))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard geo.size.width > 0 else { return }
                        player.seek(toFraction: Double(v.location.x / geo.size.width))
                    }
            )
        }
        .frame(height: 26)
    }

    private var bottomRow: some View {
        HStack(spacing: 6) {
            Text(player.isPlaying ? player.positionText : durationText)
                .font(.system(size: 11))
                .foregroundStyle(subFg)
            if player.isPlaying {
                Button { player.cycleRate() } label: {
                    Text(player.rate == 1.0 ? "1×" : (player.rate == 1.5 ? "1.5×" : "2×"))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(isOwn ? .white : Color.accentColor)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background((isOwn ? Color.white.opacity(0.2) : Color.accentColor.opacity(0.12)), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 4)
            if !timeText.isEmpty {
                Text(timeText)
                    .font(.system(size: 10))
                    .foregroundStyle(subFg)
            }
            tickView
        }
    }

    @ViewBuilder private var tickView: some View {
        switch tick {
        case .none:
            EmptyView()
        case .sent:
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(subFg)
        case .delivered, .read:
            ZStack(alignment: .leading) {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).offset(x: 3.5)
            }
            .frame(width: 14, alignment: .leading)
            .foregroundStyle(tick == .read ? .white : subFg)
        }
    }

    private var durationText: String {
        guard loadedDuration > 0 else { return "-:--" }
        let s = Int(loadedDuration)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Stable seed from the URL so each clip gets a consistent waveform shape.
    static func seed(for url: URL?) -> UInt64 {
        guard let s = url?.absoluteString else { return 1 }
        var hash: UInt64 = 1469598103934665603 // FNV-1a
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return hash
    }
}

// MARK: - Voice waveform (stylized; deterministic from the clip URL)

private struct VoiceWaveform: View {
    let progress: Double
    let isOwn: Bool
    let seed: UInt64
    private let barCount = 34

    private var heights: [CGFloat] {
        var state = seed | 1
        return (0..<barCount).map { _ in
            // xorshift for a deterministic pseudo-random 0.25...1.0 height
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return 0.25 + CGFloat(state % 1000) / 1000.0 * 0.75
        }
    }

    var body: some View {
        GeometryReader { geo in
            let bars = heights
            let played = Int((Double(barCount) * progress).rounded())
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule()
                        .fill(color(for: i, played: played))
                        .frame(height: max(3, geo.size.height * bars[i]))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    private func color(for index: Int, played: Int) -> Color {
        if index < played {
            return isOwn ? Color.white : Color.accentColor
        }
        return isOwn ? Color.white.opacity(0.35) : Color.primary.opacity(0.2)
    }
}

// MARK: - Audio Player (AVPlayer — supports remote HTTPS URLs)
// AVAudioPlayer only works with local files. All chat audio lives in Supabase
// Storage (HTTPS), so AVPlayer is required here.

@MainActor
@Observable
final class AudioPlayer {
    var isPlaying = false
    var progress: Double = 0
    var position: TimeInterval = 0
    var rate: Float = 1.0
    var totalDuration: TimeInterval = 0

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserverToken: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    func play(url: URL) {
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)

        let item = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: item)
        player = avPlayer

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            // Delivered on .main (queue above), so main-actor access is valid.
            MainActor.assumeIsolated { self?.didFinishPlaying() }
        }

        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserverToken = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            // Delivered on .main (queue above), so main-actor access is valid.
            MainActor.assumeIsolated {
                guard let self else { return }
                let secs = CMTimeGetSeconds(time)
                self.position = secs.isFinite ? secs : 0
                self.progress = self.totalDuration > 0 ? (self.position / self.totalDuration).clamped(to: 0...1) : 0
            }
        }

        avPlayer.playImmediately(atRate: rate)
        isPlaying = true
    }

    /// Seeks to a 0...1 fraction of the clip (used by the waveform scrubber).
    func seek(toFraction f: Double) {
        let frac = Swift.min(Swift.max(f, 0), 1)
        progress = frac
        position = totalDuration * frac
        guard let player, totalDuration > 0 else { return }
        player.seek(to: CMTime(seconds: totalDuration * frac, preferredTimescale: 600))
    }

    /// Cycles playback speed 1× → 1.5× → 2× → 1×, applying it live if playing.
    func cycleRate() {
        switch rate {
        case 1.0: rate = 1.5
        case 1.5: rate = 2.0
        default:  rate = 1.0
        }
        if isPlaying { player?.rate = rate }
    }

    private func didFinishPlaying() {
        isPlaying = false
        progress = 0
        position = 0
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func stop() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
            endObserver = nil
        }
        player?.pause()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isPlaying = false
        progress = 0
        position = 0
    }

    deinit {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
        }
        player?.pause()
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    var positionText: String {
        let s = Int(position)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
