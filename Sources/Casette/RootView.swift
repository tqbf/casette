import SwiftUI

/// The V1.1 three-region shell: session tape (center) over the input pane,
/// with the tabbed sidebar as a trailing inspector (the modern macOS idiom
/// for a right-side utility panel — full height, system resize handle,
/// toolbar toggle).
///
/// Focus model: the input pane owns keyboard focus by default; the root owns
/// the `@FocusState` so sidebar actions (and later ⌘L, V1.12) can hand focus
/// back to the input.
struct RootView: View {
    @State private var model = ShellModel(
        rows: PlaceholderData.rows,
        symbols: PlaceholderData.symbols
    )
    @State private var isSidebarPresented = true
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            SessionTapeView(model: model)
            Divider()
            InputPaneView(model: model, isFocused: $isInputFocused)
        }
        .frame(minWidth: Theme.windowMinWidth, minHeight: Theme.windowMinHeight)
        .inspector(isPresented: $isSidebarPresented) {
            SidebarView(model: model, focusInput: focusInput)
                .inspectorColumnWidth(
                    min: Theme.sidebarMinWidth,
                    ideal: Theme.sidebarIdealWidth,
                    max: Theme.sidebarMaxWidth
                )
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(
                    "Hide or Show Sidebar",
                    systemImage: "sidebar.trailing",
                    action: toggleSidebar
                )
                .help("Hide or show the sidebar (⌘B)")
            }
        }
        .focusedSceneValue(\.isSidebarPresented, $isSidebarPresented)
        .defaultFocus($isInputFocused, true)
        .task { isInputFocused = true }
    }

    private func toggleSidebar() {
        isSidebarPresented.toggle()
    }

    private func focusInput() {
        isInputFocused = true
    }
}

#Preview {
    RootView()
        .frame(width: 1040, height: 720)
}
