import Foundation
import os

/// Owns the Sage kernel and drives the V0.2 eight-state machine for the app:
/// boot (with discovery), request/response routing by ID, eval timeout with
/// SIGINT → hard-kill escalation, interrupt, restart-to-fresh-namespace, and
/// crash detection (mid-eval and idle). The Swift port of v0/02's
/// `controller.py`, running the kernel I/O off the main actor.
///
/// Threading model (the load-bearing rules, from PROBLEMS.md):
///   * The actor serializes all commands; `evaluate` is the SOLE consumer of
///     the wire queue. Interrupt/timeout only *signal* (set a flag / send
///     SIGINT) — they never read the queue, so a response can never be stolen
///     from the waiter.
///   * Waiting is poll + `Task.sleep` (never a blocking wait), so the actor
///     stays responsive: `interruptCurrent()` and `restart()` land while an
///     eval is in flight.
///   * Each worker generation is one fresh `KernelTransport` with its own
///     queue and EOF callback, guarded by a generation counter — a stale
///     generation's EOF can never make a fresh worker look crashed-on-boot
///     (the V0.2 restart race).
///
/// UI integration: state changes stream over `statusUpdates` (single
/// consumer: `ShellModel`); evaluation outcomes return as `Evaluation` values
/// the model applies to its pending row.
actor SessionController {
    struct Configuration: Sendable {
        /// Eval deadline before the SIGINT → hard-kill escalation begins.
        var evalTimeout: Duration = .seconds(120)
        /// How long after SIGINT the worker gets to acknowledge before the
        /// process group is hard-killed (V0.2: SIGINT is never guaranteed).
        var interruptGrace: Duration = .seconds(3)
        /// How long boot may take before the spawn is killed and reported
        /// (Sage boots in ~3s here, but cold caches can be slow).
        var readyTimeout: Duration = .seconds(120)
        /// Timeout for cheap metadata ops (`symbols`).
        var metadataTimeout: Duration = .seconds(10)
        /// Poll interval for the response/escalation loop (controller.py
        /// used 50ms; responsiveness, not throughput, is what matters).
        var pollInterval: Duration = .milliseconds(50)

        static let standard = Configuration()
    }

    /// Builds one worker-process transport per kernel generation. The default
    /// discovers Sage (stored config → well-known paths → PATH) and the
    /// bundled worker script, throwing a `KernelSetupError` with a
    /// user-facing message when either is missing.
    typealias TransportFactory = @Sendable () throws -> any KernelTransport

    /// Kernel state + issue updates for the UI. Single consumer (ShellModel).
    nonisolated let statusUpdates: AsyncStream<KernelStatus>

    private(set) var state: KernelState = .notConnected
    private(set) var issue: String?
    /// The Sage binary the CURRENT worker generation runs (from the
    /// transport), or nil with no live worker / a fake transport. V1.10 uses
    /// it to fill the session header's `sageVersion` after boot.
    private(set) var currentSagePath: String?

    private let configuration: Configuration
    private let makeTransport: TransportFactory
    private let statusContinuation: AsyncStream<KernelStatus>.Continuation
    private let logger = Logger(subsystem: "org.sockpuppet.casette", category: "kernel")

    private var transport: (any KernelTransport)?
    /// Bumped whenever the current worker generation ends (restart, kill,
    /// crash). In-flight loops and EOF callbacks compare against it.
    private var generation = 0
    private var requestCounter = 0
    /// True while a request/response exchange owns the wire queue.
    private var requestInFlight = false
    /// Tripped by `interruptCurrent()`; the eval loop does the SIGINT +
    /// escalation (the "cancel only signals" rule).
    private var cancelRequested = false

    init(
        configuration: Configuration = .standard,
        transportFactory: @escaping TransportFactory = SessionController.discoveringTransportFactory
    ) {
        self.configuration = configuration
        self.makeTransport = transportFactory
        (statusUpdates, statusContinuation) = AsyncStream.makeStream(of: KernelStatus.self)
    }

    /// The real factory: V0.9 discovery (stored config → Homebrew →
    /// /usr/local → SageMath*.app → conda → PATH) + the bundled worker.py +
    /// the worker stderr log.
    static let discoveringTransportFactory: TransportFactory = {
        let store = SageConfigStore()
        let discovery = SageDiscovery()
        let result = discovery.discover(storedPath: store.storedPath())
        guard let sage = result.selected else {
            throw KernelSetupError.sageNotFound(searched: result.candidates.map(\.path))
        }
        let worker = try WorkerScriptLocator.locate()
        return SageKernel(
            sagePath: sage.path,
            workerPath: worker,
            stderrLogURL: KernelLog.prepareWorkerLog())
    }

    // MARK: - Lifecycle

    /// Boots the first worker. Idempotent while a worker is up.
    func connect() async {
        guard state == .notConnected || state == .crashed else { return }
        await boot()
    }

    /// Tears down the current worker (if any) and boots a fresh one with a
    /// brand-new namespace — the INTENTIONAL state reset. An in-flight eval
    /// notices the generation change and finishes as interrupted.
    func restart() async {
        guard state != .restarting else { return }
        logger.notice("restart requested (state \(self.state.rawValue, privacy: .public))")
        endGeneration()
        await boot()
    }

    /// Kills the worker and goes quiet (tests / teardown).
    func shutdown() {
        endGeneration()
        setStatus(.notConnected, issue: nil)
    }

    /// Asks the in-flight eval to stop. Non-blocking: the eval loop sends the
    /// SIGINT and escalates to a hard kill if it goes unacknowledged.
    func interruptCurrent() {
        guard state == .running else { return }
        logger.notice("interrupt requested")
        cancelRequested = true
    }

    // MARK: - Evaluation

    /// Evaluates raw Sage in the persistent namespace and returns the row
    /// outcome. Enforces the timeout with SIGINT → hard-kill escalation, and
    /// maps the worker envelope through `EnvelopeMapping` (the frozen
    /// wire → model boundary).
    ///
    /// V0.8 request fields (WORKER-PROTOCOL.md):
    ///   * `numeric: true` — force-numeric for THIS request only: the primary
    ///     result becomes its decimal approximation and the exact form is
    ///     preserved in `exact_value`. Display-only — the worker guarantees
    ///     the namespace is never mutated (`y = 1/3` stays a Rational).
    ///   * `precisionDigits` — a per-request precision override (decimal
    ///     digits) for `approx`/the numeric primary. Does not change the
    ///     session default (that's the `config` op — `configure(precisionDigits:)`).
    func evaluate(
        _ sage: String,
        numeric: Bool = false,
        precisionDigits: Int? = nil
    ) async -> Evaluation {
        // Boot grace: if the kernel is still coming up, wait for it to
        // resolve (boot always ends in idle or notConnected).
        await waitWhileBootingOrBusy()
        guard state.canAcceptWork, let kernel = transport else {
            return Evaluation(
                status: .error,
                result: syntheticEnvelope(
                    type: "Sage not running",
                    message: issue ?? "Sage isn't running, so this input wasn't evaluated."),
                duration: nil)
        }

        let myGeneration = generation
        let requestID = nextRequestID(prefix: "eval")
        requestInFlight = true
        defer { requestInFlight = false }
        cancelRequested = false
        setStatus(.running, issue: nil)
        let clock = ContinuousClock()
        let started = clock.now
        let deadline = started + configuration.evalTimeout

        var request: [String: Any] = ["id": requestID, "code": sage]
        if numeric {
            request["numeric"] = true
        }
        if let precisionDigits {
            request["precision_digits"] = precisionDigits
        }
        do {
            try kernel.send(request)
        } catch {
            return failGeneration(
                myGeneration,
                kernel: kernel,
                issue: "Sage crashed. Restart Sage to continue (variables will be reset).",
                evaluation: Evaluation(
                    status: .error,
                    result: syntheticEnvelope(
                        type: "Sage crashed",
                        message: "Couldn't send this input to Sage — the worker is gone."),
                    duration: nil))
        }

        var sigintSentAt: ContinuousClock.Instant?
        var cause: EscalationCause?

        while true {
            // 0) Preempted by restart? Another generation owns the state now.
            if generation != myGeneration {
                return Evaluation(
                    status: .interrupted,
                    result: syntheticEnvelope(
                        type: "Interrupted",
                        message: "Sage was restarted before this evaluation finished."),
                    duration: elapsed(since: started, clock: clock))
            }

            // 1) Response?
            if let response = kernel.dequeue(where: { ($0["id"] as? String) == requestID }) {
                return finish(
                    response,
                    cause: cause,
                    duration: elapsed(since: started, clock: clock),
                    generation: myGeneration)
            }

            // 2) Crash? (EOF with no response — unless WE killed it below.)
            if kernel.isAtEOF {
                logger.error("worker died mid-eval (EOF)")
                return failGeneration(
                    myGeneration,
                    kernel: kernel,
                    issue: "Sage crashed during an evaluation. Restart Sage to continue (variables will be reset).",
                    evaluation: Evaluation(
                        status: .error,
                        result: syntheticEnvelope(
                            type: "Sage crashed",
                            message: "The Sage process died while evaluating this input."),
                        duration: elapsed(since: started, clock: clock)))
            }

            let now = clock.now

            // 3) Escalation triggers: explicit cancel, or the deadline.
            if cause == nil, cancelRequested {
                cause = .cancel
                kernel.interrupt()
                sigintSentAt = now
                logger.notice("SIGINT sent (cancel)")
            } else if cause == nil, now >= deadline {
                cause = .timeout
                kernel.interrupt()
                sigintSentAt = now
                logger.notice("SIGINT sent (timeout after \(self.configuration.evalTimeout.description, privacy: .public))")
            }

            // 4) SIGINT ignored past the grace window → brutal kill (V0.2:
            // SIGINT is never guaranteed; the escalation path is mandatory).
            if let sentAt = sigintSentAt, now - sentAt >= configuration.interruptGrace {
                logger.error("SIGINT unacknowledged after grace — hard-killing the worker group")
                let detail: (issue: String, message: String) =
                    if cause == .timeout {
                        (
                            "The evaluation hit its time limit and didn't respond to an interrupt, so Sage was force-stopped. Restart Sage to continue (variables will be reset).",
                            "Timed out: Sage didn't respond to an interrupt and was force-stopped."
                        )
                    } else {
                        (
                            "The evaluation didn't respond to an interrupt, so Sage was force-stopped. Restart Sage to continue (variables will be reset).",
                            "Stopped: Sage didn't respond to the interrupt and was force-stopped."
                        )
                    }
                return failGeneration(
                    myGeneration,
                    kernel: kernel,
                    issue: detail.issue,
                    evaluation: Evaluation(
                        status: .interrupted,
                        result: syntheticEnvelope(type: "Interrupted", message: detail.message),
                        duration: elapsed(since: started, clock: clock)))
            }

            try? await Task.sleep(for: configuration.pollInterval)
        }
    }

    /// Fetches the live user symbol table (the V0.6 `symbols` op — cheap
    /// enough to refresh after every eval). Returns nil if the kernel is
    /// unavailable or busy.
    func fetchSymbols() async -> SymbolSnapshot? {
        guard state.canAcceptWork, let kernel = transport, !requestInFlight else { return nil }
        let requestID = nextRequestID(prefix: "symbols")
        requestInFlight = true
        defer { requestInFlight = false }
        guard (try? kernel.send(["id": requestID, "op": "symbols"])) != nil else { return nil }

        let clock = ContinuousClock()
        let deadline = clock.now + configuration.metadataTimeout
        let myGeneration = generation
        while clock.now < deadline, generation == myGeneration, !kernel.isAtEOF {
            if let response = kernel.dequeue(where: { ($0["id"] as? String) == requestID }) {
                return SymbolSnapshot(workerResponse: response)
            }
            try? await Task.sleep(for: configuration.pollInterval)
        }
        return nil
    }

    /// Sets the worker's session-level approximation precision (the V0.8
    /// `config` op — `precision_digits`, worker default 10). Applies to every
    /// subsequent eval's `approx` until changed; the worker holds it as
    /// session state, so the model re-applies it after boot/restart (like the
    /// boot prelude). Returns whether the worker accepted the setting (it
    /// rejects non-positive values and leaves the session unchanged).
    func configure(precisionDigits: Int) async -> Bool {
        await waitWhileBootingOrBusy()
        guard state.canAcceptWork, let kernel = transport else { return false }
        let requestID = nextRequestID(prefix: "config")
        requestInFlight = true
        defer { requestInFlight = false }
        guard (try? kernel.send([
            "id": requestID, "op": "config", "precision_digits": precisionDigits,
        ])) != nil else { return false }

        let clock = ContinuousClock()
        let deadline = clock.now + configuration.metadataTimeout
        let myGeneration = generation
        while clock.now < deadline, generation == myGeneration, !kernel.isAtEOF {
            if let response = kernel.dequeue(where: { ($0["id"] as? String) == requestID }) {
                return response["ok"] as? Bool ?? false
            }
            try? await Task.sleep(for: configuration.pollInterval)
        }
        return false
    }

    // MARK: - Boot

    private func boot() async {
        setStatus(.restarting, issue: nil)
        generation += 1
        let myGeneration = generation

        let kernel: any KernelTransport
        do {
            kernel = try makeTransport()
            // EOF callback registered BEFORE spawn so a fast-failing boot is
            // never missed; generation-scoped so a stale worker's EOF can
            // never disturb a fresh one (the V0.2 restart race).
            kernel.setEOFHandler { [weak self] in
                guard let self else { return }
                Task { await self.handleEOF(generation: myGeneration) }
            }
            try kernel.spawn()
        } catch {
            logger.error("kernel setup failed: \(String(describing: error), privacy: .public)")
            // Setup failures (no Sage, no worker script) are flagged so the
            // banner can lead with the Sage Doctor instead of a blind restart.
            setStatus(
                .notConnected,
                issue: String(describing: error),
                setupFailure: error is KernelSetupError)
            return
        }
        transport = kernel
        currentSagePath = kernel.sageBinaryPath

        // Await the ready banner (carries the worker's REAL pid — the
        // SIGINT target; the spawned pid is just the bash wrapper).
        let clock = ContinuousClock()
        let deadline = clock.now + configuration.readyTimeout
        while clock.now < deadline {
            if generation != myGeneration { return }  // preempted
            if let banner = kernel.dequeue(where: { ($0["op"] as? String) == "ready" }) {
                if let pid = banner["pid"] as? Int {
                    kernel.noteRealPID(Int32(pid))
                }
                logger.notice("worker ready (pid \(banner["pid"] as? Int ?? -1))")
                setStatus(.idle, issue: nil)
                return
            }
            if kernel.isAtEOF {
                endGeneration()
                logger.error("worker exited before sending its ready banner")
                setStatus(
                    .notConnected,
                    issue: "Sage exited before it finished starting. See the worker log in ~/Library/Application Support/Casette/logs/.")
                return
            }
            try? await Task.sleep(for: configuration.pollInterval)
        }

        // Hung at boot: hard-kill BEFORE reporting, or the wrapper and its
        // children leak (the V0.9 hang-at-boot lesson).
        endGeneration()
        logger.error("worker never became ready — killed")
        setStatus(
            .notConnected,
            issue: "Sage didn't finish starting in time and was stopped. See the worker log in ~/Library/Application Support/Casette/logs/.")
    }

    // MARK: - Private

    private enum EscalationCause { case cancel, timeout }

    /// Maps an arrived response + escalation cause to the terminal state
    /// (mirrors controller.py `_finish`).
    private func finish(
        _ response: [String: Any],
        cause: EscalationCause?,
        duration: TimeInterval,
        generation myGeneration: Int
    ) -> Evaluation {
        let status = RowStatus(workerResponse: response)
        let envelope = PersistedEnvelope(workerResponse: response)
        let terminal: KernelState =
            switch status {
            case .ok: .completed
            // SIGINT honored: the worker survived and is ready for more.
            case .interrupted: cause == .timeout ? .timedOut : .interrupted
            case .error, .running: .error
            }
        if generation == myGeneration {
            setStatus(terminal, issue: nil)
        }
        logger.notice("eval finished: \(terminal.rawValue, privacy: .public) in \(duration, format: .fixed(precision: 3))s")
        return Evaluation(status: status, result: envelope, duration: duration)
    }

    /// Ends the current generation around a dead/killed worker, flips to
    /// `.crashed` with an honest issue, and returns the evaluation outcome.
    private func failGeneration(
        _ myGeneration: Int,
        kernel: any KernelTransport,
        issue: String,
        evaluation: Evaluation
    ) -> Evaluation {
        kernel.hardKill()
        if generation == myGeneration {
            endGeneration()
            setStatus(.crashed, issue: issue)
        }
        return evaluation
    }

    /// Kills and detaches the current worker and bumps the generation so
    /// stale EOF callbacks and loops become no-ops.
    private func endGeneration() {
        generation += 1
        transport?.hardKill()
        transport = nil
        currentSagePath = nil
    }

    /// Idle crash detection: the generation's EOF callback lands here. The
    /// running and booting cases are handled by their own loops.
    private func handleEOF(generation eofGeneration: Int) {
        guard eofGeneration == generation else { return }  // stale generation
        guard state != .running, state != .restarting else { return }
        logger.error("worker stopped unexpectedly while idle")
        endGeneration()
        setStatus(
            .crashed,
            issue: "Sage stopped unexpectedly. Restart Sage to continue (variables will be reset).")
    }

    private func waitWhileBootingOrBusy() async {
        // Bounded: boot resolves within readyTimeout; a concurrent metadata
        // request resolves within metadataTimeout.
        let clock = ContinuousClock()
        let deadline = clock.now + configuration.readyTimeout + configuration.metadataTimeout
        while clock.now < deadline, state == .restarting || requestInFlight {
            try? await Task.sleep(for: configuration.pollInterval)
        }
    }

    private func setStatus(
        _ newState: KernelState, issue newIssue: String?, setupFailure: Bool = false
    ) {
        state = newState
        issue = newIssue
        statusContinuation.yield(
            KernelStatus(state: newState, issue: newIssue, isSetupFailure: setupFailure))
        logger.info("kernel state → \(newState.rawValue, privacy: .public)")
    }

    private func nextRequestID(prefix: String) -> String {
        requestCounter += 1
        return "\(prefix)-\(requestCounter)"
    }

    private func elapsed(since start: ContinuousClock.Instant, clock: ContinuousClock) -> TimeInterval {
        let duration = start.duration(to: clock.now)
        let components = duration.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) * 1e-18
    }

    /// A parent-side envelope for outcomes the worker never produced (crash,
    /// forced stop, kernel unavailable) so the row still renders an honest,
    /// readable error and persists self-describing data.
    private func syntheticEnvelope(type: String, message: String) -> PersistedEnvelope {
        PersistedEnvelope(
            kind: "error",
            plain: message,
            error: PersistedError(type: type, message: message))
    }
}
