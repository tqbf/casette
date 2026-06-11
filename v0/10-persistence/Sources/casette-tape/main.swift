import Foundation
import SessionStore

// MARK: - casette-tape: the V0.10 proof harness
//
// Drives the full session-persistence proof end to end and prints a pass/fail
// checklist mapped to the V0.10 exit criteria. Subcommands let the orchestrator
// (and the README) reproduce each phase; `all` runs the complete proof.
//
// Storage is hermetic: set CASETTE_CONFIG_DIR to a scratch dir (the harness does
// this for `all`), so nothing touches the real Application Support location.

let sagePath = ProcessInfo.processInfo.environment["CASETTE_SAGE"]
  ?? "/usr/local/bin/sage"
let workerPath = ProcessInfo.processInfo.environment["CASETTE_WORKER"]
  ?? defaultWorkerPath()

func defaultWorkerPath() -> String {
  // This file lives at v0/10-persistence/Sources/casette-tape/main.swift; the
  // canonical worker is at v0/01-worker-protocol/worker.py.
  let thisFile = URL(fileURLWithPath: #filePath)
  let repoV0 = thisFile
    .deletingLastPathComponent()  // casette-tape
    .deletingLastPathComponent()  // Sources
    .deletingLastPathComponent()  // 10-persistence
    .deletingLastPathComponent()  // v0
  return repoV0
    .appendingPathComponent("01-worker-protocol/worker.py").path
}

// MARK: Checklist plumbing

final class Checklist {
  private(set) var passed = 0
  private(set) var failed = 0
  func check(_ ok: Bool, _ label: String, detail: String = "") {
    if ok {
      passed += 1
      print("  PASS  \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    } else {
      failed += 1
      print("  FAIL  \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    }
  }
  func section(_ title: String) { print("\n\(title)") }
}

func requiredVarsByRowID(_ session: Session, steps: [RecordStep]) -> [UUID: [String]] {
  var map: [UUID: [String]] = [:]
  for (row, step) in zip(session.rows, steps) {
    map[row.id] = step.requiredVariables
  }
  return map
}

// MARK: The full proof

func runAll(_ list: Checklist) -> Int {
  // Hermetic scratch dir for the whole proof.
  let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("casette-v010-\(UUID().uuidString)", isDirectory: true)
  setenv("CASETTE_CONFIG_DIR", scratch.path, 1)
  let store = SessionStore()
  print("Sage:    \(sagePath)")
  print("Worker:  \(workerPath)")
  print("Store:   \(store.sessionFileURL.path)")

  let driver = WorkerDriver(sagePath: sagePath, workerPath: workerPath)

  // ===== Phase 1: record a real worker session, persisted incrementally =====
  list.section("Phase 1 — record a real worker session (incremental atomic save)")
  let now = Date()
  var session = Session(created: now, updated: now, sageVersion: "9.5")
  let steps = Fixtures.mainTape
  do {
    session = try driver.record(
      steps: steps, into: session, store: store, precisionDigits: 10)
  } catch {
    print("  FATAL  record failed: \(error)")
    return 1
  }
  list.check(session.rows.count == steps.count,
    "all \(steps.count) rows recorded",
    detail: "\(session.rows.count) rows")
  list.check(FileManager.default.fileExists(atPath: store.sessionFileURL.path),
    "session file written to disk")
  // Sanity on the recorded content.
  let factorRow = session.rows[0]
  list.check(factorRow.input == "factor x^4 - 1" && factorRow.sage == "factor(x^4 - 1)",
    "row 0 keeps input vs sage distinction",
    detail: "\(factorRow.input)  →  \(factorRow.sage)")
  let rationalRow = session.rows[1]
  list.check(rationalRow.result?.plain == "8/15"
      && rationalRow.result?.approx == "0.5333333333",
    "row 1 cached envelope has exact plain + approx",
    detail: "plain=\(rationalRow.result?.plain ?? "?") approx=\(rationalRow.result?.approx ?? "?")")
  let eigRow = session.rows[3]
  list.check(eigRow.status == .ok && eigRow.result?.kind == "list",
    "row 3 (A.eigenvalues()) evaluated against stored A",
    detail: "kind=\(eigRow.result?.kind ?? "?") plain=\(eigRow.result?.plain ?? "?")")

  // Show the pretty-printed file is inspectable (first lines).
  if let raw = try? String(contentsOf: store.sessionFileURL, encoding: .utf8) {
    let head = raw.split(separator: "\n").prefix(6).joined(separator: "\n")
    print("\n  --- last-session.json (head) ---")
    print(head.split(separator: "\n").map { "  " + $0 }.joined(separator: "\n"))
    print("  ---")
  }

  // ===== Phase 2: "relaunch" — fresh load, Sage NOT spawned =====
  list.section("Phase 2 — relaunch: restore the tape with Sage genuinely not involved")
  let outcome = store.load()
  guard case let .restored(restored) = outcome else {
    print("  FAIL  restore did not return .restored: \(outcome)")
    return 1
  }
  list.check(restored.rows.count == steps.count,
    "restored \(restored.rows.count) rows from disk (no worker spawned)")
  // The restored rows are render-ready: plain/latex match what was saved.
  let savedFactor = session.rows[0].result
  let restoredFactor = restored.rows[0].result
  list.check(savedFactor?.plain == restoredFactor?.plain
      && savedFactor?.latex == restoredFactor?.latex,
    "restored row 0 plain/latex matches saved",
    detail: "plain=\(restoredFactor?.plain ?? "?")")
  list.check(restored.rows.allSatisfy { $0.provenance.kind == .cached },
    "every restored row is provenance=cached")
  let restoredRational = restored.rows[1].result
  list.check(restoredRational?.plain == "8/15"
      && restoredRational?.approx == "0.5333333333"
      && restoredRational?.exact == true,
    "restored row 1 renders exact + approx with no worker",
    detail: "plain=\(restoredRational?.plain ?? "?") approx=\(restoredRational?.approx ?? "?") exact=\(String(describing: restoredRational?.exact))")

  // ===== Phase 3: replay into a FRESH worker (state-dependent) =====
  list.section("Phase 3 — replay the restored tape into a fresh worker (order preserved)")
  let replayResult: ReplayResult
  do {
    replayResult = try driver.replay(
      restored,
      requiredVariablesByRowID: requiredVarsByRowID(restored, steps: steps))
  } catch {
    print("  FAIL  replay failed: \(error)")
    return 1
  }
  let replayed = replayResult.session
  list.check(replayed.rows.allSatisfy { $0.provenance.kind == .replayed },
    "every row now provenance=replayed")
  list.check(replayed.rows.allSatisfy { $0.provenance.replayedAt != nil },
    "every replayed row has a replayedAt timestamp")
  list.check(replayed.rows.allSatisfy { $0.provenance.cachedAt != nil },
    "every replayed row still carries its original cachedAt")
  let replayedEig = replayed.rows[3]
  list.check(replayedEig.status == .ok && replayedEig.result?.kind == "list",
    "state-dependent row 3 (A.eigenvalues()) replayed OK — A was re-established by order",
    detail: "kind=\(replayedEig.result?.kind ?? "?") plain=\(replayedEig.result?.plain ?? "?")")

  // ===== Phase 4: replayed vs cached distinguishable =====
  list.section("Phase 4 — replayed vs cached distinguishable")
  // The deterministic rows should match cached (no supersession); provenance flips.
  let row1Cached = restored.rows[1].result?.plain
  let row1Replayed = replayed.rows[1].result?.plain
  list.check(row1Cached == row1Replayed && replayed.rows[1].provenance.kind == .replayed,
    "deterministic row 1: value identical, provenance flipped cached→replayed",
    detail: "value=\(row1Replayed ?? "?")")
  list.check(replayResult.differingRowIDs.isEmpty,
    "no spurious supersession for deterministic tape (paths-only diffs ignored)")
  // Now force a DIFFERING replay to prove supersession is captured in the model.
  do {
    let supersedeOK = try proveSupersession(driver: driver)
    list.check(supersedeOK,
      "a differing replay retains the cached envelope in supersededCache (replace + keep)")
  } catch {
    list.check(false, "supersession proof errored: \(error)")
  }

  // ===== Phase 5: missing artifacts degrade gracefully =====
  list.section("Phase 5 — missing artifacts degrade gracefully (plot row)")
  do {
    let artifactOK = try proveMissingArtifacts(driver: driver)
    list.check(artifactOK.restoreOK,
      "plot row restores with artifact marked MISSING + plain text intact")
    list.check(artifactOK.replayRegenerated,
      "replay regenerated a FRESH present artifact for the missing one")
  } catch {
    list.check(false, "missing-artifact proof errored: \(error)")
  }

  // ===== Phase 6: robustness (no worker needed) =====
  list.section("Phase 6 — robustness: corruption / schema / empty / missing")
  proveRobustness(list)

  return 0
}

// MARK: Phase 4 helper — supersession

func proveSupersession(driver: WorkerDriver) throws -> Bool {
  // Build a one-row session whose CACHED result is deliberately wrong, then
  // replay it; the replay must differ and capture the cache in supersededCache.
  let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("casette-v010-sup-\(UUID().uuidString)", isDirectory: true)
  let store = SessionStore(directory: scratch.appendingPathComponent("sessions"))
  let now = Date()
  var session = Session(created: now, updated: now)
  // Cached envelope claims plain "999" for `1 + 1`; replay will return "2".
  let wrongCache = PersistedEnvelope(kind: "integer", plain: "999", latex: "999")
  session.rows = [SessionRow(
    input: "1 + 1", sage: "1 + 1", result: wrongCache, status: .ok,
    timestamp: now, provenance: Provenance(kind: .cached, cachedAt: now))]
  try store.save(session)
  guard case let .restored(restored) = store.load() else { return false }
  let result = try driver.replay(restored)
  let row = result.session.rows[0]
  let captured = row.supersededCache
  let replacedToTwo = row.result?.plain == "2"
  let keptOldCache = captured?.envelope.plain == "999"
  print("    replay differed: \(result.differingRowIDs.count == 1); "
    + "current plain=\(row.result?.plain ?? "?"), "
    + "supersededCache plain=\(captured?.envelope.plain ?? "nil"), "
    + "reason=\(captured?.reason ?? "nil")")
  return replacedToTwo && keptOldCache && result.differingRowIDs.count == 1
}

// MARK: Phase 5 helper — missing artifacts

struct MissingArtifactOutcome { var restoreOK: Bool; var replayRegenerated: Bool }

func proveMissingArtifacts(driver: WorkerDriver) throws -> MissingArtifactOutcome {
  let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("casette-v010-plot-\(UUID().uuidString)", isDirectory: true)
  let store = SessionStore(directory: scratch.appendingPathComponent("sessions"))
  let now = Date()
  var session = Session(created: now, updated: now)
  session = try driver.record(
    steps: Fixtures.plotTape, into: session, store: store, precisionDigits: 10)

  let plotRow = session.rows[0]
  guard let result = plotRow.result, !result.artifacts.isEmpty else {
    print("    no artifacts produced for the plot row")
    return MissingArtifactOutcome(restoreOK: false, replayRegenerated: false)
  }
  // Delete the artifact files on disk (simulating the V0.5 session-dir removal).
  for artifact in result.artifacts {
    if let path = artifact.path, FileManager.default.fileExists(atPath: path) {
      try? FileManager.default.removeItem(atPath: path)
    }
  }
  // Restore: liveness must flip to .missing, and the row still has plain text.
  guard case let .restored(restored) = store.load() else {
    return MissingArtifactOutcome(restoreOK: false, replayRegenerated: false)
  }
  let restoredRow = restored.rows[0]
  let allMissing = restoredRow.result?.artifacts.allSatisfy { $0.status == .missing } ?? false
  let kindIntact = restoredRow.result?.kind == "plot"
  print("    restored plot row: kind=\(restoredRow.result?.kind ?? "?"), "
    + "artifacts=\(restoredRow.result?.artifacts.count ?? 0) all .missing=\(allMissing), "
    + "plain=\"\(restoredRow.result?.plain ?? "")\"")
  let restoreOK = allMissing && kindIntact

  // Replay: a fresh worker regenerates the plot → fresh present artifacts.
  let replay = try driver.replay(
    restored,
    requiredVariablesByRowID: [restoredRow.id: ["x"]])
  let replayedRow = replay.session.rows[0]
  let regenerated = (replayedRow.result?.artifacts.contains { $0.status == .present }) ?? false
  print("    replayed plot row: artifacts=\(replayedRow.result?.artifacts.count ?? 0), "
    + "any .present=\(regenerated)")
  return MissingArtifactOutcome(restoreOK: restoreOK, replayRegenerated: regenerated)
}

// MARK: Phase 6 helper — robustness (pure, no worker)

func proveRobustness(_ list: Checklist) {
  // 6a. Corrupted JSON → quarantine + fresh.
  do {
    let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("casette-v010-corrupt-\(UUID().uuidString)", isDirectory: true)
    let dir = scratch.appendingPathComponent("sessions")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let store = SessionStore(directory: dir)
    try Data("{ this is not valid json ]".utf8).write(to: store.sessionFileURL)
    let outcome = store.load()
    if case let .corruptQuarantined(quarantinePath, _) = outcome {
      let quarantined = FileManager.default.fileExists(atPath: quarantinePath)
      let originalGone = !FileManager.default.fileExists(atPath: store.sessionFileURL.path)
      list.check(quarantined && originalGone,
        "corrupt JSON → quarantined aside, fresh start, no crash",
        detail: "quarantine=\(URL(fileURLWithPath: quarantinePath).lastPathComponent)")
    } else {
      list.check(false, "corrupt JSON did not quarantine: \(outcome)")
    }
  } catch {
    list.check(false, "corruption test errored: \(error)")
  }

  // 6b. Unknown schema version → polite refusal (file left intact).
  do {
    let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("casette-v010-schema-\(UUID().uuidString)", isDirectory: true)
    let dir = scratch.appendingPathComponent("sessions")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let store = SessionStore(directory: dir)
    let future = """
      { "schemaVersion": 9999, "created": "2026-06-11T00:00:00Z",
        "updated": "2026-06-11T00:00:00Z", "precisionDigits": 10, "rows": [] }
      """
    try Data(future.utf8).write(to: store.sessionFileURL)
    let outcome = store.load()
    if case let .refusedSchema(found, supported) = outcome {
      let intact = FileManager.default.fileExists(atPath: store.sessionFileURL.path)
      list.check(found == 9999 && supported == currentSchemaVersion && intact,
        "unknown schema version → polite refusal, file left intact",
        detail: "found=\(found) supported=\(supported)")
    } else {
      list.check(false, "unknown schema did not refuse: \(outcome)")
    }
  } catch {
    list.check(false, "schema test errored: \(error)")
  }

  // 6c. Empty file → fresh.
  do {
    let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("casette-v010-empty-\(UUID().uuidString)", isDirectory: true)
    let dir = scratch.appendingPathComponent("sessions")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let store = SessionStore(directory: dir)
    try Data().write(to: store.sessionFileURL)
    list.check(store.load() == .fresh, "empty file → fresh session")
  } catch {
    list.check(false, "empty test errored: \(error)")
  }

  // 6d. Missing file → fresh.
  let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("casette-v010-missing-\(UUID().uuidString)", isDirectory: true)
  let store = SessionStore(directory: scratch.appendingPathComponent("sessions"))
  list.check(store.load() == .fresh, "missing file → fresh session")
}

// MARK: Entry

let args = Array(CommandLine.arguments.dropFirst())
let command = args.first ?? "all"

switch command {
case "record-example":
  // Records the main tape into CASETTE_CONFIG_DIR (must be set) and exits, so the
  // resulting last-session.json can be inspected / captured for docs.
  let store = SessionStore()
  let driver = WorkerDriver(sagePath: sagePath, workerPath: workerPath)
  let now = Date()
  var session = Session(created: now, updated: now, sageVersion: "9.5")
  do {
    session = try driver.record(
      steps: Fixtures.mainTape, into: session, store: store, precisionDigits: 10)
    print("wrote \(session.rows.count) rows to \(store.sessionFileURL.path)")
    exit(0)
  } catch {
    print("record failed: \(error)")
    exit(1)
  }
case "all":
  print("=== Casette V0.10 — Session Tape Persistence-Lite — proof ===")
  let list = Checklist()
  let rc = runAll(list)
  print("\n=== \(list.passed) passed, \(list.failed) failed ===")
  exit((rc == 0 && list.failed == 0) ? 0 : 1)
default:
  print("usage: casette-tape [all]")
  exit(2)
}
