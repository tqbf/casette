import Foundation

/// Quit-time safety net for worker processes.
///
/// The worker runs in its OWN session/process group (so we can group-kill it
/// without orphans — PROBLEMS.md), which also means it does NOT die with the
/// app automatically. Every spawned `SageKernel` registers here; on normal app
/// termination (`applicationWillTerminate`) `killAll()` group-kills anything
/// still alive so no Sage worker outlives Casette.
///
/// Kernels unregister themselves in `hardKill()`, so a restarted/replaced
/// generation never lingers in the registry.
final class KernelReaper: @unchecked Sendable {
    static let shared = KernelReaper()

    private let lock = NSLock()
    private var kernels: [ObjectIdentifier: SageKernel] = [:]

    func register(_ kernel: SageKernel) {
        lock.lock()
        defer { lock.unlock() }
        kernels[ObjectIdentifier(kernel)] = kernel
    }

    func unregister(_ kernel: SageKernel) {
        lock.lock()
        defer { lock.unlock() }
        kernels[ObjectIdentifier(kernel)] = nil
    }

    /// Group-kills every registered kernel. Synchronous and signal-only, so
    /// it is safe to call from `applicationWillTerminate`.
    func killAll() {
        lock.lock()
        let snapshot = Array(kernels.values)
        lock.unlock()
        // hardKill() unregisters; iterate a snapshot so we never mutate
        // under our own lock.
        for kernel in snapshot {
            kernel.hardKill()
        }
    }
}
