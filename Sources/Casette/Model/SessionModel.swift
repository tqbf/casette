import Foundation

// MARK: - Session model (V1.2)
//
// LIFTED VERBATIM from v0/10-persistence/Sources/SessionStore/SessionModel.swift
// (the frozen SESSION-FORMAT.md schema, version 1). Field names and semantics
// are identical to the persisted file shape so V1.9's `SessionStore` is a
// drop-in: these Codable types ARE the on-disk session file AND the in-app
// session model — one world, not two.
//
// App-side additions (Identifiable, view-derived helpers, `apply(Evaluation)`)
// live in SessionRow+App.swift so this file stays diffable against v0/10.
//
// Design choices (documented in plans/SESSION-FORMAT.md):
//   * `schemaVersion` is FIRST-CLASS and load-bearing — restore refuses an
//     unknown future version politely rather than mis-reading it.
//   * The persisted envelope is a SUBSET of the worker envelope: only the fields
//     needed to RENDER a row without a worker (kind/plain/latex/repr/approx/
//     exact/etc.) plus artifact refs (paths, not bytes). stdout/stderr/value/
//     actions/error are kept where they carry display meaning; transient framing
//     (`id`, `op`) is dropped.
//   * Every row carries PROVENANCE: was this result `cached` (loaded from disk)
//     or `replayed` (freshly recomputed)? A replay that DIFFERS from the cached
//     result keeps BOTH (the cached one is moved to `supersededCache`) so the
//     difference is visible in the data model.

/// The current on-disk schema version. Bump only on a breaking change; restore
/// refuses a version it doesn't recognize (forward-incompatible → polite refusal).
public let currentSchemaVersion = 1
public let defaultSessionPrecisionDigits = 5

// MARK: Session

/// A persisted calculator session: a header plus an ordered tape of rows.
///
/// NOT a document. There is exactly one "last session" file the app rewrites in
/// place (V1.9 — "persistent without becoming document-oriented"); the header
/// records provenance of the whole session so a restore can reason about it.
public struct Session: Codable, Equatable, Sendable {
  /// On-disk schema version. Checked on load before any field is trusted.
  public var schemaVersion: Int
  /// When the session was first created (ISO-8601).
  public var created: Date
  /// When the session was last written (ISO-8601). Bumped on every append.
  public var updated: Date
  /// The Sage version that produced the cached results (from the ready banner /
  /// doctor). Informational: a replay against a different Sage is still allowed,
  /// but the mismatch is visible.
  public var sageVersion: String?
  /// The session-default precision (the worker's `config` `precision_digits`),
  /// so a replay can restore the same precision the cached results used.
  public var precisionDigits: Int
  /// The ordered tape. Order is load-bearing for replay (state-dependent rows).
  public var rows: [SessionRow]

  public init(
    schemaVersion: Int = currentSchemaVersion,
    created: Date,
    updated: Date,
    sageVersion: String? = nil,
    precisionDigits: Int = defaultSessionPrecisionDigits,
    rows: [SessionRow] = []
  ) {
    self.schemaVersion = schemaVersion
    self.created = created
    self.updated = updated
    self.sageVersion = sageVersion
    self.precisionDigits = precisionDigits
    self.rows = rows
  }
}

// MARK: SessionRow

