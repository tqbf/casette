import Foundation
import Observation
import os

/// The view-facing model behind the Sage Doctor sheet: the live discovery
/// view (candidates + selection + stored path), the manual override, the
/// check run, and the copyable report.
///
/// Config is the app's ONE config store (`sage-doctor.json` via
/// `SageConfigStore` — the same file the kernel's transport factory reads at
/// every boot/restart), so "Use This Sage" + `reconnect` is all it takes for
/// the running app to switch binaries without a relaunch.
///
/// Override policy (PROBLEMS.md, the V0.9 fail-loud lesson): a manual path
/// that doesn't exist NEVER falls through — "Use This Sage" refuses with a
/// visible message, and a check run against it fails the `discovery` check.
@MainActor
@Observable
final class DoctorModel {
    /// The manual override path (the text field / file picker). While
    /// non-empty it is the discovery override — highest priority, fail-loud.
    var manualPath = "" {
        didSet {
            guard manualPath != oldValue else { return }
            useIssue = nil  // the message described a path that changed
        }
    }
    /// The path stored in sage-doctor.json, if any.
    private(set) var storedPath: String?
    /// Every candidate the discovery search considered, priority order.
    private(set) var candidates: [ReportCandidate] = []
    /// The binary discovery would select right now (what the kernel's
    /// factory will use at the next boot/restart).
    private(set) var selectedPath: String?
    /// The `--version` probe of the selected binary (async; nil while
    /// probing or with no selection).
    private(set) var versionDetection: SageVersionDetection?
    private(set) var versionStanding: VersionStanding?
    /// Check results, appended live while a run is in flight.
    private(set) var checks: [CheckResult] = []
    private(set) var isRunning = false
    /// The completed report — what Copy Report copies.
    private(set) var lastReport: DoctorReport?
    /// The fail-loud message when "Use This Sage" refuses a missing path.
    private(set) var useIssue: String?
    /// Asks the app to restart its kernel (re-running discovery, which now
    /// sees the new stored path) — wired to `ShellModel.restartKernel` by the
    /// hosting view. The "connect without relaunching" hook.
    var reconnect: () -> Void = {}

    private let configStore: SageConfigStore
    private let runner: SageDoctorRunner
    private let logger = Logger(subsystem: "org.sockpuppet.casette", category: "doctor")
    /// Guards against a stale run's results landing after a newer run/stop.
    @ObservationIgnored private var runGeneration = 0
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var versionTask: Task<Void, Never>?

    init(
        configStore: SageConfigStore = SageConfigStore(),
        runner: SageDoctorRunner = SageDoctorRunner()
    ) {
        self.configStore = configStore
        self.runner = runner
    }

    // MARK: - Derived state

    /// The override the runner/discovery sees: the trimmed manual path, or
    /// nil when the field is empty (auto-discovery).
    var manualOverride: String? {
        let trimmed = manualPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The inline fail-loud message under the override field: non-nil exactly
    /// when a manual path is set and does NOT point at an executable file.
    var manualPathIssue: String? {
        guard let manualOverride else { return nil }
        let expanded = (manualOverride as NSString).expandingTildeInPath
        guard !runner.existenceCheck(expanded) else { return nil }
        return "No executable file at \(manualOverride) — check the path; it will never be used silently."
    }

    var canUseManualPath: Bool {
        manualOverride != nil && !isRunning
    }

    var canForgetStoredPath: Bool {
        storedPath != nil && !isRunning
    }

    var canRunChecks: Bool { !isRunning }

    /// The copyable diagnostics: the human report plus the `--json` contract,
    /// one paste = one complete bug report.
    var reportText: String? {
        guard let lastReport else { return nil }
        let human = ReportFormatter.humanReadable(lastReport)
        guard let json = try? ReportFormatter.json(lastReport) else { return human }
        return human + "\n\n--- JSON report (sage-doctor contract) ---\n" + json
    }

    // MARK: - Discovery view

    /// Re-runs the (cheap, pure) discovery search and the async version probe.
    /// Called when the sheet opens and after any config change — NOT per
    /// keystroke (discovery shells out to `which`).
    func refresh() {
        storedPath = configStore.storedPath()
        let result = runner.discovery.discover(
            override: manualOverride, storedPath: storedPath)
        candidates = SageDoctorRunner.reportCandidates(result)
        selectedPath = result.selected?.path
        probeVersion(of: result.selected?.path)
    }

    private func probeVersion(of path: String?) {
        versionTask?.cancel()
        versionDetection = nil
        versionStanding = nil
        guard let path else { return }
        versionTask = Task { [detect = runner.detectVersion] in
            let detection = await detect(path)
            guard !Task.isCancelled else { return }
            versionDetection = detection
            versionStanding = SageVersionPolicy.standing(for: detection.parsed)
        }
    }

    // MARK: - Check run

    /// Runs the full doctor (discovery → version → live worker checks) against
    /// the current override/stored configuration. Results append live; the
    /// completed report replaces the discovery view with the run's truth.
    func runChecks() {
        guard !isRunning else { return }
        isRunning = true
        checks = []
        lastReport = nil
        useIssue = nil
        runGeneration += 1
        let generation = runGeneration
        let override = manualOverride
        let stored = storedPath
        runTask = Task { [runner] in
            let report = await runner.run(override: override, storedPath: stored) { [weak self] check in
                guard let self, runGeneration == generation else { return }
                checks.append(check)
            }
            guard runGeneration == generation else { return }
            adopt(report)
            isRunning = false
        }
    }

    /// Cooperatively stops an in-flight run. The runner marks the remaining
    /// checks `skipped` and still tears its workers down (no leaks); the
    /// partial report lands normally.
    func stopChecks() {
        runTask?.cancel()
    }

    private func adopt(_ report: DoctorReport) {
        lastReport = report
        checks = report.checks
        candidates = report.candidates
        selectedPath = report.sagePath
        if let raw = report.versionRaw {
            versionDetection = SageVersionDetection(
                raw: raw, parsed: SageVersion.parse(raw), detail: raw)
            versionStanding = report.versionStanding
        }
        logger.notice("doctor run finished: overallOK=\(report.overallOK)")
    }

    // MARK: - Config actions

    /// "Use This Sage": persists the manual path to sage-doctor.json and asks
    /// the app to reconnect with it. A path that doesn't exist FAILS LOUD —
    /// visible message, nothing stored, no reconnect (never fall through).
    func useManualPath() {
        guard let manualOverride else { return }
        if let issue = manualPathIssue {
            useIssue = issue
            logger.error("refused to store a non-existent Sage path: \(manualOverride, privacy: .public)")
            return
        }
        let expanded = (manualOverride as NSString).expandingTildeInPath
        do {
            try configStore.store(sagePath: expanded)
        } catch {
            useIssue = "Couldn't save the path: \(error.localizedDescription)"
            return
        }
        useIssue = nil
        manualPath = ""  // the stored path now carries it (source: Saved)
        refresh()
        reconnect()
    }

    /// "Forget": clears the stored path; the next boot/restart re-discovers.
    func forgetStoredPath() {
        do {
            try configStore.forget()
        } catch {
            useIssue = "Couldn't clear the saved path: \(error.localizedDescription)"
            return
        }
        useIssue = nil
        refresh()
    }

    /// Copies the human report + JSON contract for a bug report.
    func copyReport() {
        guard let reportText else { return }
        Pasteboard.copy(reportText)
    }
}
