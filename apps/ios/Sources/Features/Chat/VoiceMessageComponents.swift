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
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
        try? session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        recorder = try? AVAudioRecorder(url: url, settings: settings)
        recorder?.delegate = self
        recorder?.record()
        recordingURL = url
        isRecording = true
        duration = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.duration += 0.1
            }
        }
    }

    func stop() -> URL? {
        timer?.invalidate(); timer = nil
        recorder?.stop()
        recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false
        let url = recordingURL
        recordingURL = nil
        duration = 0
        return url
    }

    deinit {
        timer?.invalidate()
        recorder?.stop()
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
                if secs.isFinite && secs > 0 { loadedDuration = secs }
            }
        }
        .onDisappear { player.stop() }
    }

    private var durationText: String {
        let s = Int(loadedDuration)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

@MainActor
final class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    @Published var progress: Double = 0
    @Published var position: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func play(url: URL) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        player?.play()
        isPlaying = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let p = self.player else { return }
                self.position = p.currentTime
                self.progress = p.duration > 0 ? p.currentTime / p.duration : 0
            }
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isPlaying = false
        progress = 0
        position = 0
    }

    nonisolated func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully _: Bool) {
        Task { @MainActor in
            isPlaying = false
            progress = 0
            position = 0
            timer?.invalidate()
            timer = nil
        }
    }

    deinit {
        timer?.invalidate()
        player?.stop()
    }

    var positionText: String {
        let s = Int(position)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
