import Foundation
import Testing
@testable import Casette

@MainActor
@Suite("ShellModel")
struct ShellModelTests {
    // V1.2 exit criterion: rows can be appended.
    @Test("submitting the draft appends a pending row and clears the draft")
    func submitAppendsRow() {
        let model = ShellModel()
        model.draft = "factor x^4 - 1"
        model.submitDraft()

        #expect(model.rows.count == 1)
        #expect(model.rows[0].input == "factor x^4 - 1")
        // V1.4: the friendly compiler is wired in — the row records the
        // raw input AND the generated Sage.
        #expect(model.rows[0].sage == "factor(x^4 - 1)")
        // No kernel until V1.3: the row is honestly incomplete — no result.
        #expect(model.rows[0].status == .running)
        #expect(model.rows[0].result == nil)
        #expect(model.rows[0].isPending)
        #expect(model.kernelState == .notConnected)
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

    // V1.2 exit criterion: running rows are represented (and the V1.3 seam
    // completes them in place, identity stable).
    @Test("completing a pending row applies the evaluation in place")
    func completeAppliesEvaluation() {
        let model = ShellModel()
        let rowID = model.append(CompiledInput.bypass("2 + 2"))
        #expect(model.rows[0].status == .running)

        let envelope = PersistedEnvelope(kind: "integer", plain: "4", latex: "4")
        model.complete(
            rowID: rowID,
            with: Evaluation(status: .ok, result: envelope, duration: 0.001)
        )

        #expect(model.rows.count == 1)
        #expect(model.rows[0].id == rowID)
        #expect(model.rows[0].status == .ok)
        #expect(model.rows[0].result?.plain == "4")
        #expect(model.rows[0].duration == 0.001)
        // A freshly evaluated result is stamped like the V0.10 recorder:
        // provenance cached-at-now, what a later restore loads as "cached".
        #expect(model.rows[0].provenance.kind == .cached)
        #expect(model.rows[0].provenance.cachedAt != nil)
    }

    // V1.2 exit criterion: failed rows are represented.
    @Test("a failed evaluation lands as an error row with the error detail")
    func failedRowsRepresented() {
        let model = ShellModel()
        let rowID = model.append(CompiledInput.bypass("1/0"))
        let envelope = PersistedEnvelope(
            kind: "error", plain: "rational division by zero",
            error: PersistedError(
                type: "ZeroDivisionError", message: "rational division by zero"
            )
        )
        model.complete(rowID: rowID, with: Evaluation(status: .error, result: envelope))

        #expect(model.rows[0].status == .error)
        #expect(model.rows[0].errorType == "ZeroDivisionError")
        #expect(model.rows[0].result?.error?.message == "rational division by zero")
    }

    @Test("completing an unknown row id is a no-op")
    func completeUnknownIDIsNoOp() {
        let model = ShellModel(rows: PlaceholderData.rows)
        let before = model.rows
        model.complete(rowID: UUID(), with: Evaluation(status: .ok, result: nil))
        #expect(model.rows == before)
    }

    // V1.2 exit criterion: rows can be edited (identity stable, stale result
    // honestly cleared).
    @Test("editing a row recompiles input, clears the stale result, keeps the id")
    func editKeepsIdentityClearsResult() {
        let model = ShellModel(rows: PlaceholderData.rows)
        let target = model.rows[0]
        #expect(target.status == .ok)

        model.edit(rowID: target.id, input: "  3 + 3  ")

        let edited = model.rows[0]
        #expect(edited.id == target.id)
        #expect(edited.input == "3 + 3")
        #expect(edited.sage == "3 + 3")
        #expect(edited.status == .running)
        #expect(edited.result == nil)
        #expect(edited.duration == nil)
        // Neighbors untouched.
        #expect(model.rows[1] == PlaceholderData.rows[1])
    }

    @Test("editing to an empty input is rejected, row untouched")
    func editRejectsEmptyInput() {
        let model = ShellModel(rows: PlaceholderData.rows)
        let before = model.rows[0]
        model.edit(rowID: before.id, input: "   ")
        #expect(model.rows[0] == before)
    }

    @Test("toggling expanded flips only that row's UI state")
    func toggleExpanded() {
        let model = ShellModel(rows: PlaceholderData.rows)
        let target = model.rows[2]
        #expect(!target.expanded)

        model.toggleExpanded(rowID: target.id)
        #expect(model.rows[2].expanded)
        // The result data is untouched by the UI-state flip.
        #expect(model.rows[2].result == target.result)
        #expect(model.rows.filter(\.expanded).count == 1)

        model.toggleExpanded(rowID: target.id)
        #expect(!model.rows[2].expanded)
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

    @Test("appending bumps the session's updated timestamp")
    func appendBumpsUpdated() {
        let model = ShellModel()
        let before = model.session.updated
        model.append(CompiledInput.bypass("2 + 2"), at: before.addingTimeInterval(60))
        #expect(model.session.updated == before.addingTimeInterval(60))
    }
}
