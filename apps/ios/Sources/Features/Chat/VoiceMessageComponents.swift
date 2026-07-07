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
    /// Live mic levels (0…1), one sample per timer tick — drives the
    /// iMessage-style waveform that scrolls while recording.
    private(set) var levels: [Float] = []

    /// A finished recording awaiting review — play it back, discard it, or
    /// send it. Mirrors iMessage: stop never sends, the arrow does.
    struct Preview: Equatable {
        let url: URL
        let duration: TimeInterval
        let levels: [Float]

        var durationText: String {
            let s = Int(duration)
            return String(format: "%d:%02d", s / 60, s % 60)
        }
    }
    private(set) var preview: Preview?

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
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
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
        recorder?.isMeteringEnabled = true
        guard recorder?.record() == true else {
            recorder = nil
            try? session.setActive(false)
            return
        }
        recordingURL = url
        isRecording = true
        duration = 0
        levels = []
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func tick() {
        duration += 0.05
        guard let recorder else { return }
        recorder.updateMeters()
        // -50 dB…0 dB → 0…1, the useful speech range for a visual meter.
        let db = recorder.averagePower(forChannel: 0)
        levels.append(max(0, min(1, (db + 50) / 50)))
    }

    /// Stops recording and parks the clip for review (play / discard / send).
    /// Clips under 0.5 s are dropped — AVAudioRecorder writes a valid M4A
    /// container but AVURLAsset reads 0 duration for very short clips,
    /// crashing AVPlayer on playback.
    func finishRecording() {
        guard isRecording else { return }
        let url = recordingURL
        let capturedDuration = duration
        let capturedLevels = levels
        tearDown()
        guard let url, capturedDuration >= 0.5 else {
            if let url { try? FileManager.default.removeItem(at: url) }
            return
        }
        preview = Preview(url: url, duration: capturedDuration, levels: capturedLevels)
    }

    /// Stops recording and deletes the clip — nothing to review.
    func cancelRecording() {
        let url = recordingURL
        tearDown()
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    /// Discards a reviewed clip (the X button).
    func discardPreview() {
        if let preview { try? FileManager.default.removeItem(at: preview.url) }
        preview = nil
    }

    /// Hands the reviewed clip to the caller for sending and clears the state.
    func takePreview() -> Preview? {
        defer { preview = nil }
        return preview
    }

    private func tearDown() {
        timer?.invalidate(); timer = nil
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false
        recordingURL = nil
        duration = 0
        levels = []
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

// MARK: - Recording pill (iMessage: live red waveform · red timer · red stop)

/// The compose pill while recording — exactly iMessage: the whole capsule
/// becomes the recording surface, a live waveform scrolls in from the right,
/// the elapsed time reads in red, and the red stop button parks the clip for
/// review. Shared by the group chat and DM input bars.
struct VoiceRecordingPill: View {
    var recorder: ChatAudioRecorder
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            LiveVoiceWaveform(levels: recorder.levels)
                .frame(maxWidth: .infinity)
                .padding(.leading, AppSpacing.md)

            Text(recorder.durationText)
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.red)
                .contentTransition(.numericText())

            Button {
                onStop()
                HapticFeedback.impact(.medium)
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.18))
                        .frame(width: 40, height: 40)
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(Color.red)
                        .frame(width: 14, height: 14)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Stop recording"))
        }
        .padding(.trailing, 6)
        .frame(height: 52)
        .mediaGlass(in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityValue(Text(verbatim: recorder.durationText))
    }
}

// MARK: - Review row (iMessage: ✕ · play · waveform · duration chip · send)

/// The post-recording review row — exactly iMessage: an ✕ in a glass circle
/// where the + button sat, then a tall pill holding play/pause, the static
/// waveform of the clip, the "+ 0:09" duration chip, and the send arrow.
struct VoiceReviewRow: View {
    let preview: ChatAudioRecorder.Preview
    var isSending: Bool = false
    let onDiscard: () -> Void
    let onSend: () -> Void

    @State private var player = AudioPlayer()

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.sm) {
            Button {
                player.stop()
                onDiscard()
                HapticFeedback.impact(.light)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .mediaGlass(in: Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Discard recording"))

            HStack(spacing: 10) {
                Button {
                    if player.isPlaying {
                        player.pause()
                    } else if player.canResume {
                        player.resume()
                    } else {
                        player.totalDuration = preview.duration
                        player.play(url: preview.url)
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 36, height: 36)
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play voice message")

                StaticVoiceWaveform(levels: preview.levels, progress: player.progress)
                    .frame(maxWidth: .infinity)

                Text(verbatim: "+ \(preview.durationText)")
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.07), in: Capsule())
                    .accessibilityLabel(Text("Voice message"))
                    .accessibilityValue(Text(verbatim: preview.durationText))

                Button {
                    player.stop()
                    onSend()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 40, height: 40)
                        if isSending {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isSending)
                .accessibilityLabel(Text("Send"))
            }
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .frame(height: 52)
            .mediaGlass(in: Capsule())
        }
        .onDisappear { player.stop() }
    }
}

