import SwiftUI

/// The tabbed right sidebar: a segmented tab strip (Xcode-inspector style)
/// over per-tab content — Symbols / History / Inspector / Actions (V1.6).
/// Tab selection lives on the model so sidebar flows can switch tabs
/// (Symbols → Inspect lands on the Inspector).
struct SidebarView: View {
    @Bindable var model: ShellModel
    /// Hands keyboard focus back to the input pane after a sidebar action
    /// that targets the input (insert into draft).
    var focusInput: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker("Sidebar Tab", selection: $model.sidebarTab) {
                ForEach(SidebarTab.allCases) { tab in
                    Image(systemName: tab.systemImage)
                        .accessibilityLabel(tab.title)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(Theme.sidebarSectionPadding)

            Divider()

            switch model.sidebarTab {
            case .symbols:
                SymbolsTabView(model: model, focusInput: focusInput)
            case .history:
                HistoryTabView(model: model, focusInput: focusInput)
            case .inspector:
                InspectorTabView(row: model.selectedRow)
            case .actions:
                ActionsTabView(model: model, row: model.selectedRow, focusInput: focusInput)
            }
        }
    }
}

#Preview {
    SidebarView(
        model: ShellModel(rows: PlaceholderData.rows, symbols: PlaceholderData.symbols),
        focusInput: {}
    )
    .frame(width: 280, height: 600)
}
