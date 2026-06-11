import SwiftUI

/// Context-sensitive actions for the selected result, straight from the
/// envelope's per-kind `actions` list. Informational in V1.1 — they become
/// runnable follow-up evaluations in V1.11 (so they are rendered as labels,
/// not stubbed buttons that do nothing).
struct ActionsTabView: View {
    let row: TapeRow?

    var body: some View {
        if let row, !row.actions.isEmpty {
            List {
                Section {
                    ForEach(row.actions, id: \.self) { action in
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
                description: Text(
                    row == nil
                        ? "Select a result in the tape to see its actions."
                        : "This result has no actions."
                )
            )
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
