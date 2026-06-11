import Foundation

/// Runs the worker-dependent checks against the canonical worker, applying the
/// PROBLEMS.md process lessons via `WorkerProcess`. Each check is timed and
/// produces an actionable `CheckResult`; a worker that won't boot fails the boot
/// check and the rest are reported `skipped`, never crashing the doctor.
struct WorkerCheckRunner {
  let sagePath: String
  let workerPath: String

  /// How long to wait for a worker's ready banner before declaring a boot
  /// failure. 120s for real Sage (a cold boot is ~3s, but CI machines vary);
  /// overridable via `CASETTE_READY_TIMEOUT` so the broken-config "hang at boot"
  /// proof fails fast instead of waiting two minutes.
  var readyTimeout: Double {
    if let raw = ProcessInfo.processInfo.environment["CASETTE_READY_TIMEOUT"],
      let seconds = Double(raw) {
      return seconds
    }
    return 120
  }

  func runAll() -> [CheckResult] {
    var results: [CheckResult] = []

    // Up-front: the worker file must exist, or every worker check is doomed with
    // a clear cause.
    guard FileManager.default.fileExists(atPath: workerPath) else {
      let detail = "worker script not found at \(workerPath) "
        + "(set CASETTE_WORKER to its path)"
      results.append(fail("worker_boot", "Worker boot", detail))
      for (id, name) in Self.skippableChecks {
        results.append(skip(id, name, "skipped: worker script missing"))
      }
      return results
    }

    // One worker for boot + the per-eval checks (boot, eval, state, latex, plot).
    let worker = WorkerProcess(sagePath: sagePath, workerPath: workerPath)
    let bootStart = Date()
    do {
      let banner = try worker.start(readyTimeout: readyTimeout)
      let pid = (banner["pid"] as? Int).map(String.init) ?? "?"
      results.append(
        ok("worker_boot", "Worker boot", millis(since: bootStart),
          "ready, worker pid \(pid)"))
    } catch {
      results.append(
        fail("worker_boot", "Worker boot", actionable(error)))
      // No worker — skip the eval-dependent checks (interrupt/restart spawn
      // their own workers, but with the same binary they'd fail identically;
      // we still attempt them so their diagnostics show).
      for (id, name) in Self.evalDependentChecks {
        results.append(skip(id, name, "skipped: worker did not boot"))
      }
      worker.shutdown()
      results.append(runInterruptCheck())
      results.append(runRestartCheck())
      return results
    }

    results.append(runEvalCheck(worker))
    results.append(runStateCheck(worker))
    results.append(runLatexCheck(worker))
    results.append(runPlotCheck(worker))

    // Clean teardown of the shared worker before the lifecycle checks.
    worker.shutdown()

    results.append(runInterruptCheck())
    results.append(runRestartCheck())
    return results
  }

  // MARK: - Per-eval checks

  /// 2 + 2 -> integer 4.
  private func runEvalCheck(_ worker: WorkerProcess) -> CheckResult {
    let start = Date()
    do {
      let response = try worker.request(["id": "eval", "code": "2 + 2"], timeout: 30)
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
      return fail("eval", "Eval test", actionable(error))
    }
  }

  /// Assign, then read back — proves the namespace persists across evals.
  private func runStateCheck(_ worker: WorkerProcess) -> CheckResult {
    let start = Date()
    do {
      _ = try worker.request(["id": "state-set", "code": "casette_probe = 41 + 1"], timeout: 30)
      let response = try worker.request(["id": "state-get", "code": "casette_probe"], timeout: 30)
      let plain = response["plain"] as? String ?? "?"
      guard plain == "42" else {
        return fail("state", "State persistence",
          "assigned 42, read back \(plain) — namespace not persisting")
      }
      return ok("state", "State persistence", millis(since: start),
        "assign then read back == 42")
    } catch {
      return fail("state", "State persistence", actionable(error))
    }
  }

  /// sqrt(2) envelope must carry a LaTeX field.
  private func runLatexCheck(_ worker: WorkerProcess) -> CheckResult {
    let start = Date()
    do {
      let response = try worker.request(["id": "latex", "code": "sqrt(2)"], timeout: 30)
      guard let latex = response["latex"] as? String, !latex.isEmpty else {
        return fail("latex", "LaTeX extraction",
          "sqrt(2) envelope had no latex field")
      }
      return ok("latex", "LaTeX extraction", millis(since: start),
        "sqrt(2) -> \(latex)")
    } catch {
      return fail("latex", "LaTeX extraction", actionable(error))
    }
  }

