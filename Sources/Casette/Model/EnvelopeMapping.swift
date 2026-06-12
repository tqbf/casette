import Foundation

// MARK: - Worker envelope (raw JSON) -> PersistedEnvelope
//
// LIFTED VERBATIM from v0/10-persistence/Sources/SessionStore/EnvelopeMapping.swift.
// This is the single boundary where the wire shape becomes the model shape;
// V1.3's kernel hands raw `[String: Any]` wire objects to these initializers.
//
// The worker speaks JSONL; `WorkerProcess.request` hands back `[String: Any]`.
// This maps that raw envelope to the render-ready persisted subset. It is the
// single boundary where the wire shape becomes the model shape — V1 will reuse
// it (the worker contract is frozen, so this mapping is stable).

extension PersistedEnvelope {
  /// Builds a `PersistedEnvelope` from a raw worker response object.
  ///
  /// Tolerant by design: missing optional fields map to nil, not a failure, so a
  /// future additive worker field never breaks the mapping (forward-compatible).
  public init(workerResponse response: [String: Any]) {
    let kind = response["kind"] as? String ?? "unknown"
    let plain = response["plain"] as? String ?? ""
    let latex = response["latex"] as? String
    let repr = response["repr"] as? String
    let approx = response["approx"] as? String
    let approxDigits = response["approx_digits"] as? Int
    let exact = response["exact"] as? Bool
    let primaryIsApprox = response["primary_is_approx"] as? Bool
    let exactValue = response["exact_value"] as? String
    let actions = response["actions"] as? [String] ?? []
    let truncated = response["truncated"] as? Bool ?? false
    let stdout = response["stdout"] as? String
    let stderr = response["stderr"] as? String

    // The V0.3 truncation object ({plain_len, repr_len, plain_cap, repr_cap}),
    // present only when `truncated` — the "showing N of M chars" sizes (V1.5).
    var truncation: PersistedTruncation?
    if let truncationObject = response["truncation"] as? [String: Any] {
      truncation = PersistedTruncation(
        plainLength: truncationObject["plain_len"] as? Int,
        reprLength: truncationObject["repr_len"] as? Int,
        plainCap: truncationObject["plain_cap"] as? Int,
        reprCap: truncationObject["repr_cap"] as? Int)
    }

    var error: PersistedError?
    if let errorObject = response["error"] as? [String: Any] {
      error = PersistedError(
        type: errorObject["type"] as? String ?? "Error",
        message: errorObject["message"] as? String ?? "",
        traceback: errorObject["traceback"] as? String)
    }

    let artifacts = (response["artifacts"] as? [[String: Any]] ?? []).map {
      PersistedArtifact(workerArtifact: $0)
    }

    self.init(
      kind: kind,
      plain: plain,
      latex: latex,
      repr: repr,
      approx: approx,
      approxDigits: approxDigits,
      exact: exact,
      primaryIsApprox: primaryIsApprox,
      exactValue: exactValue,
      actions: actions,
      artifacts: artifacts,
      truncated: truncated,
      truncation: truncation,
      stdout: (stdout?.isEmpty == true) ? nil : stdout,
      stderr: (stderr?.isEmpty == true) ? nil : stderr,
      error: error)
  }
}

extension PersistedArtifact {
  /// Builds a `PersistedArtifact` from a raw worker artifact entry, resolving
  /// liveness against the filesystem immediately (the file is fresh — present).
  init(workerArtifact entry: [String: Any]) {
    let type = entry["type"] as? String ?? "image"
    let format = entry["format"] as? String ?? "png"
    let path = entry["path"] as? String
    let bytes = entry["bytes"] as? Int
    self.init(type: type, format: format, path: path, bytes: bytes)
    self = resolvingLiveness()
  }
}

// MARK: - RowStatus / Provenance from a worker response

extension RowStatus {
  /// Derives the row status from a worker response (`ok` + `kind`).
  public init(workerResponse response: [String: Any]) {
    let ok = response["ok"] as? Bool ?? false
    let kind = response["kind"] as? String ?? ""
    if ok {
      self = .ok
    } else if kind == "interrupted" {
      self = .interrupted
    } else {
      self = .error
    }
  }
}
