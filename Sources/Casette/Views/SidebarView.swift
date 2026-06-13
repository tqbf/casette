import SwiftUI

/// The tabbed right sidebar: a segmented tab strip (Xcode-inspector style)
/// over per-tab content — Symbols / History / Inspector / Actions (V1.6).
/// Tab selection lives on the model so sidebar flows can switch tabs
/// (Symbols → Inspect lands on the Inspector).
struct SidebarView: View {
    @Bindable var model: ShellModel
    @Binding var topPaneHeight: Double
    /// Hands keyboard focus back to the input pane after a sidebar action
    /// that targets the input (insert into draft).
    var focusInput: () -> Void

    var body: some View {
        PersistentVerticalSplitView(
            persistedDimension: $topPaneHeight,
            persistedPane: .top,
            minimumTopHeight: Theme.sidebarTabStripMinHeight,
            minimumBottomHeight: Theme.sidebarContentMinHeight
        ) {
            SidebarTabStripView(selection: $model.sidebarTab)
        } bottom: {
            switch model.sidebarTab {
            case .symbols:
                SymbolsTabView(model: model, focusInput: focusInput)
            case .history:
                HistoryTabView(model: model, focusInput: focusInput)
            case .inspector:
                InspectorTabView(
                    row: model.selectedRow,
                    provenanceMark: model.selectedRow.flatMap { model.provenanceMark(for: $0) })
            case .actions:
                ActionsTabView(model: model, row: model.selectedRow, focusInput: focusInput)
            }
        }
    }
}

#Preview {
    SidebarView(
        model: ShellModel(rows: PlaceholderData.rows, symbols: PlaceholderData.symbols),
        topPaneHeight: .constant(UILayout.defaultSidebarTopPaneHeight),
        focusInput: {}
    )
    .frame(width: 280, height: 600)
}