/// One tape entry: the raw user input, the Sage actually evaluated, the persisted
/// result envelope, a timestamp, and provenance.
///
/// Mirrors the V1.2 "Session Row Fields" list: id / raw input / compiled Sage /
/// status / result envelope / timestamp / duration / artifacts. (`expanded` is
/// the one UI-state field the spec lists; persisted so the tape restores
/// collapsed/expanded as the user left it.)
public struct SessionRow: Codable, Equatable, Sendable {
  /// Stable identity that survives save/restore (V1.2 "stable identity").
  public var id: UUID
  /// The raw text the user typed (`factor x^4 - 1`).
  public var input: String
  /// The Sage actually evaluated — friendly-compiled OR a raw-Sage bypass
  /// (`factor(x^4 - 1)`). This is what replay re-sends, in order.
  public var sage: String
  /// The persisted, render-ready result envelope (a subset of the worker
  /// envelope). Optional only to represent a row that never completed.
  public var result: PersistedEnvelope?
  /// `ok` / `error` / `interrupted` / `running` — the row status (V1.2).
  public var status: RowStatus
  /// When this row was evaluated (ISO-8601).
  public var timestamp: Date
  /// Wall-clock eval duration in seconds, if measured.
  public var durationSeconds: Double?
  /// Provenance: cached (from disk) vs replayed (freshly recomputed).
  public var provenance: Provenance
  /// When a replay produces a DIFFERENT result, the previous cached envelope is
  /// preserved here (not discarded) so the supersession is visible in the data.
  public var supersededCache: SupersededCache?
  /// UI state: was the row expanded? (V1.2 "expanded/collapsed UI state".)
  public var expanded: Bool
  /// True when this row was evaluated in force-numeric mode (the V0.8
  /// per-request `numeric:true` — decimal primary, exact form preserved in
  /// the envelope's `exactValue`). Recorded on the REQUEST side so a replay
  /// (V1.9) can reproduce the same display; the envelope alone can't always
  /// tell (a numeric eval of a statement or error carries no `exact_value`).
  /// V1.8 additive field, documented in SESSION-FORMAT.md: optional +
  /// omitted-when-nil, so schema v1 files with or without it round-trip
  /// unchanged and old readers ignore it — no schema bump.
  public var numeric: Bool?

  public init(
    id: UUID = UUID(),
    input: String,
    sage: String,
    result: PersistedEnvelope? = nil,
    status: RowStatus,
    timestamp: Date,
    durationSeconds: Double? = nil,
    provenance: Provenance = .cached,
    supersededCache: SupersededCache? = nil,
    expanded: Bool = false,
    numeric: Bool? = nil
  ) {
    self.id = id
    self.input = input
    self.sage = sage
    self.result = result
    self.status = status
    self.timestamp = timestamp
    self.durationSeconds = durationSeconds
    self.provenance = provenance
    self.supersededCache = supersededCache
    self.expanded = expanded
    self.numeric = numeric
  }
}

/// Row status. `running` exists so a row persisted mid-eval (crash-safety) is
/// representable; on restore a `running` row is incomplete, not a result.
public enum RowStatus: String, Codable, Sendable {
  case ok
  case error
  case interrupted
  case running
}

// MARK: Provenance

/// Where a row's CURRENT result came from. The replay proof turns on this:
/// a freshly restored tape is all `.cached`; after a replay each replayed row
/// flips to `.replayed` (with a fresh `replayedAt` timestamp).
public enum ProvenanceKind: String, Codable, Sendable {
  /// Loaded from disk — the worker was not involved in producing this result.
  case cached
  /// Freshly recomputed by re-sending `sage` to a worker this run.
  case replayed
}

public struct Provenance: Codable, Equatable, Sendable {
  public var kind: ProvenanceKind
  /// When the cached result was originally produced (carried across restore).
  public var cachedAt: Date?
  /// When this row was last replayed (nil until replayed).
  public var replayedAt: Date?

  public init(kind: ProvenanceKind, cachedAt: Date? = nil, replayedAt: Date? = nil) {
    self.kind = kind
    self.cachedAt = cachedAt
    self.replayedAt = replayedAt
  }

  public static let cached = Provenance(kind: .cached)
}

/// A cached envelope a later replay superseded with a DIFFERENT result. Kept so
/// "the difference and the policy are visible in the data model" (the spec).
/// Policy: REPLACE the current result with the replayed one, but RETAIN the
/// superseded cache here for inspection/diffing.
public struct SupersededCache: Codable, Equatable, Sendable {
  public var envelope: PersistedEnvelope
  public var cachedAt: Date?
  /// A short human-readable reason the replay differed (e.g. "plain changed").
  public var reason: String

  public init(envelope: PersistedEnvelope, cachedAt: Date?, reason: String) {
    self.envelope = envelope
    self.cachedAt = cachedAt
    self.reason = reason
  }
}
