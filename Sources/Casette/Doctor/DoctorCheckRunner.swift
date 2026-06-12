import Foundation

/// Runs the V0.9 worker-dependent check list — boot, eval, state persistence,
/// LaTeX extraction, plot artifact, interrupt, restart — against a LIVE worker,
/// through the APP's own process machinery (`KernelTransport` / `SageKernel`).
///
/// This is the in-app port of v0/09's `WorkerCheckRunner`, with one deliberate
/// architectural change (the "ONE source of truth" rule): v0/09's blocking
/// `WorkerProcess`/`LineReader` pair is NOT lifted — the app already unified
/// them into `SageKernel` at V1.3, so the doctor spawns its workers through the
/// same transport seam the calculator uses (and tests drive the whole check
/// list over `FakeKernelTransport`s). Check ids, names, and detail vocabulary
/// stay the frozen v0/09 contract (plans/SAGE-DOCTOR.md).
///
/// Process-safety rules applied on every path (the V0.9 lessons):
///   * A boot that hangs or fails is hard-killed BEFORE it is reported — the
///     hang-at-boot fixture must leave no orphans.
///   * Every worker lifecycle ends in `hardKill()` (group SIGKILL), including
///     thrown/cancelled paths — `defer` guarantees it.
///   * Interrupt SIGINTs the REAL banner pid; a swallowed SIGINT escalates to
///     the group kill and reports the escalation honestly.
struct DoctorCheckRunner: Sendable {
    struct Configuration: Sendable {
        /// How long a worker may take to emit its ready banner. Real Sage cold
        /// boots in ~3s; broken-config tests shorten this so the hang-at-boot
        /// proof fails fast.
        var readyTimeout: Duration = .seconds(120)
        /// Per-request deadline for the cheap eval checks.
        var evalTimeout: Duration = .seconds(30)
        /// The plot check renders and saves files — give it longer.
        var plotTimeout: Duration = .seconds(60)
        /// How long the interrupt check waits for the `interrupted` envelope
        /// before escalating to the hard kill (v0/09 used 8s).
        var interruptResponseTimeout: Duration = .seconds(8)
        /// Pause before the SIGINT so the spin eval actually starts (v0/09).
        var interruptDelay: Duration = .milliseconds(300)
        var pollInterval: Duration = .milliseconds(25)

        static let standard = Configuration()
    }

    /// Builds one worker transport per lifecycle (`SageKernel` in the app;
    /// scripted fakes in tests).
    typealias TransportFactory = @Sendable (
        _ sagePath: String, _ workerPath: String
    ) throws -> any KernelTransport

    let sagePath: String
    /// Resolves the worker script (the bundled worker.py). Throws the
    /// app's actionable `KernelSetupError` when it's missing.
    let resolveWorker: @Sendable () throws -> String
    let makeTransport: TransportFactory
    let configuration: Configuration

    init(
        sagePath: String,
        resolveWorker: @escaping @Sendable () throws -> String = { try WorkerScriptLocator.locate() },
        makeTransport: @escaping TransportFactory = { sage, worker in
            SageKernel(sagePath: sage, workerPath: worker, stderrLogURL: KernelLog.prepareWorkerLog())
        },
        configuration: Configuration = .standard
    ) {
        self.sagePath = sagePath
        self.resolveWorker = resolveWorker
        self.makeTransport = makeTransport
        self.configuration = configuration
    }

