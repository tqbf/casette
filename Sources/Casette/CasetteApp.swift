import SwiftUI

@main
struct CasetteApp: App {
    var body: some Scene {
        WindowGroup("Casette") {
            RootView()
        }
        .defaultSize(width: 1040, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            SidebarToggleCommands()
        }
    }
}
