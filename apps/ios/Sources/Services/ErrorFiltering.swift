import Foundation

// MARK: - Cancellation is not an error
//
// A pull-to-refresh released early, a `task(id:)` restart, navigating away
// mid-load — Swift concurrency cancels the in-flight request and the throw
// surfaces as `CancellationError` (or URLSession's `.cancelled`). Services
// used to record it like a genuine failure, and pages alerted the user with
// "Swift.CancellationError" (IMG_8656). One shared gate for every service's
// catch block: genuine failures record their message, cancellation records
// nothing.

extension Error {
    /// True for task-cancellation artifacts — never user-facing failures.
    var isTaskCancellation: Bool {
        if self is CancellationError { return true }
        if let urlError = self as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    /// What a service should record on catch: nil for cancellation
    /// artifacts, the localized description for genuine failures.
    var recordableDescription: String? {
        isTaskCancellation ? nil : localizedDescription
    }
}
