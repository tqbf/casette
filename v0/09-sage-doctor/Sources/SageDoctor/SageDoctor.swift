import Foundation

/// Runs the full diagnostic: discover Sage, detect its version, then drive the
/// canonical worker end-to-end through every check, producing a `DoctorReport`.
///
/// Each check is **independent, timed, and degrades to an actionable failure
/// message** rather than throwing a stack trace at the user. A worker that won't
/// boot fails the boot check and skips the worker-dependent checks; it never
/// crashes the doctor.
public struct SageDoctor: Sendable {
  public let workerPath: String

  /// - Parameter workerPath: the canonical worker.py. Defaults to the repo's
  ///   `v0/01-worker-protocol/worker.py` resolved relative to this source file,
  ///   with an env override (`CASETTE_WORKER`) for tests/relocation.
  public init(workerPath: String = SageDoctor.defaultWorkerPath()) {
    self.workerPath = workerPath
  }

  /// Runs discovery + version + all checks and returns the report.
  public func run(override: String? = nil, storedPath: String? = nil) -> DoctorReport {
    let discovery = SageDiscovery().discover(override: override, storedPath: storedPath)
    let reportCandidates = discovery.candidates.map { candidate in
      ReportCandidate(
        path: candidate.path,
        source: candidate.source.rawValue,
        exists: candidate.exists,
        selected: candidate.path == discovery.selected?.path)
    }

    // An explicit `--sage PATH` that does not exist must fail LOUDLY, not fall
    // through to a discovered Sage: the user asked for that specific binary.
    if let override, !(SageDiscovery.defaultExistenceCheck(
      (override as NSString).expandingTildeInPath)) {
      return DoctorReport(
        sagePath: nil,
        candidates: reportCandidates,
        versionRaw: nil,
        versionMajorMinor: nil,
        versionStanding: .unknown,
        checks: [
          CheckResult(
            id: "discovery", name: "Discovery", status: .fail, durationMillis: 0,
            detail: "the --sage path you gave (\(override)) does not exist or is "
              + "not executable. Check the path, or omit --sage to auto-discover"),
        ],
        overallOK: false)
    }

    guard let selected = discovery.selected else {
      return DoctorReport(
        sagePath: nil,
        candidates: reportCandidates,
        versionRaw: nil,
        versionMajorMinor: nil,
        versionStanding: .unknown,
        checks: [
          CheckResult(
            id: "discovery", name: "Discovery", status: .fail, durationMillis: 0,
            detail: "no Sage binary found. Install Sage (brew install sage) or "
              + "point the doctor at one with --sage /path/to/sage, then --use it"),
        ],
        overallOK: false)
    }

    let version = detectVersion(sagePath: selected.path)
    let standing = SageVersionPolicy.standing(for: version.parsed)

    var checks: [CheckResult] = []
    checks.append(makeVersionCheck(version: version, standing: standing))

    // Drive the worker through the end-to-end checks. If boot fails, the rest
    // are skipped (not failed) — they have no worker to run against.
    let workerChecks = runWorkerChecks(sagePath: selected.path)
    checks.append(contentsOf: workerChecks)

    let overallOK = checks.allSatisfy { $0.status != .fail }
    return DoctorReport(
      sagePath: selected.path,
      candidates: reportCandidates,
      versionRaw: version.raw,
      versionMajorMinor: version.parsed.map { "\($0.major).\($0.minor)" },
      versionStanding: standing,
      checks: checks,
      overallOK: overallOK)
  }

  // MARK: - Version

  struct VersionDetection {
    let raw: String?
    let parsed: SageVersion?
    let detail: String
  }

  func detectVersion(sagePath: String) -> VersionDetection {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: sagePath)
    process.arguments = ["--version"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
      try process.run()
    } catch {
      return VersionDetection(
        raw: nil, parsed: nil,
        detail: "could not run `\(sagePath) --version`: \(error.localizedDescription)")
    }
    // Bound the call so a hung "sage --version" can't wedge the doctor.
    let deadline = Date().addingTimeInterval(60)
    while process.isRunning, Date() < deadline {
      usleep(20_000)
    }
    if process.isRunning {
      process.terminate()
      return VersionDetection(
        raw: nil, parsed: nil,
        detail: "`\(sagePath) --version` did not return within 60s (is this Sage?)")
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(decoding: data, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !output.isEmpty else {
      return VersionDetection(
        raw: nil, parsed: nil,
        detail: "`\(sagePath) --version` produced no output (not a Sage binary?)")
    }
    let parsed = SageVersion.parse(output)
    return VersionDetection(
      raw: output, parsed: parsed,
      detail: parsed == nil ? "no MAJOR.MINOR found in: \(output)" : output)
  }

  private func makeVersionCheck(
    version: VersionDetection,
    standing: VersionStanding
  ) -> CheckResult {
    switch standing {
    case .supported:
      return CheckResult(
        id: "version", name: "Sage version", status: .ok, durationMillis: 0,
        detail: version.parsed.map { "\($0.major).\($0.minor)" } ?? "")
    case .belowFloor:
      let shown = version.parsed.map { "\($0.major).\($0.minor)" } ?? "?"
      return CheckResult(
        id: "version", name: "Sage version", status: .ok, durationMillis: 0,
        detail: "\(shown) is below the tested floor 9.5 — may work, untested")
    case .unknown:
      return CheckResult(
        id: "version", name: "Sage version", status: .fail, durationMillis: 0,
        detail: version.detail)
    }
  }

  // MARK: - Worker checks

  /// Boots one worker and runs the worker-dependent checks against it (boot,
  /// eval, state, latex, plot), then runs interrupt + restart as their own
  /// worker lifecycles. Guarantees the worker is killed before returning.
  private func runWorkerChecks(sagePath: String) -> [CheckResult] {
    let runner = WorkerCheckRunner(sagePath: sagePath, workerPath: workerPath)
    return runner.runAll()
  }

  // MARK: - Worker path resolution

  public static func defaultWorkerPath() -> String {
    if let override = ProcessInfo.processInfo.environment["CASETTE_WORKER"],
      !override.isEmpty {
      return override
    }
    // This file lives at v0/09-sage-doctor/Sources/SageDoctor/SageDoctor.swift.
    // The canonical worker is at v0/01-worker-protocol/worker.py — four dirs up
    // then across. Resolve relative to #filePath so it works from any cwd.
    let thisFile = URL(fileURLWithPath: #filePath)
    let repoV0 = thisFile
      .deletingLastPathComponent()  // SageDoctor/
      .deletingLastPathComponent()  // Sources/
      .deletingLastPathComponent()  // 09-sage-doctor/
      .deletingLastPathComponent()  // v0/
    return repoV0
      .appendingPathComponent("01-worker-protocol/worker.py")
      .path
  }
}