    /// Runs every check in order, reporting each through `onCheck` as it
    /// completes (the Doctor UI appends rows live). Cooperative cancellation:
    /// a cancelled run marks the remaining checks `skipped` — and the worker
    /// teardown still happens (no leaks, even when the user stops a run).
    func runAll(
        onCheck: @MainActor @Sendable (CheckResult) -> Void = { _ in }
    ) async -> [CheckResult] {
        var results: [CheckResult] = []
        func record(_ result: CheckResult) async {
            results.append(result)
            await onCheck(result)
        }

        // Up-front: the worker script must exist, or every worker check is
        // doomed with a clear cause (the v0/09 shape; the locator's error is
        // already the actionable message).
        let workerPath: String
        do {
            workerPath = try resolveWorker()
        } catch {
            await record(fail("worker_boot", "Worker boot", actionable(error)))
            for (id, name) in Self.skippableChecks {
                await record(skip(id, name, "skipped: worker script missing"))
            }
            return results
        }

        // One worker for boot + the per-eval checks (boot, eval, state, latex,
        // plot).
        let bootStart = Date.now
        let worker: DoctorWorker
        do {
            worker = DoctorWorker(
                transport: try makeTransport(sagePath, workerPath),
                pollInterval: configuration.pollInterval)
        } catch {
            await record(fail("worker_boot", "Worker boot", actionable(error)))
            for (id, name) in Self.skippableChecks {
                await record(skip(id, name, "skipped: worker could not be created"))
            }
            return results
        }
        do {
            let banner = try await worker.boot(readyTimeout: configuration.readyTimeout)
            let pid = (banner["pid"] as? Int).map(String.init) ?? "?"
            await record(ok(
                "worker_boot", "Worker boot", millis(since: bootStart),
                "ready, worker pid \(pid)"))
        } catch {
            // boot() already hard-killed on its failure paths (the V0.9
            // hang-at-boot lesson); this is belt-and-braces.
            worker.hardKill()
            await record(outcome("worker_boot", "Worker boot", error))
            // No worker — skip the eval-dependent checks (interrupt/restart
            // spawn their own workers, but with the same binary they'd fail
            // identically; we still attempt them so their diagnostics show).
            for (id, name) in Self.evalDependentChecks {
                await record(skip(id, name, "skipped: worker did not boot"))
            }
            await record(runInterruptCheck(workerPath: workerPath))
            await record(runRestartCheck(workerPath: workerPath))
            return results
        }

        await record(runEvalCheck(worker))
        await record(runStateCheck(worker))
        await record(runLatexCheck(worker))
        await record(runPlotCheck(worker))

        // Teardown of the shared worker before the lifecycle checks. The app's
        // teardown is the group hard-kill (same as restart/quit — deterministic,
        // orphan-proof; the worker's /tmp dir is reaped by the OS).
        worker.hardKill()

        await record(runInterruptCheck(workerPath: workerPath))
        await record(runRestartCheck(workerPath: workerPath))
        return results
    }

    // MARK: - Per-eval checks

    /// 2 + 2 -> integer 4.
    private func runEvalCheck(_ worker: DoctorWorker) async -> CheckResult {
        let start = Date.now
        do {
            let response = try await worker.request(
                id: "eval", code: "2 + 2", timeout: configuration.evalTimeout)
            guard response["ok"] as? Bool == true else {
                return fail("eval", "Eval test", "worker returned not-ok for `2 + 2`")
            }
            let kind = response["kind"] as? String ?? "?"
            let plain = response["plain"] as? String ?? "?"
            guard kind == "integer", plain == "4" else {
                return fail("eval", "Eval test",
                    "expected integer 4, got kind=\(kind) plain=\(plain)")
            }
            return ok("eval", "Eval test", millis(since: start), "2 + 2 = 4")
        } catch {
            return outcome("eval", "Eval test", error)
        }
    }

    /// Assign, then read back — proves the namespace persists across evals.
    private func runStateCheck(_ worker: DoctorWorker) async -> CheckResult {
        let start = Date.now
        do {
            _ = try await worker.request(
                id: "state-set", code: "casette_probe = 41 + 1",
                timeout: configuration.evalTimeout)
            let response = try await worker.request(
                id: "state-get", code: "casette_probe", timeout: configuration.evalTimeout)
            let plain = response["plain"] as? String ?? "?"
            guard plain == "42" else {
                return fail("state", "State persistence",
                    "assigned 42, read back \(plain) — namespace not persisting")
            }
            return ok("state", "State persistence", millis(since: start),
                "assign then read back == 42")
        } catch {
            return outcome("state", "State persistence", error)
        }
    }

