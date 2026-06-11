import Foundation

/// A parsed `major.minor` Sage version. We ignore patch/build for the policy —
/// the floor is expressed in major.minor.
public struct SageVersion: Codable, Sendable, Equatable, Comparable {
  public let major: Int
  public let minor: Int
  /// The raw version line, e.g. "SageMath version 9.5, Release Date: 2022-01-30".
  public let raw: String

  public init(major: Int, minor: Int, raw: String) {
    self.major = major
    self.minor = minor
    self.raw = raw
  }

  public static func < (lhs: SageVersion, rhs: SageVersion) -> Bool {
    (lhs.major, lhs.minor) < (rhs.major, rhs.minor)
  }

  /// Parses the first `MAJOR.MINOR` it finds in a `sage --version` string.
  ///
  /// Real output: `SageMath version 9.5, Release Date: 2022-01-30`. We don't
  /// require an exact prefix — any `\d+\.\d+` token is accepted — so a slightly
  /// different banner (e.g. `Sage Version 10.3`) still parses.
  public static func parse(_ versionOutput: String) -> SageVersion? {
    let trimmed = versionOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    // Match the first number.number token.
    let pattern = #"(\d+)\.(\d+)"#
    guard
      let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(
        in: trimmed,
        range: NSRange(trimmed.startIndex..., in: trimmed)),
      let majorRange = Range(match.range(at: 1), in: trimmed),
      let minorRange = Range(match.range(at: 2), in: trimmed),
      let major = Int(trimmed[majorRange]),
      let minor = Int(trimmed[minorRange])
    else { return nil }
    return SageVersion(major: major, minor: minor, raw: trimmed)
  }
}

/// How a detected version sits against the support policy.
public enum VersionStanding: String, Codable, Sendable {
  /// At or above the floor we develop against — fully supported.
  case supported
  /// Below the floor but plausibly workable — proceed with a warning.
  case belowFloor
  /// No version string could be parsed — treat as suspect.
  case unknown
}

/// The version-support policy.
///
/// We develop and test against **Sage 9.5**, so that is the floor. A binary at
/// or above 9.5 is `supported`. Below 9.5 is the `belowFloor` warning band: the
/// doctor proceeds (the worker may still work) but flags that we don't test
/// against it. An unparseable banner is `unknown` — also a warning, never a hard
/// stop, because the worker checks below are the real proof of fitness.
public enum SageVersionPolicy {
  /// The version Casette develops against; also the support floor.
  public static let floor = SageVersion(major: 9, minor: 5, raw: "floor 9.5")

  public static func standing(for version: SageVersion?) -> VersionStanding {
    guard let version else { return .unknown }
    return version >= floor ? .supported : .belowFloor
  }

  /// A human sentence describing the standing, for the report.
  public static func note(for version: SageVersion?) -> String {
    switch standing(for: version) {
    case .supported:
      return "at or above the tested floor (9.5)"
    case .belowFloor:
      return "below the tested floor (9.5) — Casette is developed against 9.5; "
        + "this may work but is untested"
    case .unknown:
      return "could not parse a version; the end-to-end checks below are the "
        + "real test of fitness"
    }
  }
}
