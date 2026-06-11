import SwiftUI

/// Context-sensitive actions for the selected result, straight from the
/// envelope's per-kind `actions` list. Informational until V1.11 makes them
/// runnable follow-up evaluations (so they are rendered as labels, not
/// stubbed buttons that do nothing).
struct ActionsTabView: View {
    let row: SessionRow?

    var body: some View {
        if let actions = row?.result?.actions, !actions.isEmpty {
            List {
                Section {
                    ForEach(actions, id: \.self) { action in
                        Label(action, systemImage: "bolt")
                            .font(Theme.Fonts.sidebarMono)
                            .listRowSeparator(.hidden)
                    }
                } footer: {
                    Text("Preview — actions will run once Sage is connected.")
                        .font(Theme.Fonts.meta)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        } else {
            ContentUnavailableView(
                "No Actions",
                systemImage: "bolt",
                description: Text(emptyDescription)
            )
        }
    }

    /// Honest empty-state copy: no selection, a row that was never evaluated
    /// (no result yet), or a result whose kind genuinely has no actions.
    private var emptyDescription: String {
        switch row {
        case nil: "Select a result in the tape to see its actions."
        case .some(let row) where row.result == nil: "This row hasn't been evaluated yet."
        default: "This result has no actions."
        }
    }
}

#Preview("Matrix-ish row") {
    ActionsTabView(row: PlaceholderData.rows[1])
        .frame(width: 280, height: 400)
}

#Preview("Empty") {
    ActionsTabView(row: nil)
        .frame(width: 280, height: 400)
}
