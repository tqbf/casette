import Foundation

// MARK: - Persisted result envelope (a render-ready SUBSET of the worker envelope)
//
// LIFTED from v0/10-persistence/Sources/SessionStore/PersistedEnvelope.swift
// (the frozen SESSION-FORMAT.md schema, version 1). This is the V1.2
// `ResultEnvelope` / `Artifact` — see the typealiases at the end of this file.
//
// V1.5 additive change (the one deviation from the verbatim lift, documented
// in SESSION-FORMAT.md): the optional `truncation` field carries the worker's
// truncation sizes so the UI can say "showing N of M characters" honestly
// instead of a bare "truncated". Optional + omitted-when-nil → schema v1
// files (with or without it) round-trip unchanged; old readers ignore it.
//
// The worker envelope (WORKER-PROTOCOL.md) carries transient framing (`id`,
// `op`, `value`) and large optional payloads. What the UI needs to RENDER a
// restored row WITHOUT a worker is a stable subset: the kind, the display
// strings, the exact/approx fields, and artifact references. That subset is
// `PersistedEnvelope`. It is the V1.2 `ResultEnvelope` prototype.

/// The render-ready subset of the worker result envelope, persisted per row.
///
/// Field choices (and what is intentionally dropped) are documented in
/// plans/SESSION-FORMAT.md. At minimum the spec demands kind/plain/latex/approx/
/// exact/truncated and artifacts-as-paths — all present here.
public struct PersistedEnvelope: Codable, Equatable, Sendable {
  /// One of the frozen 14-kind set (`integer`, `matrix`, `symbolic`, …).
  public var kind: String
  /// `str(value)`, the primary human-readable text. Always present.
  public var plain: String
  /// Sage LaTeX, or nil when it doesn't render (plot, text, error).
  public var latex: String?
  /// `repr(value)` — the unambiguous fallback / degrade target.
  public var repr: String?
  /// Numeric approximation string, or nil (per the V0.8 per-kind policy).
  public var approx: String?
  /// Precision (decimal digits) `approx` carries, or nil.
  public var approxDigits: Int?
  /// Is the PRIMARY result exact? true/false/null (V0.8).
  public var exact: Bool?
  /// Render `≈` on the primary value? (V0.8 force-numeric / float primary.)
  public var primaryIsApprox: Bool?
  /// Only present for a force-numeric eval: the original exact form.
  public var exactValue: String?
  /// Result-kind-aware UI action names (drives the V1.11 actions menu).
  public var actions: [String]
  /// Persisted artifact references (paths + format + liveness), not bytes.
  public var artifacts: [PersistedArtifact]
  /// Was `plain`/`repr` capped by the worker?
  public var truncated: Bool
  /// The worker's truncation sizes (original lengths + caps), present only
  /// when `truncated` — drives the honest "showing N of M characters" note.
  /// (V1.5 additive field; see the header note.)
  public var truncation: PersistedTruncation?
  /// Captured user `print()` / raw-fd output, if any (kept because it's display).
  public var stdout: String?
  public var stderr: String?
  /// For an error/interrupted row: the error detail (type/message/traceback).
  public var error: PersistedError?

  public init(
    kind: String,
    plain: String,
    latex: String? = nil,
    repr: String? = nil,
    approx: String? = nil,
    approxDigits: Int? = nil,
    exact: Bool? = nil,
    primaryIsApprox: Bool? = nil,
    exactValue: String? = nil,
    actions: [String] = [],
    artifacts: [PersistedArtifact] = [],
    truncated: Bool = false,
    truncation: PersistedTruncation? = nil,
    stdout: String? = nil,
    stderr: String? = nil,
    error: PersistedError? = nil
  ) {
    self.kind = kind
    self.plain = plain
    self.latex = latex
    self.repr = repr
    self.approx = approx
    self.approxDigits = approxDigits
    self.exact = exact
    self.primaryIsApprox = primaryIsApprox
    self.exactValue = exactValue
    self.actions = actions
    self.artifacts = artifacts
    self.truncated = truncated
    self.truncation = truncation
    self.stdout = stdout
    self.stderr = stderr
    self.error = error
  }
}

