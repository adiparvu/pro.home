import Foundation
import AVFoundation

// MARK: - Real Apple tones, from the device itself
//
// iOS ships its alert tones in /System/Library/Audio/UISounds (the modern
// set lives in New/) and the ringtones in /Library/Ringtones — readable
// on-device system content. We enumerate at runtime instead of hardcoding
// names, so the picker only ever offers tones that actually exist and can
// actually play; if a future iOS locks the directories down, the sections
// simply disappear and the curated classic list remains. These play in-app
// (previews and incoming-message sounds). System notifications outside the
// app keep the default sound — iOS does not let third-party apps attach
// Apple's tones to notifications, and we don't pretend otherwise.

@MainActor
enum SystemToneCatalog {
    struct Tone: Identifiable, Equatable {
        let name: String   // display + stored preference value, e.g. "Reflection"
        let url: URL
        var id: String { name }
    }

    static let ringtones: [Tone] = discover(directory: "/Library/Ringtones", ext: "m4r")

    static let alertTones: [Tone] = {
        var tones = discover(directory: "/System/Library/Audio/UISounds/New", ext: "caf")
        if tones.isEmpty {
            tones = discover(directory: "/System/Library/Audio/UISounds/Modern", ext: "caf")
        }
        return tones
    }()

    private static func discover(directory: String, ext: String) -> [Tone] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return [] }
        return names
            .filter { $0.lowercased().hasSuffix(".\(ext)") }
            .map { file in
                Tone(name: (file as NSString).deletingPathExtension,
                     url: URL(fileURLWithPath: directory).appendingPathComponent(file))
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func tone(named name: String, isCall: Bool) -> Tone? {
        (isCall ? ringtones : alertTones).first { $0.name == name }
    }

    // MARK: Playback — the player is retained until the next play/stop,
    // otherwise the sound cuts off the moment the reference dies.

    private static var player: AVAudioPlayer?

    static func play(_ tone: Tone) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(contentsOf: tone.url)
        player?.play()
    }

    static func stop() {
        player?.stop()
        player = nil
    }
}
