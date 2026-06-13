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
    @State private var doctorModel = DoctorModel()
    /// Sidebar visibility persists across launches (V1.9 "remember UI
    /// layout") — `@AppStorage` is the lightweight macOS idiom for it; the
    /// projected binding drives `.inspector` and the ⌘B command unchanged.
    @AppStorage(UILayout.sidebarVisibleKey) private var isSidebarPresented = true
    /// The selected sidebar tab, persisted as its raw value. The live value
    /// stays on `ShellModel` (sidebar flows switch tabs); this is just the
    /// durable copy, synced both ways below.
    @AppStorage(UILayout.sidebarTabKey) private var storedSidebarTab = SidebarTab.symbols.rawValue
    @AppStorage(UILayout.inputPaneHeightKey) private var inputPaneHeight =
        UILayout.defaultInputPaneHeight
    @AppStorage(UILayout.sidebarTopPaneHeightKey) private var sidebarTopPaneHeight =
        UILayout.defaultSidebarTopPaneHeight
    @State private var isConfirmingClearTape = false
    @FocusState private var isInputFocused: Bool

    /// Previews pass false so opening a canvas never spawns a Sage process —
    /// nor touches the real session file (restore is gated with the kernel).
    var connectsKernel = true

    var body: some View {
        @Bindable var model = model
        PersistentVerticalSplitView(
            persistedDimension: $inputPaneHeight,
            persistedPane: .bottom,
            minimumTopHeight: Theme.tapeMinHeight,
            minimumBottomHeight: Theme.inputMinHeight
        ) {
            SessionTapeRegionView(model: model)
        } bottom: {
            InputPaneView(model: model, isFocused: $isInputFocused)
        }
        .frame(minWidth: Theme.windowMinWidth, minHeight: Theme.windowMinHeight)
        .inspector(isPresented: $isSidebarPresented) {
            SidebarView(
                model: model,
                topPaneHeight: $sidebarTopPaneHeight,
                focusInput: focusInput
            )
                .inspectorColumnWidth(
                    min: Theme.sidebarMinWidth,
                    ideal: Theme.sidebarIdealWidth,
                    max: Theme.sidebarMaxWidth
                )
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Clear Tape", systemImage: "trash", action: confirmClearTape)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(!model.canClearTape)
                    .help("Clear all rows from the tape")

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
        .focusedSceneValue(\.confirmClearTape, confirmClearTape)
        .defaultFocus($isInputFocused, true)
        .sheet(isPresented: $model.isDoctorPresented) {
            DoctorSheetView(model: doctorModel, reconnect: model.restartKernel)
        }
        .confirmationDialog(
            "Clear Tape?",
            isPresented: $isConfirmingClearTape,
            titleVisibility: .visible
        ) {
            Button("Clear Tape", role: .destructive) {
                model.clearTape()
                focusInput()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every row from the tape. Sage variables stay available.")
        }
        .onChange(of: model.sidebarTab) {
            storedSidebarTab = model.sidebarTab.rawValue
        }
        .task {
            isInputFocused = true
            model.sidebarTab = UILayout.sidebarTab(fromStored: storedSidebarTab)
            if connectsKernel {
                // Restore BEFORE the kernel connects: the tape renders from
                // its persisted envelopes with Sage genuinely not involved,
                // so it's there even when discovery fails (the banner case).
                model.restoreLastSession(from: SessionStore())
                model.connectKernel()
            }
        }
    }

    private func toggleSidebar() {
        isSidebarPresented.toggle()
    }

    private func confirmClearTape() {
        isConfirmingClearTape = true
    }

    private func focusInput() {
        isInputFocused = true
    }
}

#Preview {
    RootView(connectsKernel: false)
        .frame(width: 1040, height: 720)
}
