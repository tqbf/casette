import Foundation

/// The status of a single check.
public enum CheckStatus: String, Codable, Sendable {
  case ok
  case fail
  /// The check could not run because a prerequisite failed (e.g. version check
  /// skipped because no binary was found). Reported, never silently dropped.
  case skipped
}

/// One independent, timed diagnostic check.
///
/// This struct — and `DoctorReport` below — is the **V1.10 JSON contract**. The
/// in-app Sage Doctor pane decodes exactly this shape from `sage-doctor --json`,
/// or builds the same struct in-process from the `SageDoctor` library. Fields
/// are additive going forward; existing fields keep their meaning.
public struct CheckResult: Codable, Sendable {
  /// Stable identifier, e.g. "worker_boot" — the key V1.10 keys UI off, not the
  /// display name.
  public let id: String
  /// Human display name, e.g. "Worker boot".
  public let name: String
  public let status: CheckStatus
  /// Wall-clock duration in milliseconds.
  public let durationMillis: Double
  /// One-line outcome detail. On failure this is the ACTIONABLE message (what to
  /// do), never a raw stack trace.
  public let detail: String

  public init(
    id: String,
    name: String,
    status: CheckStatus,
    durationMillis: Double,
    detail: String
  ) {
    self.id = id
    self.name = name
    self.status = status
    self.durationMillis = durationMillis
    self.detail = detail
  }
}

/// A discovered candidate, in report form (mirrors `SageCandidate` plus a
/// `selected` flag for the JSON consumer).
public struct ReportCandidate: Codable, Sendable {
  public let path: String
  public let source: String
  public let exists: Bool
  public let selected: Bool

  public init(path: String, source: String, exists: Bool, selected: Bool) {
    self.path = path
    self.source = source
    self.exists = exists
    self.selected = selected
  }
}

/// The full diagnostic report. `sage-doctor --json` emits this; V1.10 decodes it.
public struct DoctorReport: Codable, Sendable {
  /// Report schema version, so V1.10 can evolve the contract safely.
  public let schemaVersion: Int
  /// The selected Sage binary, or `nil` if none was found.
  public let sagePath: String?
  /// All candidates considered, in priority order.
  public let candidates: [ReportCandidate]
  /// The raw `sage --version` line, or `nil`.
  public let versionRaw: String?
  /// Parsed `major.minor`, or `nil` if unparseable.
  public let versionMajorMinor: String?
  /// How the version sits against the support floor.
  public let versionStanding: VersionStanding
  /// Every check, in run order.
  public let checks: [CheckResult]
  /// True iff a Sage was selected and every non-skipped check passed.
  public let overallOK: Bool

  public init(
    schemaVersion: Int = 1,
    sagePath: String?,
    candidates: [ReportCandidate],
    versionRaw: String?,
    versionMajorMinor: String?,
    versionStanding: VersionStanding,
    checks: [CheckResult],
    overallOK: Bool
  ) {
    self.schemaVersion = schemaVersion
    self.sagePath = sagePath
    self.candidates = candidates
    self.versionRaw = versionRaw
    self.versionMajorMinor = versionMajorMinor
    self.versionStanding = versionStanding
    self.checks = checks
    self.overallOK = overallOK
  }
}
