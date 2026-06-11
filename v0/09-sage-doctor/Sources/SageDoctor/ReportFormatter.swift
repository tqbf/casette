import Foundation

/// Renders a `DoctorReport` two ways: a human-readable report matching the
/// spec's example shape, and the `--json` contract. Pure (string in, string
/// out) so it is unit-testable without running Sage.
public enum ReportFormatter {
  /// The human-readable report. Shape follows the spec:
  ///
  /// ```text
  /// Sage path: /usr/local/bin/sage
  /// Sage version: 9.5
  /// Worker boot: ok
  /// Eval test: ok
  /// ...
  /// ```
  public static func humanReadable(_ report: DoctorReport) -> String {
    var lines: [String] = []

    lines.append("Sage path: \(report.sagePath ?? "(none found)")")

    // The version headline (spec shape: a single `Sage version:` line). The
    // standing note rides as a suffix; the standalone `version` check row is
    // therefore suppressed in the loop below to avoid a duplicate line.
    if let raw = report.versionRaw {
      let shown = report.versionMajorMinor ?? raw
      lines.append("Sage version: \(shown)\(standingSuffix(report.versionStanding))")
    } else {
      lines.append("Sage version: (unknown)\(standingSuffix(report.versionStanding))")
    }

    for check in report.checks where check.id != "version" {
      lines.append("\(check.name): \(statusWord(check.status))\(detailSuffix(check))")
    }

    lines.append("")
    lines.append(report.overallOK ? "All checks passed." : "One or more checks FAILED.")
    return lines.joined(separator: "\n")
  }

  /// The `--json` contract output (pretty-printed, stable key order).
  public static func json(_ report: DoctorReport) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(report)
    return String(decoding: data, as: UTF8.self)
  }

  // MARK: - Private

  private static func statusWord(_ status: CheckStatus) -> String {
    switch status {
    case .ok: "ok"
    case .fail: "FAIL"
    case .skipped: "skipped"
    }
  }

  private static func standingSuffix(_ standing: VersionStanding) -> String {
    switch standing {
    case .supported: ""
    case .belowFloor: "  [WARNING: below tested floor 9.5]"
    case .unknown: "  [WARNING: version unrecognized]"
    }
  }

  /// On failure (or a notable detail), show the actionable detail inline. We
  /// keep `ok` rows clean unless they carry a short useful note.
  private static func detailSuffix(_ check: CheckResult) -> String {
    switch check.status {
    case .ok:
      return check.detail.isEmpty ? "" : "  (\(check.detail))"
    case .fail, .skipped:
      return check.detail.isEmpty ? "" : " — \(check.detail)"
    }
  }
}
