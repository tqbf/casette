import Foundation

/// The kernel lifecycle as the app sees it — the V0.2 eight-state machine
/// (idle / running / completed / error / interrupted / timed_out / crashed /
/// restarting, proven in v0/02-lifecycle and re-proven from Swift in v0/09),
/// plus `.notConnected` for the app-side reality that no kernel exists yet
/// (before V1.3 wires `SageKernel` in, and later before first boot / after
/// shutdown).
///
/// Live state, deliberately NOT `Codable`: a kernel's state dies with the
/// process and is never part of the persisted session.
enum KernelState: String, Equatable, Sendable {
    /// No Sage worker process exists. The only state V1.2 ever shows; V1.3
    /// drives the rest of the machine.
    case notConnected = "not_connected"
    case idle
    case running
    /// Last evaluation completed normally; worker is ready for more.
    case completed
    /// Last evaluation raised; worker survived and is ready for more.
    case error
    /// Last evaluation was interrupted (SIGINT); worker survived.
    case interrupted
    /// Last evaluation timed out and the SIGINT resolved it — the worker
    /// survived and is ready for more. (When the escalation has to hard-kill
    /// instead, the worker is gone and the state is `.crashed`.)
    case timedOut = "timed_out"
    /// The worker process died — crashed on its own, or force-stopped by the
    /// escalation policy. Only `restart` recovers from this.
    case crashed
    case restarting

    /// Is there a live worker process at all? Drives the honest tape message
    /// for incomplete rows ("Not evaluated — Sage isn't connected yet" vs
    /// "Evaluating…").
    var isConnected: Bool { self != .notConnected }

    /// Can the app hand the kernel a new evaluation right now? The terminal
    /// per-eval states (completed/error/interrupted/timedOut) leave the worker
    /// alive and ready, exactly like idle (V0.2: the worker survives an error,
    /// an interrupt, and a timeout that SIGINT resolved).
    var canAcceptWork: Bool {
        switch self {
        case .idle, .completed, .error, .interrupted, .timedOut: true
        case .notConnected, .running, .crashed, .restarting: false
        }
    }
}
