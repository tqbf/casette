import Foundation

/// One kernel status update from `SessionController` to the UI: the state
/// machine's current state plus, when something is wrong, an honest
/// user-facing explanation (boot failure, crash, forced stop) that drives the
/// recovery banner.
struct KernelStatus: Equatable, Sendable {
    var state: KernelState
    /// Non-nil only when the kernel is unavailable for a *reason* the user
    /// should see (no Sage found, worker crashed, force-stopped). Cleared by
    /// a successful connect/restart.
    var issue: String?
}
