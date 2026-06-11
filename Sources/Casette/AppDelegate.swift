import AppKit

/// AppKit delegate for lifecycle hooks SwiftUI doesn't expose. The one job:
/// on termination, group-kill any live Sage worker. The worker runs in its
/// own session (so interrupt/kill semantics work without orphans), which
/// means it would NOT die with the app on its own — without this, quitting
/// Casette would leak a running Sage process.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        KernelReaper.shared.killAll()
    }
}
