import SwiftUI

@main
struct CasetteApp: App {
    /// Quit-time worker teardown (see AppDelegate).
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Casette") {
            RootView()
        }
        .defaultSize(width: 1040, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            SidebarToggleCommands()
            SageCommands()
        }
    }
}
