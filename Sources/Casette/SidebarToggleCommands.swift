import SwiftUI

/// View-menu command for the right sidebar, wired to the focused window's
/// state via `FocusedValues`. Carrying the shortcut here (not on the toolbar
/// button) gives the standard macOS affordance: a discoverable menu item
/// with a visible ⌘B, disabled when no Casette window is focused.
struct SidebarToggleCommands: Commands {
    @FocusedBinding(\.isSidebarPresented) private var isSidebarPresented: Bool?

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button(isSidebarPresented == false ? "Show Sidebar" : "Hide Sidebar") {
                isSidebarPresented?.toggle()
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(isSidebarPresented == nil)
        }
    }
}
