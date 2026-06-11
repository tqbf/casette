import Foundation
import Testing
@testable import Casette

@Suite("Kernel setup (worker locator + discovery wiring)")
struct KernelSetupTests {
    @Test("an explicit CASETTE_WORKER_PATH that doesn't exist fails LOUD")
    func workerOverrideMissingFailsLoud() {
        // The PROBLEMS.md override lesson: never fall through to the bundle.
        #expect(throws: KernelSetupError.workerOverrideMissing(path: "/no/such/worker.py")) {
            try WorkerScriptLocator.locate(
                environment: ["CASETTE_WORKER_PATH": "/no/such/worker.py"],
                bundledWorker: URL(fileURLWithPath: "/also/irrelevant.py"))
        }
    }

    @Test("an existing override wins over the bundled worker")
    func workerOverrideWins() throws {
        let temp = FileManager.default.temporaryDirectory
            .appending(path: "casette-test-worker-\(UUID().uuidString).py")
        try Data("# worker\n".utf8).write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }

        let located = try WorkerScriptLocator.locate(
            environment: ["CASETTE_WORKER_PATH": temp.path],
            bundledWorker: nil)
        #expect(located == temp.path)
    }

    @Test("no override and no bundled worker → an honest 'broken build' error")
    func missingBundledWorkerIsHonest() {
        #expect(throws: KernelSetupError.workerNotBundled) {
            try WorkerScriptLocator.locate(environment: [:], bundledWorker: nil)
        }
        #expect(
            KernelSetupError.workerNotBundled.description.contains("worker.py"))
    }

    @Test("discovery priority: the stored config path beats well-known paths")
    func storedPathBeatsKnownPaths() {
        // Everything "exists" — the stored path must still be selected first.
        let discovery = SageDiscovery(
            existenceCheck: { _ in true },
            pathLookup: { "/from/path/sage" },
            appBundleGlob: { [] })
        let result = discovery.discover(storedPath: "/stored/sage")
        #expect(result.selected?.path == "/stored/sage")
        #expect(result.selected?.source == .stored)
        // And the full searched set is reported (the honest-discovery rule).
        #expect(result.candidates.count > 2)
    }

    @Test("the no-Sage setup error names the search and the config escape hatch")
    func sageNotFoundMessageIsActionable() {
        let message = KernelSetupError.sageNotFound(searched: ["/x"]).description
        #expect(message.contains("Homebrew"))
        #expect(message.contains("sage-doctor.json"))
    }
}
