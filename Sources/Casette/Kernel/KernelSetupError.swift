import Foundation

/// Setup failures that prevent a kernel from existing at all — no Sage found,
/// no worker script. Each carries a clear, actionable, user-facing message
/// (the V1.3 "honest error surface"; the full Doctor UI is V1.10).
enum KernelSetupError: Error, CustomStringConvertible, Equatable {
    /// The discovery search found no existing Sage binary.
    case sageNotFound(searched: [String])
    /// An explicit `CASETTE_WORKER_PATH` override points at a missing file.
    /// An explicit override must fail LOUD, never fall through (PROBLEMS.md).
    case workerOverrideMissing(path: String)
    /// The app bundle carries no worker.py — a broken build.
    case workerNotBundled

    var description: String {
        switch self {
        case .sageNotFound:
            """
            Couldn't find SageMath on this Mac. Casette searched Homebrew, \
            /usr/local, /Applications (SageMath apps), conda, and your PATH. \
            Install Sage, or store its path in \
            ~/Library/Application Support/Casette/sage-doctor.json.
            """
        case .workerOverrideMissing(let path):
            "CASETTE_WORKER_PATH points at \(path), which doesn't exist."
        case .workerNotBundled:
            "The Sage worker script (worker.py) is missing from the app bundle — this build is broken."
        }
    }
}
