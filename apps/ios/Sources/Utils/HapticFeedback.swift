import UIKit
import AudioToolbox

// MARK: - Message sounds

/// The sounds Messages itself plays. SystemSoundID 1004 is the system
/// "message sent" swoosh — the exact sound iMessage uses — and, like
/// iMessage, it respects the ring/silent switch.
enum MessageSounds {
    static func sent() {
        AudioServicesPlaySystemSound(1004)
    }
}

enum HapticFeedback {
    private static var enabled: Bool {
        UserDefaults.standard.object(forKey: "prvio.hapticOn") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "prvio.hapticOn")
    }

    // Retained generators — recreating + firing a generator inline (the old
    // approach) often produces a weak or no haptic. Keeping them alive and
    // calling prepare() right before triggering makes feedback reliable.
    private static let impactLight  = UIImpactFeedbackGenerator(style: .light)
    private static let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private static let impactHeavy  = UIImpactFeedbackGenerator(style: .heavy)
    private static let notification = UINotificationFeedbackGenerator()
    private static let selectionGen = UISelectionFeedbackGenerator()

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        guard enabled else { return }
        run {
            let gen: UIImpactFeedbackGenerator
            switch style {
            case .light: gen = impactLight
            case .heavy: gen = impactHeavy
            case .medium: gen = impactMedium
            default: gen = UIImpactFeedbackGenerator(style: style)
            }
            gen.prepare()
            gen.impactOccurred()
        }
    }

    static func success() { notify(.success) }
    static func warning() { notify(.warning) }
    static func error()   { notify(.error) }

    static func selection() {
        guard enabled else { return }
        run {
            selectionGen.prepare()
            selectionGen.selectionChanged()
        }
    }

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard enabled else { return }
        run {
            notification.prepare()
            notification.notificationOccurred(type)
        }
    }

    /// Feedback generators must be used on the main thread.
    private static func run(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }
}
