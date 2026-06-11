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
    @State private var model = ShellModel()
    @State private var isSidebarPresented = true
    @FocusState private var isInputFocused: Bool

    /// Previews pass false so opening a canvas never spawns a Sage process.
    var connectsKernel = true

    var body: some View {
        VStack(spacing: 0) {
            SessionTapeView(model: model)
            Divider()
            // The kernel recovery banner: shown only when the kernel is
            // unavailable for a reason the user should see. Plain structural
            // conditional — no transition (SWIFTUI-RULES §1.1 is about
            // animated insert/remove).
            if let issue = model.kernelIssue {
                KernelIssueBanner(message: issue) { model.restartKernel() }
                Divider()
            }
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
        .focusedSceneValue(\.shellModel, model)
        .defaultFocus($isInputFocused, true)
        .task {
            isInputFocused = true
            if connectsKernel {
                model.connectKernel()
            }
        }
    }

    private func toggleSidebar() {
        isSidebarPresented.toggle()
    }

    private func focusInput() {
        isInputFocused = true
    }
}

#Preview {
    RootView(connectsKernel: false)
        .frame(width: 1040, height: 720)
}
