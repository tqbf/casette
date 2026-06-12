import Foundation

/// Assembles the full `DoctorReport` — discovery, version + floor verdict, and
/// the live worker check list — the in-app port of v0/09's `SageDoctor.run`,
/// re-pointed at the app's single sources of truth:
///
///   * discovery/config: the SAME `SageDiscovery` + `SageConfigStore` the
///     kernel's `discoveringTransportFactory` uses (lifted at V1.3);
///   * processes: the checks run through `DoctorCheckRunner` over the app's
///     `SageKernel` transport seam (never v0/09's `WorkerProcess`).
///
/// Policy preserved verbatim from plans/SAGE-DOCTOR.md:
///   * an explicit override that does not exist **fails LOUDLY** as a
///     `discovery` FAIL — it never falls through to a discovered Sage;
///   * no Sage at all → a `discovery` FAIL with the actionable install hint;
///   * below-floor versions warn (`ok` + note), unparseable versions FAIL the
///     version check — the worker checks are the real fitness test.
///
/// Every dependency is injected so the whole flow is testable over fakes; the
/// defaults are the real thing.
struct SageDoctorRunner: Sendable {
    var discovery = SageDiscovery()
    var existenceCheck: SageDiscovery.ExistenceCheck = SageDiscovery.defaultExistenceCheck
    var detectVersion: @Sendable (String) async -> SageVersionDetection = { path in
        await SageVersionDetector.detect(sagePath: path)
    }
    /// Runs the worker check list for a selected binary, reporting each check
    /// as it completes. Default: `DoctorCheckRunner` over real `SageKernel`s.
    var runChecks: @Sendable (
        _ sagePath: String,
        _ onCheck: @MainActor @Sendable (CheckResult) -> Void
    ) async -> [CheckResult] = { sagePath, onCheck in
        await DoctorCheckRunner(sagePath: sagePath).runAll(onCheck: onCheck)
    }

    /// Runs discovery + version + all checks and returns the report. Each
    /// check (including the version check and a discovery failure) is also
    /// reported through `onCheck` as it lands, so the UI fills in live.
    func run(
        override: String? = nil,
        storedPath: String? = nil,
        onCheck: @MainActor @Sendable (CheckResult) -> Void = { _ in }
    ) async -> DoctorReport {
        let discovered = discovery.discover(override: override, storedPath: storedPath)
        let reportCandidates = Self.reportCandidates(discovered)

        // An explicit override that does not exist must fail LOUDLY, not fall
        // through to a discovered Sage: the user asked for that specific
        // binary (PROBLEMS.md, the V0.9 lesson).
        if let override,
           !existenceCheck((override as NSString).expandingTildeInPath) {
            let check = CheckResult(
                id: "discovery", name: "Discovery", status: .fail, durationMillis: 0,
                detail: "the Sage path you gave (\(override)) does not exist or is "
                    + "not executable. Check the path, or clear it to auto-discover")
            await onCheck(check)
            return DoctorReport(
                sagePath: nil,
                candidates: reportCandidates,
                versionRaw: nil,
                versionMajorMinor: nil,
                versionStanding: .unknown,
                checks: [check],
                overallOK: false)
        }

        guard let selected = discovered.selected else {
            let check = CheckResult(
                id: "discovery", name: "Discovery", status: .fail, durationMillis: 0,
                detail: "no Sage binary found. Install Sage (brew install sage) or "
                    + "choose a binary below, then Use This Sage")
            await onCheck(check)
            return DoctorReport(
                sagePath: nil,
                candidates: reportCandidates,
                versionRaw: nil,
                versionMajorMinor: nil,
                versionStanding: .unknown,
                checks: [check],
                overallOK: false)
        }

        let version = await detectVersion(selected.path)
        let standing = SageVersionPolicy.standing(for: version.parsed)

        var checks: [CheckResult] = []
        let versionCheck = Self.makeVersionCheck(version: version, standing: standing)
        checks.append(versionCheck)
        await onCheck(versionCheck)

        // Drive the worker through the end-to-end checks. If boot fails, the
        // rest are skipped (not failed) — they have no worker to run against.
        let workerChecks = await runChecks(selected.path, onCheck)
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

    // MARK: - Report pieces (the v0/09 mappings, verbatim)

    /// Maps a discovery result to the report's candidate rows (every searched
    /// path, priority order, with the `selected` flag).
    static func reportCandidates(_ result: DiscoveryResult) -> [ReportCandidate] {
        result.candidates.map { candidate in
            ReportCandidate(
                path: candidate.path,
                source: candidate.source.rawValue,
                exists: candidate.exists,
                selected: candidate.path == result.selected?.path)
        }
    }

    static func makeVersionCheck(
        version: SageVersionDetection,
        standing: VersionStanding
    ) -> CheckResult {
        switch standing {
        case .supported:
            CheckResult(
                id: "version", name: "Sage version", status: .ok, durationMillis: 0,
                detail: version.parsed.map { "\($0.major).\($0.minor)" } ?? "")
        case .belowFloor:
            CheckResult(
                id: "version", name: "Sage version", status: .ok, durationMillis: 0,
                detail: "\(version.parsed.map { "\($0.major).\($0.minor)" } ?? "?") "
                    + "is below the tested floor 9.5 — may work, untested")
        case .unknown:
            CheckResult(
                id: "version", name: "Sage version", status: .fail, durationMillis: 0,
                detail: version.detail)
        }
    }
}
