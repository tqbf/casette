import SwiftUI

/// The tabbed right sidebar: a segmented tab strip (Xcode-inspector style)
/// over per-tab content. Tabs are Symbols / History / Inspector / Actions
/// (INITIAL.md V1.1); each tab's real behavior lands in V1.6.
struct SidebarView: View {
    var model: ShellModel
    /// Hands keyboard focus back to the input pane after a sidebar action
    /// (e.g. History → Insert into Input).
    var focusInput: () -> Void

    @State private var selectedTab: SidebarTab = .symbols

    var body: some View {
        VStack(spacing: 0) {
            Picker("Sidebar Tab", selection: $selectedTab) {
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

            switch selectedTab {
            case .symbols:
                SymbolsTabView(symbols: model.symbols.entries)
            case .history:
                HistoryTabView(model: model, focusInput: focusInput)
            case .inspector:
                InspectorTabView(row: model.selectedRow)
            case .actions:
                ActionsTabView(row: model.selectedRow)
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