    /// sqrt(2) envelope must carry a LaTeX field.
    private func runLatexCheck(_ worker: DoctorWorker) async -> CheckResult {
        let start = Date.now
        do {
            let response = try await worker.request(
                id: "latex", code: "sqrt(2)", timeout: configuration.evalTimeout)
            guard let latex = response["latex"] as? String, !latex.isEmpty else {
                return fail("latex", "LaTeX extraction",
                    "sqrt(2) envelope had no latex field")
            }
            return ok("latex", "LaTeX extraction", millis(since: start),
                "sqrt(2) -> \(latex)")
        } catch {
            return outcome("latex", "LaTeX extraction", error)
        }
    }

    /// plot(sin(x), (x,-1,1)) -> non-empty artifacts whose files exist.
    /// Needs `var('x')` first (PROBLEMS.md: a bare star-import doesn't
    /// predefine x in the worker).
    private func runPlotCheck(_ worker: DoctorWorker) async -> CheckResult {
        let start = Date.now
        do {
            _ = try await worker.request(
                id: "plot-var", code: "x = var('x')", timeout: configuration.evalTimeout)
            let response = try await worker.request(
                id: "plot", code: "plot(sin(x), (x, -1, 1))",
                timeout: configuration.plotTimeout)
            guard let artifacts = response["artifacts"] as? [[String: Any]],
                  !artifacts.isEmpty else {
                return fail("plot", "Plot generation", "plot produced no artifacts")
            }
            // At least one artifact file must exist and be non-empty.
            let existing = artifacts.compactMap { $0["path"] as? String }
                .filter { path in
                    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                          let size = attrs[.size] as? Int else { return false }
                    return size > 0
                }
            guard let first = existing.first else {
                return fail("plot", "Plot generation",
                    "artifacts reported but no file exists/is non-empty on disk")
            }
            return ok("plot", "Plot generation", millis(since: start),
                "\(artifacts.count) artifact(s), e.g. \(first)")
        } catch {
            return outcome("plot", "Plot generation", error)
        }
    }

    // MARK: - Interrupt (its own worker lifecycle)

    /// Start a `while True: pass` eval, SIGINT the REAL worker pid, expect an
    /// `interrupted` envelope (cysignals turns SIGINT into KeyboardInterrupt).
    /// If SIGINT is somehow swallowed we escalate to a hard process-group kill
    /// so we never hang or leak — and report that escalation honestly.
    private func runInterruptCheck(workerPath: String) async -> CheckResult {
        // A cancelled run must not spawn yet another worker lifecycle.
        if Task.isCancelled {
            return skip("interrupt", "Interrupt", "skipped: stopped by the user")
        }
        let start = Date.now
        let worker: DoctorWorker
        do {
            worker = DoctorWorker(
                transport: try makeTransport(sagePath, workerPath),
                pollInterval: configuration.pollInterval)
        } catch {
            return fail("interrupt", "Interrupt", actionable(error))
        }
        defer { worker.hardKill() }
        do {
            _ = try await worker.boot(readyTimeout: configuration.readyTimeout)
        } catch {
            return outcome("interrupt", "Interrupt", error)
        }
        do {
            try worker.send(id: "spin", code: "while True: pass")
            // Give the eval a beat to actually start spinning, then interrupt.
            try? await Task.sleep(for: configuration.interruptDelay)
            worker.interrupt()
            if let response = try await worker.awaitResponse(
                id: "spin", timeout: configuration.interruptResponseTimeout) {
                let kind = response["kind"] as? String ?? "?"
                guard kind == "interrupted" else {
                    return fail("interrupt", "Interrupt",
                        "expected interrupted envelope, got kind=\(kind)")
                }
                return ok("interrupt", "Interrupt", millis(since: start),
                    "SIGINT to real pid honored -> interrupted envelope")
            }
            // SIGINT didn't land in time — escalate (this is the mandatory
            // hard-kill path). Still a documented success of the CONTROL story.
            worker.hardKill()
            return ok("interrupt", "Interrupt", millis(since: start),
                "SIGINT not acknowledged; escalated to process-group kill (no leak)")
        } catch {
            return outcome("interrupt", "Interrupt", error)
        }
    }

    // MARK: - Restart (kill the group, respawn, fresh namespace)

