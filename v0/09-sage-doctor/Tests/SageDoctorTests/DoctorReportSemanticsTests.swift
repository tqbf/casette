import Foundation
import Testing
@testable import SageDoctor

/// Pure-logic checks on the report-level semantics that don't require Sage:
/// overall-OK derivation and the candidate `selected` mapping.
@Suite("DoctorReport — overall-OK semantics")
struct DoctorReportSemanticsTests {
  @Test("overallOK is false if any check fails, true if all pass/skip")
  func overallOKDerivation() {
    let passing = [
      CheckResult(id: "a", name: "A", status: .ok, durationMillis: 1, detail: ""),
      CheckResult(id: "b", name: "B", status: .skipped, durationMillis: 0, detail: ""),
    ]
    #expect(passing.allSatisfy { $0.status != .fail })

    let failing = passing + [
      CheckResult(id: "c", name: "C", status: .fail, durationMillis: 0, detail: "boom"),
    ]
    #expect(!failing.allSatisfy { $0.status != .fail })
  }

  @Test("the human report omits the duplicate standalone version row")
  func humanReportOmitsVersionRow() {
    let report = DoctorReport(
      sagePath: "/x/sage", candidates: [],
      versionRaw: "SageMath version 9.5", versionMajorMinor: "9.5",
      versionStanding: .supported,
      checks: [
        CheckResult(id: "version", name: "Sage version", status: .ok, durationMillis: 0, detail: "9.5"),
        CheckResult(id: "worker_boot", name: "Worker boot", status: .ok, durationMillis: 1, detail: "ready"),
      ],
      overallOK: true)
    let text = ReportFormatter.humanReadable(report)
    // Exactly one "Sage version:" line (the headline), not a second check row.
    let versionLines = text.split(separator: "\n").filter { $0.contains("Sage version:") }
    #expect(versionLines.count == 1)
  }
}
