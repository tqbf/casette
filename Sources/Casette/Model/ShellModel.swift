import Foundation
import Observation

/// The view-facing seam over the live session: one `Session` (the real V1.2
/// model, lifted from v0/10), the latest `SymbolSnapshot`, the kernel state,
/// and the transient UI state (selection, input draft). Views stay dumb and
/// read only what's here; V1.3 plugs `SageKernel` into `append`/`complete`
/// without reshaping anything.
///
/// UI-state policy (the V1.2 "result data independent of UI rendering" exit
/// criterion): result data is `PersistedEnvelope` — pure Codable wire-derived
/// fields, zero UI state. Transient UI state (selection, draft, kernel
/// presentation) lives ONLY here, never in the Codable model. The one durable
/// piece of UI state, `SessionRow.expanded`, stays on the row because
/// SESSION-FORMAT.md deliberately persists it (the tape restores
/// collapsed/expanded as the user left it) — but it is outside the result
/// envelope, so flipping it can never change what a result *is*.
@MainActor
@Observable
final class ShellModel {
    /// The live session — the same value V1.9's `SessionStore` will save and
    /// load. Mutations go through the methods below so `updated` stays honest.
    private(set) var session: Session
    /// The latest symbol-table snapshot (placeholder until V1.6 wires the
    /// worker `symbols` op). Replaced whole on every refresh.
    private(set) var symbols: SymbolSnapshot
    /// Kernel lifecycle as the app sees it. Always `.notConnected` in V1.2;
    /// V1.3's `SageKernel` drives the rest of the machine.
    private(set) var kernelState: KernelState = .notConnected
    var selectedRowID: SessionRow.ID?
    var draft = ""

    init(rows: [SessionRow] = [], symbols: SymbolSnapshot = .empty) {
        let now = Date.now
        self.session = Session(created: now, updated: now, rows: rows)
        self.symbols = symbols
    }

    var rows: [SessionRow] { session.rows }

    var selectedRow: SessionRow? {
        guard let selectedRowID else { return nil }
        return session.rows.first { $0.id == selectedRowID }
    }

    /// Prior inputs, newest first, for the History tab.
    var historyRows: [SessionRow] { session.rows.reversed() }

    /// Compile (V1.4 — bypass-only for now) and append the current draft as a
    /// pending row. There is no kernel yet (V1.3), so the row stays incomplete
    /// and the tape presents it honestly via `kernelState`.
    func submitDraft() {
        let input = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        append(CompiledInput.bypass(input))
        draft = ""
    }

    /// Appends a pending (incomplete) row for a compiled input and returns its
    /// stable identity. V1.3 calls this on submit, then `complete(rowID:with:)`
    /// when the kernel answers.
    @discardableResult
    func append(_ compiled: CompiledInput, at date: Date = .now) -> SessionRow.ID {
        let row = SessionRow(
            input: compiled.raw,
            sage: compiled.sage,
            result: nil,
            status: .running,
            timestamp: date
        )
        session.rows.append(row)
        session.updated = date
        return row.id
    }

    /// Applies a finished evaluation to its pending row (the V1.3 seam).
    /// Unknown IDs are ignored (the row may have been removed meanwhile).
    func complete(rowID: SessionRow.ID, with evaluation: Evaluation, at date: Date = .now) {
        guard let index = session.rows.firstIndex(where: { $0.id == rowID }) else { return }
        session.rows[index].apply(evaluation, at: date)
        session.updated = date
    }

    /// Edits a row's input in place. Identity and timestamp are stable; the
    /// input is recompiled and the stale result is cleared, so the row honestly
    /// reads as not-yet-evaluated again (re-evaluation arrives with V1.3).
    func edit(rowID: SessionRow.ID, input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = session.rows.firstIndex(where: { $0.id == rowID })
        else { return }
        let compiled = CompiledInput.bypass(trimmed)
        session.rows[index].input = compiled.raw
        session.rows[index].sage = compiled.sage
        session.rows[index].result = nil
        session.rows[index].status = .running
        session.rows[index].durationSeconds = nil
        session.updated = .now
    }

    /// Flips a row's expanded/collapsed state (the V1.2 row field; V1.5's
    /// result cards give it a visible affordance).
    func toggleExpanded(rowID: SessionRow.ID) {
        guard let index = session.rows.firstIndex(where: { $0.id == rowID }) else { return }
        session.rows[index].expanded.toggle()
    }

    func select(_ rowID: SessionRow.ID?) {
        selectedRowID = rowID
    }

    /// Place text in the input draft (History → "Insert into Input").
    func insertIntoDraft(_ text: String) {
        draft = text
    }
}