    /// Set a variable, hard-kill the process group, respawn, and prove the new
    /// worker has a fresh namespace (the variable is gone).
    private func runRestartCheck(workerPath: String) async -> CheckResult {
        if Task.isCancelled {
            return skip("restart", "Restart", "skipped: stopped by the user")
        }
        let start = Date.now
        let first: DoctorWorker
        do {
            first = DoctorWorker(
                transport: try makeTransport(sagePath, workerPath),
                pollInterval: configuration.pollInterval)
        } catch {
            return fail("restart", "Restart", actionable(error))
        }
        do {
            _ = try await first.boot(readyTimeout: configuration.readyTimeout)
            _ = try await first.request(
                id: "set", code: "restart_probe = 99", timeout: configuration.evalTimeout)
            // Confirm it's there in the first generation.
            let before = try await first.request(
                id: "get1", code: "restart_probe", timeout: configuration.evalTimeout)
            guard before["plain"] as? String == "99" else {
                first.hardKill()
                return fail("restart", "Restart", "could not set state in first worker")
            }
        } catch {
            first.hardKill()
            return outcome("restart", "Restart", error)
        }
        // Brutal kill of the whole group (wrapper + worker).
        first.hardKill()

        let second: DoctorWorker
        do {
            second = DoctorWorker(
                transport: try makeTransport(sagePath, workerPath),
                pollInterval: configuration.pollInterval)
        } catch {
            return fail("restart", "Restart", actionable(error))
        }
        defer { second.hardKill() }
        do {
            _ = try await second.boot(readyTimeout: configuration.readyTimeout)
            // The fresh namespace must NOT have restart_probe -> NameError.
            let response = try await second.request(
                id: "get2", code: "restart_probe", timeout: configuration.evalTimeout)
            let responseOK = response["ok"] as? Bool ?? true
            let errorType = (response["error"] as? [String: Any])?["type"] as? String
            guard responseOK == false, errorType == "NameError" else {
                return fail("restart", "Restart",
                    "respawned worker still knows restart_probe — namespace not fresh")
            }
            return ok("restart", "Restart", millis(since: start),
                "group-killed, respawned, fresh namespace (NameError as expected)")
        } catch {
            return outcome("restart", "Restart", error)
        }
    }

    // MARK: - Helpers

    static let evalDependentChecks: [(String, String)] = [
        ("eval", "Eval test"),
        ("state", "State persistence"),
        ("latex", "LaTeX extraction"),
        ("plot", "Plot generation"),
    ]

    static let skippableChecks: [(String, String)] = evalDependentChecks + [
        ("interrupt", "Interrupt"),
        ("restart", "Restart"),
    ]

    private func ok(_ id: String, _ name: String, _ ms: Double, _ detail: String) -> CheckResult {
        CheckResult(id: id, name: name, status: .ok, durationMillis: ms, detail: detail)
    }

    private func fail(_ id: String, _ name: String, _ detail: String) -> CheckResult {
        CheckResult(id: id, name: name, status: .fail, durationMillis: 0, detail: detail)
    }

    private func skip(_ id: String, _ name: String, _ detail: String) -> CheckResult {
        CheckResult(id: id, name: name, status: .skipped, durationMillis: 0, detail: detail)
    }

    /// Maps a thrown error to its honest check result: user cancellation is
    /// `skipped` (the check didn't fail — it never finished), everything else
    /// is a FAIL with the actionable one-liner.
    private func outcome(_ id: String, _ name: String, _ error: Error) -> CheckResult {
        if let failure = error as? DoctorWorker.Failure, case .cancelled = failure {
            return skip(id, name, "skipped: stopped by the user")
        }
        return fail(id, name, actionable(error))
    }

    private func millis(since start: Date) -> Double {
        Date.now.timeIntervalSince(start) * 1000
    }

    /// Turns a thrown error into a one-line actionable message (never a stack
    /// trace). `DoctorWorker.Failure` and `KernelSetupError` already produce
    /// these.
    private func actionable(_ error: Error) -> String {
        if let failure = error as? DoctorWorker.Failure {
            return failure.description
        }
        if let setup = error as? KernelSetupError {
            return setup.description
        }
        return "\(error)"
    }
}
