import SwiftUI

/// Prior inputs, newest first, with quick reuse: rerun (a fresh evaluation
/// through the normal submit path), insert into input, copy.
struct HistoryTabView: View {
    var model: ShellModel
    var focusInput: () -> Void

    var body: some View {
        if model.rows.isEmpty {
            ContentUnavailableView(
                "No History Yet",
                systemImage: "clock",
                description: Text("Everything you evaluate appears here.")
            )
        } else {
            List(model.historyRows) { row in
                HistoryRowView(
                    row: row,
                    onInsert: { insert(row) },
                    onRerun: { model.rerun(rowID: row.id) }
                )
                .listRowSeparator(.hidden)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private func insert(_ row: SessionRow) {
        model.insertIntoDraft(row.input)
        focusInput()
    }
}

#Preview {
    HistoryTabView(model: ShellModel(rows: PlaceholderData.rows), focusInput: {})
        .frame(width: 280, height: 400)
}
