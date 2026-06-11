import SwiftUI

/// Prior inputs, newest first, with quick reuse (insert/copy). Rerun
/// arrives with the kernel (V1.3/V1.6).
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
                HistoryRowView(row: row, onInsert: { insert(row) })
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
