import Foundation
import Testing
@testable import Casette

@MainActor
@Suite("Sage Doctor model")
struct DoctorModelTests {
    @Test("refresh discovers the selected Sage and probes its version")
    func refreshDiscoversAndProbesVersion() async throws {
        let path = "/tmp/fake-sage"
        let model = DoctorModel(
            configStore: Self.store(),
            runner: Self.runner(existingPaths: [path], pathLookup: path)
        )

        model.refresh()

        #expect(await eventually { @MainActor in model.selectedPath == path })
        #expect(model.versionDetection?.displayVersion == "9.5")
        #expect(model.versionStanding == .supported)
    }

    @Test("Use This Sage stores an executable manual path and asks the app to reconnect")
    func useManualPathStoresAndReconnects() throws {
        let path = "/tmp/manual-sage"
        let store = Self.store()
        let model = DoctorModel(
            configStore: store,
            runner: Self.runner(existingPaths: [path])
        )
        var reconnects = 0
        model.reconnect = { reconnects += 1 }
        model.manualPath = path

        model.useManualPath()

        #expect(store.storedPath() == path)
        #expect(reconnects == 1)
        #expect(model.useIssue == nil)
    }

    @Test("Use This Sage refuses a missing manual path without reconnecting")
    func useManualPathRefusesMissingPath() {
        let store = Self.store()
        let model = DoctorModel(
            configStore: store,
            runner: Self.runner(existingPaths: [])
        )
        var reconnects = 0
        model.reconnect = { reconnects += 1 }
        model.manualPath = "/tmp/missing-sage"

        model.useManualPath()

        #expect(store.storedPath() == nil)
        #expect(reconnects == 0)
        #expect(model.useIssue?.contains("No executable file") == true)
    }

    @Test("runChecks appends live checks and keeps a copyable report")
    func runChecksBuildsReport() async {
        let path = "/tmp/fake-sage"
        let model = DoctorModel(
            configStore: Self.store(),
            runner: Self.runner(existingPaths: [path], pathLookup: path)
        )

        model.runChecks()

        #expect(await eventually { @MainActor in !model.isRunning })
        #expect(model.checks.map(\.id) == ["version", "eval"])
        #expect(model.lastReport?.overallOK == true)
        #expect(model.reportText?.contains("--- JSON report") == true)
    }

    private static func store() -> SageConfigStore {
        SageConfigStore(environment: [
            SageConfigStore.directoryOverrideKey:
                URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .path,
        ])
    }

    private static func runner(
        existingPaths: Set<String>,
        pathLookup: String? = nil
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
                id: "eval",
                name: "Eval test",
                status: .ok,
                durationMillis: 12,
                detail: "2 + 2 = 4"
            )
            await onCheck(check)
            return [check]
        }
        return runner
    }
}
