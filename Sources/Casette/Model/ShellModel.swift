import Foundation
import Observation

/// The view-facing seam over the live session: one `Session` (the real V1.2
/// model, lifted from v0/10), the latest `SymbolSnapshot`, the kernel state,
/// and the transient UI state (selection, input draft). Views stay dumb and
/// read only what's here; the kernel (V1.3) plugs into `append`/`complete`.
///
/// Kernel wiring: `connectKernel` attaches a `SessionController` (an actor —
/// all kernel I/O runs off the main actor) and watches its status stream.
/// Submissions append a pending row, then evaluate through a CHAINED task
/// queue (`kernelQueue`), so rapid submissions evaluate strictly in tape
/// order against the one persistent namespace. Restart and interrupt are NOT
/// chained — they're the escape hatches and must preempt a stuck eval.
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
    /// The latest symbol-table snapshot — refreshed from the worker `symbols`
    /// op after every evaluation. Replaced whole on every refresh.
    private(set) var symbols: SymbolSnapshot
    /// Kernel lifecycle as the app sees it, driven by the controller's
    /// status stream. `.notConnected` until `connectKernel` runs.
    private(set) var kernelState: KernelState = .notConnected
    /// Honest, user-facing reason the kernel is unavailable (no Sage found,
    /// crash, forced stop) — drives the recovery banner. nil when healthy.
    private(set) var kernelIssue: String?
    var selectedRowID: SessionRow.ID?
    var draft = ""

    private var controller: SessionController?
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    /// The serial evaluation queue: each enqueued work item awaits the
    /// previous one, so evals run strictly in tape order. Internal so tests
    /// can await quiescence.
    @ObservationIgnored private(set) var kernelQueue: Task<Void, Never>?

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

    // MARK: - Kernel

    /// Attaches the kernel controller, starts watching its status stream,
    /// and boots Sage. With no controller attached (previews, pure model
    /// tests) submissions stay honestly pending, exactly like V1.2.
    func connectKernel(_ controller: SessionController = SessionController()) {
        guard self.controller == nil else { return }
        self.controller = controller
        statusTask = Task { [weak self] in
            for await status in controller.statusUpdates {
                guard let self else { return }
                kernelState = status.state
                kernelIssue = status.issue
            }
        }
        enqueueKernelWork {
            await controller.connect()
        }
    }

    /// Intentionally resets the session's Sage state: kills the worker,
    /// boots a fresh one, and refreshes the (now empty) symbol table. NOT
    /// chained behind pending evaluations — restart is the escape hatch and
    /// must preempt a stuck eval (which then finishes as interrupted).
    func restartKernel() {
        guard let controller else { return }
        Task {
            await controller.restart()
            await refreshSymbols()
        }
    }

    /// Asks the in-flight evaluation to stop (SIGINT, escalating to a hard
    /// kill if Sage won't yield). Safe to call any time; no-op when idle.
    func interruptEvaluation() {
        guard let controller else { return }
        Task { await controller.interruptCurrent() }
    }

    /// Compile (V1.4 — bypass-only for now), append a pending row, and
    /// evaluate it through the serial kernel queue.
    func submitDraft() {
        let input = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        let compiled = CompiledInput.bypass(input)
        let rowID = append(compiled)
        draft = ""
        evaluate(rowID: rowID, sage: compiled.sage)
    }

    /// Evaluates a pending row in order, applies the outcome in place, and
    /// refreshes the symbol sidebar (the V0.6 op is cheap — ~1ms).
    private func evaluate(rowID: SessionRow.ID, sage: String) {
        guard let controller else { return }  // pre-kernel: row stays pending
        enqueueKernelWork { [weak self] in
            let evaluation = await controller.evaluate(sage)
            guard let self else { return }
            complete(rowID: rowID, with: evaluation)
            await refreshSymbols()
        }
    }

    private func refreshSymbols() async {
        guard let controller else { return }
        if let snapshot = await controller.fetchSymbols() {
            symbols = snapshot
        }
    }

    /// Appends `work` to the serial kernel queue (each item awaits the one
    /// before it, so kernel requests never interleave).
    private func enqueueKernelWork(_ work: @escaping @MainActor () async -> Void) {
        kernelQueue = Task { [previous = kernelQueue] in
            await previous?.value
            await work()
        }
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
