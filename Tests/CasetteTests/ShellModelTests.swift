import Foundation
import Testing
@testable import Casette

@MainActor
@Suite("ShellModel")
struct ShellModelTests {
    @Test("submitting the draft appends a not-evaluated row and clears the draft")
    func submitAppendsRow() {
        let model = ShellModel()
        model.draft = "factor x^4 - 1"
        model.submitDraft()

        #expect(model.rows.count == 1)
        #expect(model.rows[0].input == "factor x^4 - 1")
        #expect(model.rows[0].sage == "factor x^4 - 1")
        #expect(model.rows[0].status == .notEvaluated)
        #expect(model.draft.isEmpty)
    }

    @Test("whitespace-only drafts are ignored, surrounding whitespace is trimmed")
    func submitTrimsAndIgnoresEmpty() {
        let model = ShellModel()
        model.draft = "   \n"
        model.submitDraft()
        #expect(model.rows.isEmpty)

        model.draft = "  2 + 2  "
        model.submitDraft()
        #expect(model.rows.count == 1)
        #expect(model.rows[0].input == "2 + 2")
    }

    @Test("selection resolves to the selected row, nil when cleared")
    func selectionLookup() {
        let model = ShellModel(rows: PlaceholderData.rows)
        let target = PlaceholderData.rows[2]

        model.select(target.id)
        #expect(model.selectedRow?.id == target.id)
        #expect(model.selectedRow?.input == target.input)

        model.select(nil)
        #expect(model.selectedRow == nil)
    }

    @Test("history is newest first")
    func historyNewestFirst() {
        let model = ShellModel(rows: PlaceholderData.rows)
        #expect(model.historyRows.first?.id == PlaceholderData.rows.last?.id)
        #expect(model.historyRows.last?.id == PlaceholderData.rows.first?.id)
    }

    @Test("insert into draft replaces the draft")
    func insertIntoDraft() {
        let model = ShellModel()
        model.draft = "old"
        model.insertIntoDraft("A.eigenvalues()")
        #expect(model.draft == "A.eigenvalues()")
    }
}
