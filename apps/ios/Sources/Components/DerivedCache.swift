import Foundation

/// One-slot memo for values a view derives from observable data.
///
/// A SwiftUI body may re-evaluate dozens of times without the underlying data
/// changing (every keystroke in a bound TextField, every focus change). Any
/// computed property that filters or indexes a large array re-pays that cost
/// on each pass — the chat thread re-filtered the whole conversation ~19
/// times per keystroke. Held in `@State` (so the slot survives re-renders)
/// and keyed on a hash of the *inputs* (typically the service's `revision`
/// counter plus the relevant settings), it recomputes only when an input
/// actually changed.
///
/// Reference semantics are deliberate: mutating the slot during a body pass
/// is legal (it isn't SwiftUI state), and the observable inputs are still
/// read while building the key, so observation registration is preserved.
final class DerivedCache<Value> {
    private var key: Int = .min
    private var stored: Value?

    func value(for key: Int, compute: () -> Value) -> Value {
        if self.key != key || stored == nil {
            stored = compute()
            self.key = key
        }
        return stored!
    }
}
