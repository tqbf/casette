import SwiftUI

extension FocusedValues {
    /// The focused window's sidebar-visibility binding, published by
    /// `RootView` so `SidebarToggleCommands` (the ⌘B menu item) can reach it.
    @Entry var isSidebarPresented: Binding<Bool>?

    /// The focused window's shell model, published by `RootView` so
    /// `SageCommands` (Restart Sage / Interrupt Evaluation) can reach the
    /// kernel and read its state for menu enablement.
    @Entry var shellModel: ShellModel?
}
