import Foundation

// MARK: - WorkerDriver: record an original tape, and replay a restored one
//
// Two operations, both over a real `WorkerProcess` (the copied v0/09 pattern):
//
//   record(input,sage):  evaluate `sage` in a worker, capture the result as a
//                        PersistedEnvelope, and append a `.cached` row. This is
//                        how the ORIGINAL tape is produced for the proof.
//
//   replay(session):     spawn a FRESH worker, re-send each row's `sage` IN
//                        ORDER, attach the new result with `.replayed`
//                        provenance, and apply the supersede policy when a
//                        replayed result differs from the cached one. Order is
//                        preserved, so state-dependent rows (A = matrix(...)
//                        then A.eigenvalues()) replay correctly.

public struct WorkerDriver {
  public let sagePath: String
  public let workerPath: String
  public let evalTimeout: Double

  public init(sagePath: String, workerPath: String, evalTimeout: Double = 60) {
    self.sagePath = sagePath
    self.workerPath = workerPath
    self.evalTimeout = evalTimeout
  }

  // MARK: Record

  /// Drives a worker through a list of (input, sage, prelude) steps, appending a
  /// `.cached` row per step to `session`, and SAVING after every row (incremental
  /// crash-safety). `prelude` is the per-row var-declaration list (V0.7 policy:
  /// the caller emits `var('V')` for required variables before evaluating).
  ///
  /// Returns the populated session and the live worker's ready banner pid /
  /// reported Sage version (informational). The worker is shut down cleanly.
  public func record(
    steps: [RecordStep],
    into session0: Session,
    store: SessionStore,
    precisionDigits: Int
  ) throws -> Session {
    var session = session0
    let worker = WorkerProcess(sagePath: sagePath, workerPath: workerPath)
    defer { worker.shutdown() }
    _ = try worker.start()

    // Apply the session precision so cached approximations match it.
    _ = try worker.request(
      ["id": "config", "op": "config", "precision_digits": precisionDigits],
      timeout: 10)
    session.precisionDigits = precisionDigits

    for (index, step) in steps.enumerated() {
      // Emit any required-variable preludes first (V0.7 declaration policy).
      for variable in step.requiredVariables {
        _ = try worker.request(
          ["id": "var-\(index)-\(variable)", "code": "\(variable) = var('\(variable)')"],
          timeout: 10)
      }
      let start = Date()
      let response = try worker.request(
        ["id": "row-\(index)", "code": step.sage], timeout: evalTimeout)
      let duration = Date().timeIntervalSince(start)

      let envelope = PersistedEnvelope(workerResponse: response)
      let status = RowStatus(workerResponse: response)
      let now = Date()
      let row = SessionRow(
        input: step.input,
        sage: step.sage,
        result: envelope,
        status: status,
        timestamp: now,
        durationSeconds: duration,
        provenance: Provenance(kind: .cached, cachedAt: now),
        expanded: false)
      session.rows.append(row)
      // INCREMENTAL atomic save after every row — crash-safety is the point.
      try store.save(session)
    }
    return session
  }

  // MARK: Replay

  /// Replays a restored session into a FRESH worker. Re-sends each row's `sage`
  /// in order; the new result becomes the row's current result with `.replayed`
  /// provenance. If the replayed result DIFFERS from the cached one, the cached
  /// envelope is retained in `supersededCache` (policy: replace + keep the old).
  ///
  /// Preludes for replay: we re-declare each row's required variables, since a
  /// fresh worker has none of the original session's namespace. Order preserved.
  public func replay(
    _ session: Session,
    requiredVariablesByRowID: [UUID: [String]] = [:]
  ) throws -> ReplayResult {
    let worker = WorkerProcess(sagePath: sagePath, workerPath: workerPath)
    defer { worker.shutdown() }
    _ = try worker.start()

    _ = try worker.request(
      ["id": "config", "op": "config", "precision_digits": session.precisionDigits],
      timeout: 10)

    var replayed = session
    var differingRowIDs: [UUID] = []

    for (index, row) in session.rows.enumerated() {
      for variable in requiredVariablesByRowID[row.id] ?? [] {
        _ = try worker.request(
          ["id": "rvar-\(index)-\(variable)",
           "code": "\(variable) = var('\(variable)')"],
          timeout: 10)
      }
      let start = Date()
      let response = try worker.request(
        ["id": "replay-\(index)", "code": row.sage], timeout: evalTimeout)
      let duration = Date().timeIntervalSince(start)

      let newEnvelope = PersistedEnvelope(workerResponse: response)
      let newStatus = RowStatus(workerResponse: response)
      let now = Date()

      var updated = row
      // Supersede policy: if the replayed result differs from the cached one,
      // retain the cached envelope (don't silently drop it) and record why.
      if let cached = row.result,
        let difference = Self.difference(cached: cached, replayed: newEnvelope) {
        updated.supersededCache = SupersededCache(
          envelope: cached,
          cachedAt: row.provenance.cachedAt,
          reason: difference)
        differingRowIDs.append(row.id)
      }
      updated.result = newEnvelope
      updated.status = newStatus
      updated.durationSeconds = duration
      updated.provenance = Provenance(
        kind: .replayed,
        cachedAt: row.provenance.cachedAt,
        replayedAt: now)
      replayed.rows[index] = updated
    }
    replayed.updated = Date()
    return ReplayResult(session: replayed, differingRowIDs: differingRowIDs)
  }

  /// Returns a short reason string if the two envelopes differ in a way that
  /// matters for display, or nil if they are equivalent. Artifacts are compared
  /// by FORMAT/COUNT only (paths differ every run — a fresh worker writes new
  /// /tmp paths — so a path diff is NOT a meaningful supersession).
  static func difference(
    cached: PersistedEnvelope, replayed: PersistedEnvelope
  ) -> String? {
    if cached.kind != replayed.kind {
      return "kind changed (\(cached.kind) → \(replayed.kind))"
    }
    if cached.plain != replayed.plain {
      return "plain changed"
    }
    if cached.latex != replayed.latex {
      return "latex changed"
    }
    if cached.approx != replayed.approx {
      return "approx changed"
    }
    let cachedFormats = cached.artifacts.map(\.format).sorted()
    let replayedFormats = replayed.artifacts.map(\.format).sorted()
    if cachedFormats != replayedFormats {
      return "artifact set changed"
    }
    return nil
  }
}

/// One step in producing the original tape: the raw input, the Sage to evaluate,
/// and any variables to declare first (V0.7 `requiredVariables`).
public struct RecordStep: Sendable {
  public var input: String
  public var sage: String
  public var requiredVariables: [String]

  public init(input: String, sage: String, requiredVariables: [String] = []) {
    self.input = input
    self.sage = sage
    self.requiredVariables = requiredVariables
  }
}

/// The outcome of a replay: the updated session plus the ids of rows whose
/// replayed result superseded a differing cached one.
public struct ReplayResult: Sendable {
  public var session: Session
  public var differingRowIDs: [UUID]

  public init(session: Session, differingRowIDs: [UUID]) {
    self.session = session
    self.differingRowIDs = differingRowIDs
  }
}