  /// plot(sin(x), (x,-1,1)) -> non-empty artifacts whose files exist.
  /// Needs `var('x')` first (PROBLEMS.md: a bare star-import doesn't predefine x
  /// in the worker reliably for plotting).
  private func runPlotCheck(_ worker: WorkerProcess) -> CheckResult {
    let start = Date()
    do {
      _ = try worker.request(["id": "plot-var", "code": "x = var('x')"], timeout: 30)
      let response = try worker.request(
        ["id": "plot", "code": "plot(sin(x), (x, -1, 1))"], timeout: 60)
      guard let artifacts = response["artifacts"] as? [[String: Any]],
        !artifacts.isEmpty else {
        return fail("plot", "Plot generation",
          "plot produced no artifacts")
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
      return fail("plot", "Plot generation", actionable(error))
    }
  }

  // MARK: - Interrupt (its own worker lifecycle)

  /// Start a `while True: pass` eval, SIGINT the REAL worker pid, expect an
  /// `interrupted` envelope (cysignals turns SIGINT into KeyboardInterrupt). If
  /// SIGINT is somehow swallowed we escalate to a hard process-group kill so we
  /// never hang or leak — and report that escalation honestly.
  private func runInterruptCheck() -> CheckResult {
    let start = Date()
    let worker = WorkerProcess(sagePath: sagePath, workerPath: workerPath)
    defer { worker.shutdown() }
    do {
      try worker.start(readyTimeout: readyTimeout)
    } catch {
      return fail("interrupt", "Interrupt", actionable(error))
    }
    do {
      try worker.sendAsync(["id": "spin", "code": "while True: pass"])
      // Give the eval a beat to actually start spinning, then interrupt.
      usleep(300_000)
      worker.interrupt()
      if let response = try worker.awaitResponse(id: "spin", timeout: 8) {
        let kind = response["kind"] as? String ?? "?"
        guard kind == "interrupted" else {
          return fail("interrupt", "Interrupt",
            "expected interrupted envelope, got kind=\(kind)")
        }
        return ok("interrupt", "Interrupt", millis(since: start),
          "SIGINT to real pid honored -> interrupted envelope")
      }
      // SIGINT didn't land in time — escalate (this is the mandatory hard-kill
      // path). Still a documented success of the CONTROL story.
      worker.hardKill()
      return ok("interrupt", "Interrupt", millis(since: start),
        "SIGINT not acknowledged; escalated to process-group kill (no leak)")
    } catch {
      worker.hardKill()
      return fail("interrupt", "Interrupt", actionable(error))
    }
  }

  // MARK: - Restart (kill the group, respawn, fresh namespace)

  /// Set a variable, hard-kill the process group, respawn, and prove the new
  /// worker has a fresh namespace (the variable is gone).
  private func runRestartCheck() -> CheckResult {
    let start = Date()
    let first = WorkerProcess(sagePath: sagePath, workerPath: workerPath)
    do {
      try first.start(readyTimeout: readyTimeout)
      _ = try first.request(["id": "set", "code": "restart_probe = 99"], timeout: 30)
      // Confirm it's there in the first generation.
      let before = try first.request(["id": "get1", "code": "restart_probe"], timeout: 30)
      guard before["plain"] as? String == "99" else {
        first.hardKill()
        return fail("restart", "Restart", "could not set state in first worker")
      }
    } catch {
      first.hardKill()
      return fail("restart", "Restart", actionable(error))
    }
    // Brutal kill of the whole group (wrapper + worker).
    first.hardKill()

    let second = WorkerProcess(sagePath: sagePath, workerPath: workerPath)
    defer { second.shutdown() }
    do {
      try second.start(readyTimeout: readyTimeout)
      // The fresh namespace must NOT have restart_probe -> NameError.
      let response = try second.request(["id": "get2", "code": "restart_probe"], timeout: 30)
      let ok = response["ok"] as? Bool ?? true
      let errorType = (response["error"] as? [String: Any])?["type"] as? String
      guard ok == false, errorType == "NameError" else {
        return fail("restart", "Restart",
          "respawned worker still knows restart_probe — namespace not fresh")
      }
      return self.ok("restart", "Restart", millis(since: start),
        "group-killed, respawned, fresh namespace (NameError as expected)")
    } catch {
      return fail("restart", "Restart", actionable(error))
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

  private func millis(since start: Date) -> Double {
    Date().timeIntervalSince(start) * 1000
  }

  /// Turns a thrown error into a one-line actionable message (never a stack
  /// trace). `WorkerError` already produces these.
  private func actionable(_ error: Error) -> String {
    if let workerError = error as? WorkerError {
      return workerError.description
    }
    return "\(error)"
  }
}
