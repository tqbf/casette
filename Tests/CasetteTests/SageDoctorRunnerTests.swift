import Foundation
import Testing
@testable import Casette

@Suite("Sage Doctor runner")
struct SageDoctorRunnerTests {
    @Test("an explicit missing override fails loudly instead of falling through")
    func missingOverrideFailsLoudly() async {
        let fallback = "/usr/local/bin/sage"
        let runner = Self.runner(existingPaths: [fallback], pathLookup: fallback)

        let report = await runner.run(override: "/tmp/not-sage")

        #expect(report.sagePath == nil)
        #expect(report.overallOK == false)
        #expect(report.checks.map(\.id) == ["discovery"])
        #expect(report.checks.first?.detail.contains("does not exist") == true)
    }

    @Test("selected Sage produces version and worker checks in report order")
    func selectedSageRunsChecks() async {
        let path = "/usr/local/bin/sage"
        let runner = Self.runner(existingPaths: [path], pathLookup: path)
        var liveIDs: [String] = []

        let report = await runner.run { check in
            liveIDs.append(check.id)
        }

        #expect(report.sagePath == path)
        #expect(report.versionMajorMinor == "9.5")
        #expect(report.overallOK == true)
        #expect(report.checks.map(\.id) == ["version", "worker_boot"])
        #expect(liveIDs == ["version", "worker_boot"])
    }

    private static func runner(
        existingPaths: Set<String>,
        pathLookup: String?
    ) -> SageDoctorRunner {
        var runner = SageDoctorRunner()
        runner.discovery = SageDiscovery(
            existenceCheck: { existingPaths.contains($0) },
            pathLookup: { pathLookup },
            appBundleGlob: { [] }
        )
        runner.existenceCheck = { existingPaths.contains($0) }
        runner.detectVersion = { _ in
            SageVersionDetection(
                raw: "SageMath version 9.5, Release Date: 2022-01-30",
                parsed: SageVersion(
                    major: 9,
                    minor: 5,
                    raw: "SageMath version 9.5, Release Date: 2022-01-30"
                ),
                detail: "SageMath version 9.5, Release Date: 2022-01-30"
            )
        }
        runner.runChecks = { _, onCheck in
            let check = CheckResult(
                id: "worker_boot",
                name: "Worker boot",
                status: .ok,
                durationMillis: 25,
                detail: "ready"
            )
            await onCheck(check)
            return [check]
        }
        return runner
    }
}

@Suite(
    "Sage Doctor integration (real Sage)",
    .serialized,
    .enabled(if: SageTestEnvironment.available))
struct SageDoctorIntegrationTests {
    @Test("real Sage passes the full in-app Doctor check list", .timeLimit(.minutes(5)))
    func realSagePassesFullDoctorChecks() async throws {
        let runner = DoctorCheckRunner(
            sagePath: try #require(SageTestEnvironment.sagePath),
            resolveWorker: { SageTestEnvironment.workerPath }
        )

        let checks = await runner.runAll()

        #expect(checks.map(\.id) == [
            "worker_boot",
            "eval",
            "state",
            "latex",
            "plot",
            "interrupt",
            "restart",
        ])
        #expect(checks.allSatisfy { $0.status == .ok })
    }
}
