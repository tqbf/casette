import Foundation
import Observation

/// The V1.1 shell's view-facing state: placeholder tape rows, placeholder
/// symbols, row selection, and the input draft. This is the seam the real
/// V1.2 session model + V1.3 kernel replace — views stay dumb and read only
/// what's here.
@MainActor
@Observable
final class ShellModel {
    private(set) var rows: [TapeRow]
    private(set) var symbols: [SymbolEntry]
    var selectedRowID: TapeRow.ID?
    var draft = ""

    init(rows: [TapeRow] = [], symbols: [SymbolEntry] = []) {
        self.rows = rows
        self.symbols = symbols
    }

    var selectedRow: TapeRow? {
        guard let selectedRowID else { return nil }
        return rows.first { $0.id == selectedRowID }
    }

    /// Prior inputs, newest first, for the History tab.
    var historyRows: [TapeRow] { rows.reversed() }

    /// Append the current draft to the tape. There is no kernel yet (V1.3),
    /// so the row is honest about not being evaluated.
    func submitDraft() {
        let input = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        rows.append(
            TapeRow(
                input: input,
                sage: input,
                status: .notEvaluated,
                kind: "none",
                primary: "Not evaluated — Sage isn't connected yet.",
                timestamp: .now
            )
        )
        draft = ""
    }

    func select(_ rowID: TapeRow.ID?) {
        selectedRowID = rowID
    }

    /// Place text in the input draft (History → "Insert into Input").
    func insertIntoDraft(_ text: String) {
        draft = text
    }
}
