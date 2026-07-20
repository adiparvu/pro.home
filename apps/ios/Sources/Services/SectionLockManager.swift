import SwiftUI
import Observation
import LocalAuthentication

/// Per-section privacy lock. Lets the user require Face ID / Touch ID / device
/// passcode before opening individually chosen sensitive sections (Documents,
/// Plans & 3D, Finances, Inventory) — independent of the app-wide lock in
/// `AppLockManager`.
///
/// Design:
///   • Which sections are protected is a user choice persisted in UserDefaults.
///   • Authentication uses `.deviceOwnerAuthentication`, so the system offers
///     biometrics first and falls back to the device passcode automatically —
///     this covers both "cod" (passcode) and "Face ID" with no custom PIN to
///     store or leak.
///   • A successful unlock lasts for the current foreground session; every
///     protected section re-locks when the app is backgrounded so a handed-over
///     unlocked phone doesn't expose them.
@MainActor
@Observable
final class SectionLockManager {
    static let shared = SectionLockManager()

    /// Sensitive areas the user can put behind a lock. Raw values are stable
    /// persistence keys — do not rename.
    enum Section: String, CaseIterable, Identifiable {
        case documents
        case plans
        case finances
        case inventory

        var id: String { rawValue }

        var titleKey: LocalizedStringKey {
            switch self {
            case .documents: return "Documents"
            case .plans:     return "Plans & 3D"
            case .finances:  return "Finances"
            case .inventory: return "Inventory"
            }
        }

        var icon: String {
            switch self {
            case .documents: return "doc.text.fill"
            case .plans:     return "cube.transparent.fill"
            case .finances:  return "banknote.fill"
            case .inventory: return "shippingbox.fill"
            }
        }

        var color: Color {
            switch self {
            case .documents: return .orange
            case .plans:     return .purple
            case .finances:  return .brandSuccess
            case .inventory: return .indigo
            }
        }
    }

    private let storeKey = "prvio.protectedSections"

    /// Raw values of the sections the user has chosen to protect.
    private(set) var protectedSections: Set<String>

    /// Sections unlocked during this foreground session.
    private var unlockedThisSession: Set<String> = []

    private init() {
        protectedSections = Set(UserDefaults.standard.stringArray(forKey: storeKey) ?? [])
        // Re-lock everything whenever the app leaves the foreground so an
        // already-unlocked section can't be seen on a borrowed device.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.lockAll() }
        }
    }

    // MARK: - Configuration

    func isProtected(_ section: Section) -> Bool {
        protectedSections.contains(section.rawValue)
    }

    func setProtected(_ section: Section, _ on: Bool) {
        if on {
            protectedSections.insert(section.rawValue)
        } else {
            protectedSections.remove(section.rawValue)
            unlockedThisSession.remove(section.rawValue)
        }
        UserDefaults.standard.set(Array(protectedSections), forKey: storeKey)
    }

    // MARK: - Session state

    /// True when a section is protected and hasn't been unlocked this session —
    /// i.e. the gate must challenge before revealing content.
    func needsAuth(_ section: Section) -> Bool {
        isProtected(section) && !unlockedThisSession.contains(section.rawValue)
    }

    /// Prompts Face ID / Touch ID / device passcode for one section.
    /// Returns whether the user authenticated successfully.
    func unlock(_ section: Section) async -> Bool {
        let ctx = LAContext()
        ctx.localizedFallbackTitle = String(localized: "Enter passcode")

        var err: NSError?
        // If the device has no passcode set there's nothing to evaluate — fail
        // open rather than trapping the user out of their own data.
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            unlockedThisSession.insert(section.rawValue)
            return true
        }

        do {
            let reason = String(localized: "Unlock to view this section")
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if ok { unlockedThisSession.insert(section.rawValue) }
            return ok
        } catch {
            return false
        }
    }

    /// Re-lock a single section (e.g. after the user taps "Lock now").
    func relock(_ section: Section) {
        unlockedThisSession.remove(section.rawValue)
    }

    /// Re-lock every protected section — called on backgrounding.
    func lockAll() {
        unlockedThisSession.removeAll()
    }
}