// MARK: - Waveform canvases

/// Live meter dashes scrolling in from the right while recording — pale red
/// when quiet, solid red and taller with speech, like iMessage.
private struct LiveVoiceWaveform: View {
    let levels: [Float]

    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 5              // 2.5pt dash + 2.5pt gap
            let capacity = max(1, Int(size.width / step))
            // Grows from the left while filling, then scrolls — like iMessage.
            let visible = levels.suffix(capacity)
            let midY = size.height / 2
            var x = step / 2
            for level in visible {
                let l = CGFloat(level)
                let h = max(4, l * size.height)
                let rect = CGRect(x: x - 1.25, y: midY - h / 2, width: 2.5, height: h)
                context.fill(Capsule().path(in: rect),
                             with: .color(.red.opacity(0.3 + Double(min(1, l * 1.8)) * 0.7)))
                x += step
            }
        }
        .frame(height: 26)
        .accessibilityHidden(true)
    }
}

/// The finished clip's waveform in the review pill, darkening with playback
/// progress.
private struct StaticVoiceWaveform: View {
    let levels: [Float]
    let progress: Double

    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 5
            let barCount = max(1, Int(size.width / step))
            let bars = Self.downsample(levels, to: barCount)
            let midY = size.height / 2
            let played = Int((Double(barCount) * progress).rounded())
            for (i, level) in bars.enumerated() {
                let h = max(4, CGFloat(level) * size.height)
                let rect = CGRect(x: CGFloat(i) * step + 1.25, y: midY - h / 2,
                                  width: 2.5, height: h)
                context.fill(Capsule().path(in: rect),
                             with: .color(.primary.opacity(i < played ? 0.85 : 0.3)))
            }
        }
        .frame(height: 26)
        .accessibilityHidden(true)
    }

    /// Averages the recorded meter samples into exactly `count` bars.
    static func downsample(_ samples: [Float], to count: Int) -> [Float] {
        guard !samples.isEmpty, count > 0 else { return Array(repeating: 0.3, count: max(count, 1)) }
        return (0..<count).map { i in
            let lo = i * samples.count / count
            let hi = max(lo + 1, (i + 1) * samples.count / count)
            let slice = samples[lo..<min(hi, samples.count)]
            return slice.isEmpty ? 0 : slice.reduce(0, +) / Float(slice.count)
        }
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
    /// Draw the group tail — true only on the last bubble of a same-sender run.
    var hasTail: Bool = true

    enum AudioTick { case none, sent, delivered, read }

    @State private var player = AudioPlayer()
    @State private var loadedDuration: TimeInterval = 0
    /// Signed URL resolved from `audioValue` (nil while resolving).
    @State private var url: URL?

    /// Readable foreground over the themed bubble fill.
    private var onBubble: Color { bubbleColor.readableText }
    private var subFg: Color { isOwn ? onBubble.opacity(0.7) : Color.primary.opacity(AppOpacity.mediumText) }

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
            in: ChatBubbleShape(isOwn: isOwn, hasTail: hasTail)
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
                    StorageImage(url: avatarURL) { phase in
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
                .background(Circle().fill(isOwn ? bubbleColor.readableText : .white))
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
            else if player.canResume { player.resume() }
            else if let url { player.play(url: url) }
        } label: {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(isOwn ? onBubble : Color.accentColor)
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
                VoiceWaveform(progress: player.progress, isOwn: isOwn, onBubble: onBubble, seed: Self.seed(for: url))
                Circle()
                    .fill(isOwn ? onBubble : Color.accentColor)
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
                        .foregroundStyle(isOwn ? onBubble : Color.accentColor)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background((isOwn ? onBubble.opacity(0.2) : Color.accentColor.opacity(0.12)), in: Capsule())
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
        case .none:    EmptyView()
        case .sent:      MessageTick(status: .sent, color: subFg, readColor: isOwn ? onBubble : .blue, size: 10)
        case .delivered: MessageTick(status: .delivered, color: subFg, readColor: isOwn ? onBubble : .blue, size: 10)
        case .read:      MessageTick(status: .read, color: subFg, readColor: isOwn ? onBubble : .blue, size: 10)
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
    /// Readable colour over the themed bubble fill (white on dark, black on light).
    var onBubble: Color = .white
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
            return isOwn ? onBubble : Color.accentColor
        }
        return isOwn ? onBubble.opacity(0.35) : Color.primary.opacity(0.2)
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
        // Rewind so a subsequent resume() replays instead of idling at the end.
        player?.seek(to: .zero)
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    /// A paused item is still loaded and can pick up where it left off.
    var canResume: Bool { player != nil }

    /// Continues a paused clip from its current position.
    func resume() {
        guard let player else { return }
        player.playImmediately(atRate: rate)
        isPlaying = true
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
