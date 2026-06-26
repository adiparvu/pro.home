import SwiftUI
import AVFoundation
import CoreMedia

// MARK: - Audio Recorder

@MainActor
final class ChatAudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var duration: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
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
        // Capture both so we don't reference self in the async block.
        let t = timer
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
    @ObservedObject var recorder: ChatAudioRecorder
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
                .padding(.horizontal, 12)
                .transition(.opacity.combined(with: .scale))
            }

            Image(systemName: recorder.isRecording ? "waveform" : "mic.fill")
                .font(.system(size: 16, weight: .semibold))
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
    let url: URL?
    let isOwn: Bool

    @StateObject private var player = AudioPlayer()
    @State private var loadedDuration: TimeInterval = 0

    var body: some View {
        HStack(spacing: 10) {
            Button {
                if player.isPlaying { player.pause() }
                else if let url { player.play(url: url) }
            } label: {
                ZStack {
                    Circle()
                        .fill(isOwn ? Color.white.opacity(0.25) : Color.accentColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isOwn ? .white : Color.accentColor)
                }
            }
            .buttonStyle(.plain)
            .disabled(url == nil || loadedDuration == 0)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(isOwn ? Color.white.opacity(0.25) : Color.primary.opacity(0.12))
                        .frame(height: 3)
                    Capsule()
                        .fill(isOwn ? Color.white : Color.accentColor)
                        .frame(width: geo.size.width * player.progress, height: 3)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 20)

            Text(player.isPlaying ? player.positionText : durationText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(isOwn ? Color.white.opacity(0.75) : Color.primary.opacity(0.5))
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            isOwn ? Color.blue.opacity(0.75) : Color.primary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .frame(minWidth: 180, maxWidth: 240)
        .task {
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

    private var durationText: String {
        guard loadedDuration > 0 else { return "-:--" }
        let s = Int(loadedDuration)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Audio Player (AVPlayer — supports remote HTTPS URLs)
// AVAudioPlayer only works with local files. All chat audio lives in Supabase
// Storage (HTTPS), so AVPlayer is required here.

@MainActor
final class AudioPlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var progress: Double = 0
    @Published var position: TimeInterval = 0
    var totalDuration: TimeInterval = 0

    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var endObserver: NSObjectProtocol?

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
            self?.didFinishPlaying()
        }

        let interval = CMTime(seconds: 0.05, preferredTimescale: 600)
        timeObserverToken = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let secs = CMTimeGetSeconds(time)
            self.position = secs.isFinite ? secs : 0
            self.progress = self.totalDuration > 0 ? (self.position / self.totalDuration).clamped(to: 0...1) : 0
        }

        avPlayer.play()
        isPlaying = true
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
