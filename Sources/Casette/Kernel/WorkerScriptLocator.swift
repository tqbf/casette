import Foundation

/// Resolves the path of the Sage worker script the kernel runs.
///
/// The canonical worker is `v0/01-worker-protocol/worker.py`; build.sh copies
/// it byte-identically into the app bundle (`Contents/Resources/worker.py`),
/// so the normal path is the bundle resource. `CASETTE_WORKER_PATH` overrides
/// it for tests and dev runs of the bare binary — and, per the PROBLEMS.md
/// override lesson, an explicit override that doesn't exist fails LOUD rather
/// than falling through to the bundle.
enum WorkerScriptLocator {
    static let overrideKey = "CASETTE_WORKER_PATH"

    static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundledWorker: URL? = Bundle.main.url(forResource: "worker", withExtension: "py")
    ) throws -> String {
        if let override = environment[overrideKey], !override.isEmpty {
            guard FileManager.default.fileExists(atPath: override) else {
                throw KernelSetupError.workerOverrideMissing(path: override)
            }
            return override
        }
        if let bundledWorker, FileManager.default.fileExists(atPath: bundledWorker.path) {
            return bundledWorker.path
        }
        throw KernelSetupError.workerNotBundled
    }
}
