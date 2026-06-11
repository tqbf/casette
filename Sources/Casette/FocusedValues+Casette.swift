import SwiftUI

extension FocusedValues {
    /// The focused window's sidebar-visibility binding, published by
    /// `RootView` so `SidebarToggleCommands` (the ⌘B menu item) can reach it.
    @Entry var isSidebarPresented: Binding<Bool>?
}