/// The worker's truncation detail (WORKER-PROTOCOL.md `truncation` object):
/// the ORIGINAL sizes of `plain`/`repr` plus the caps that were applied, so
/// the UI can render "showing N of M characters". (V1.5 additive.)
public struct PersistedTruncation: Codable, Equatable, Sendable {
  /// Original (pre-cap) length of `plain`, in characters.
  public var plainLength: Int?
  /// Original (pre-cap) length of `repr`, in characters.
  public var reprLength: Int?
  /// The cap applied to `plain`.
  public var plainCap: Int?
  /// The cap applied to `repr`.
  public var reprCap: Int?

  public init(
    plainLength: Int? = nil, reprLength: Int? = nil,
    plainCap: Int? = nil, reprCap: Int? = nil
  ) {
    self.plainLength = plainLength
    self.reprLength = reprLength
    self.plainCap = plainCap
    self.reprCap = reprCap
  }
}

/// The persisted error detail for an error/interrupted row.
public struct PersistedError: Codable, Equatable, Sendable {
  public var type: String
  public var message: String
  public var traceback: String?

  public init(type: String, message: String, traceback: String? = nil) {
    self.type = type
    self.message = message
    self.traceback = traceback
  }
}

// MARK: - Persisted artifact (path + format + liveness)

/// Liveness of an artifact file on restore. Artifacts live in the worker's
/// session-scoped `/tmp` dir, which dies with the worker (PROBLEMS.md V0.5), so
/// on a real restart a plot artifact is essentially ALWAYS stale — this is the
/// EXPECTED case, not an error.
public enum ArtifactStatus: String, Codable, Sendable {
  /// The file is still on disk where the path says.
  case present
  /// The file is gone (worker session dir removed, /tmp cleanup). Expected on
  /// restore. The row still restores with plain text; replay regenerates it.
  case missing
}

/// A persisted reference to a plot/image artifact. Stores the PATH and format,
/// not the bytes — and a liveness status resolved at restore time.
public struct PersistedArtifact: Codable, Equatable, Sendable {
  /// `"image"` (the only type so far).
  public var type: String
  /// `"svg"` or `"png"`.
  public var format: String
  /// Absolute path the worker wrote it to (nil if that format failed to save).
  public var path: String?
  /// File size recorded at save time (informational; the file may be gone now).
  public var bytes: Int?
  /// Resolved liveness: present / missing. Recomputed by `resolveLiveness()`.
  public var status: ArtifactStatus
  /// The worker's per-format save error (`"<ExcType>: <msg>"`), present only
  /// when this format failed to save — then `path` is nil
  /// (WORKER-PROTOCOL.md "Plot failures are structured"). V1.7 additive
  /// field, documented in SESSION-FORMAT.md: optional + omitted-when-nil, so
  /// schema v1 files with or without it round-trip unchanged.
  public var error: String?

  public init(
    type: String,
    format: String,
    path: String?,
    bytes: Int? = nil,
    status: ArtifactStatus = .present,
    error: String? = nil
  ) {
    self.type = type
    self.format = format
    self.path = path
    self.bytes = bytes
    self.status = status
    self.error = error
  }

  /// Returns a copy with `status` recomputed against the filesystem now.
  /// A nil path (format never saved) is treated as `missing`.
  public func resolvingLiveness(
    fileManager: FileManager = .default
  ) -> PersistedArtifact {
    var copy = self
    if let path, fileManager.fileExists(atPath: path) {
      copy.status = .present
    } else {
      copy.status = .missing
    }
    return copy
  }
}

// MARK: - V1.2 spec names
//
// INITIAL.md V1.2 names these core types `ResultEnvelope` and `Artifact`. The
// V0.10 types ARE those types (SESSION-FORMAT.md: "the V1.2 ResultEnvelope
// prototype", lifted verbatim) — aliases keep the spec vocabulary real in code
// without forking the model into a persisted world and a live world.

/// The V1.2 core type `ResultEnvelope` — the lifted V0.10 persisted envelope.
public typealias ResultEnvelope = PersistedEnvelope

/// The V1.2 core type `Artifact` — the lifted V0.10 persisted artifact.
public typealias Artifact = PersistedArtifact
