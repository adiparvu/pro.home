import SwiftUI
import LocalAuthentication

// MARK: - Per-item privacy lock
//
// Lets the user lock INDIVIDUAL items (a document, a plan, …) behind
// Face ID / Touch ID / device passcode, from each item's context menu —
// complementing SectionLockManager, which locks whole sections.
//
// Design:
//   • Which items are locked is stored per feature domain in UserDefaults —
//     a privacy affordance (like favorites), not server-side security; the
//     real access control remains Supabase RLS.
//   • Locking is free; unlocking (removing the lock) and opening a locked
//     item both require authentication.
//   • Authentication uses .deviceOwnerAuthentication, so biometrics fall
//     back to the device passcode natively ("cod/Face ID").

enum ItemLockStore {
    /// Feature domains with individually lockable items. Raw values are
    /// stable persistence keys — do not rename.
    enum Domain: String {
        case documents
        case plans
    }

    private static func key(_ domain: Domain) -> String { "prvio.lockedItems.\(domain.rawValue)" }

    static func ids(_ domain: Domain) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key(domain)) ?? [])
    }

    static func isLocked(_ id: String, in domain: Domain) -> Bool {
        ids(domain).contains(id)
    }

    static func setLocked(_ id: String, in domain: Domain, _ locked: Bool) {
        var set = ids(domain)
        if locked { set.insert(id) } else { set.remove(id) }
        UserDefaults.standard.set(Array(set), forKey: key(domain))
    }
}

/// Context-menu preview shown instead of an item's real content when it's
/// locked — the content must never leak through the long-press peek.
struct LockedItemPreview: View {
    let name: String

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            ZStack {
                Circle().fill(Color.teal.opacity(0.15)).frame(width: 72, height: 72)
                Image(systemName: "lock.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.teal)
            }
            Text(name)
                .font(AppFont.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text("Locked — Face ID required")
                .font(AppFont.footnote)
                .foregroundStyle(Color.secondaryTextColor)
        }
        .padding(40)
    }
}

enum PrivacyAuth {
    /// Prompts Face ID / Touch ID / device passcode. Fails open when the
    /// device has no passcode at all (nothing to evaluate — don't trap the
    /// user out of their own data).
    static func authenticate(reason: String = String(localized: "Unlock to view this item")) async -> Bool {
        let ctx = LAContext()
        ctx.localizedFallbackTitle = String(localized: "Enter passcode")
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return true }
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}
