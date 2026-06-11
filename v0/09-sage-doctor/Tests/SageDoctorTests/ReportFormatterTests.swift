import Foundation
import Testing
@testable import SageDoctor

@Suite("ReportFormatter — human + JSON shape")
struct ReportFormatterTests {
  private func sampleReport(overallOK: Bool = true) -> DoctorReport {
    DoctorReport(
      sagePath: "/usr/local/bin/sage",
      candidates: [
        ReportCandidate(
          path: "/usr/local/bin/sage", source: "knownPath", exists: true, selected: true),
        ReportCandidate(
          path: "/opt/homebrew/bin/sage", source: "knownPath", exists: false, selected: false),
      ],
      versionRaw: "SageMath version 9.5, Release Date: 2022-01-30",
      versionMajorMinor: "9.5",
      versionStanding: .supported,
      checks: [
        CheckResult(id: "version", name: "Sage version", status: .ok, durationMillis: 0, detail: "9.5"),
        CheckResult(id: "worker_boot", name: "Worker boot", status: .ok, durationMillis: 2900, detail: "ready, worker pid 1234"),
        CheckResult(id: "eval", name: "Eval test", status: overallOK ? .ok : .fail, durationMillis: 12, detail: overallOK ? "2 + 2 = 4" : "expected 4, got 5"),
      ],
      overallOK: overallOK)
  }

  @Test("human report matches the spec's line shape")
  func humanShape() {
    let text = ReportFormatter.humanReadable(sampleReport())
    #expect(text.contains("Sage path: /usr/local/bin/sage"))
    #expect(text.contains("Sage version: 9.5"))
    #expect(text.contains("Worker boot: ok"))
    #expect(text.contains("Eval test: ok"))
    #expect(text.contains("All checks passed."))
  }

  @Test("a FAIL renders FAIL with an actionable detail")
  func failRendering() {
    let text = ReportFormatter.humanReadable(sampleReport(overallOK: false))
    #expect(text.contains("Eval test: FAIL"))
    #expect(text.contains("expected 4, got 5"))
    #expect(text.contains("One or more checks FAILED."))
  }

  @Test("below-floor version shows a warning suffix")
  func belowFloorWarning() {
    let report = DoctorReport(
      sagePath: "/x/sage", candidates: [], versionRaw: "SageMath version 9.2",
      versionMajorMinor: "9.2", versionStanding: .belowFloor,
      checks: [], overallOK: true)
    let text = ReportFormatter.humanReadable(report)
    #expect(text.contains("WARNING"))
    #expect(text.contains("9.2"))
  }

  @Test("no-Sage report says (none found)")
  func noneFound() {
    let report = DoctorReport(
      sagePath: nil, candidates: [], versionRaw: nil, versionMajorMinor: nil,
      versionStanding: .unknown, checks: [], overallOK: false)
    let text = ReportFormatter.humanReadable(report)
    #expect(text.contains("Sage path: (none found)"))
  }

  @Test("JSON decodes back to an equivalent report (the V1.10 contract round-trips)")
  func jsonRoundTrips() throws {
    let report = sampleReport()
    let jsonString = try ReportFormatter.json(report)
    let data = Data(jsonString.utf8)
    let decoded = try JSONDecoder().decode(DoctorReport.self, from: data)
    #expect(decoded.sagePath == report.sagePath)
    #expect(decoded.schemaVersion == 1)
    #expect(decoded.versionMajorMinor == "9.5")
    #expect(decoded.versionStanding == .supported)
    #expect(decoded.checks.count == report.checks.count)
    #expect(decoded.overallOK == true)
  }

  @Test("JSON keeps slashes unescaped for readable paths")
  func jsonUnescapedSlashes() throws {
    let jsonString = try ReportFormatter.json(sampleReport())
    #expect(jsonString.contains("/usr/local/bin/sage"))
    #expect(!jsonString.contains("\\/"))
  }
}
