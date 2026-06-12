import Foundation

/// The process-level seam under `SessionController`: something that can spawn
/// a Sage worker, speak JSONL to it, and kill it. `SageKernel` is the real
/// implementation (posix_spawn + process-group control); tests drive the
/// controller's state machine, routing, and escalation policy through a fake.
///
/// Threading contract (the PROBLEMS.md single-consumer rule): the
/// `SessionController` actor is the SOLE consumer of `dequeue` — interrupt and
/// kill only *signal*. All methods are synchronous and non-blocking; waiting
/// is the controller's job (poll + `Task.sleep`), so the actor stays
/// responsive to interrupt/restart while an eval is in flight.
protocol KernelTransport: AnyObject, Sendable {
    /// Registers a callback fired exactly once when the worker's stdout
    /// closes (death or shutdown). Must be set BEFORE `spawn()` so a
    /// fast-failing boot is never missed.
    func setEOFHandler(_ handler: @escaping @Sendable () -> Void)

    /// True once the worker's stdout has closed.
    var isAtEOF: Bool { get }

    /// Launches the worker. Returns immediately; the ready banner arrives on
    /// the queue (the controller awaits it).
    func spawn() throws

    /// Records the worker's REAL pid from the ready banner — the SIGINT
    /// target (NOT the `sage` bash-wrapper pid; PROBLEMS.md).
    func noteRealPID(_ pid: Int32)

    /// Sends one JSONL request object on the worker's stdin.
    func send(_ object: [String: Any]) throws

    /// Non-blocking: removes and returns the first queued object matching
    /// `predicate`, discarding non-matching objects ahead of it (stray
    /// protocol lines). Returns nil when nothing matches yet.
    func dequeue(where predicate: ([String: Any]) -> Bool) -> [String: Any]?

    /// SIGINT to the worker's real pid (cysignals → prompt KeyboardInterrupt;
    /// never guaranteed — the controller escalates).
    func interrupt()

    /// SIGKILL to the whole process group (wrapper + worker together — the
    /// orphan-proof teardown), then reaps.
    func hardKill()

    /// Best-effort: is the spawned (wrapper) process still alive?
    func isAlive() -> Bool

    /// The Sage binary this transport runs, when known. Real kernels report
    /// it (V1.10 fills the session header's `sageVersion` from it and the
    /// Doctor shows it); fakes default to nil via the extension below.
    var sageBinaryPath: String? { get }
}

extension KernelTransport {
    var sageBinaryPath: String? { nil }
}
