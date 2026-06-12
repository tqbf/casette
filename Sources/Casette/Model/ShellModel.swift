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
    /// Which sidebar tab is showing. Transient UI state (like selection),
    /// model-owned so sidebar flows can switch tabs (Symbols → Inspect lands
    /// the user on the Inspector) and tests can assert the flow.
    var sidebarTab: SidebarTab = .symbols
    /// The input draft. Any change that is NOT a history recall counts as a
    /// user edit: it dismisses a pending ambiguity picker (the candidates
    /// describe text that no longer exists) and ends history navigation (the
    /// next Up starts from the newest entry — standard shell behavior). A
    /// recall changes the draft too, but must not end the navigation it is
    /// part of, so it announces itself via `isRecallingHistory`.
    var draft = "" {
        didSet {
            guard draft != oldValue else { return }
            pendingAmbiguity = nil
            if !isRecallingHistory {
                inputHistory.endNavigation()
            }
        }
    }
    /// An ambiguous submission awaiting the user's pick (drives the inline
    /// candidate panel above the input). Transient UI state, never persisted.
    var pendingAmbiguity: PendingAmbiguity?
    /// Command history (the session's submitted inputs) behind Up/Down.
    private(set) var inputHistory = InputHistory()

    /// True while a history recall is writing the draft, so `draft.didSet`
    /// can tell a recall apart from a user edit.
    @ObservationIgnored private var isRecallingHistory = false

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

    /// The boot prelude, sent (and discarded) right after every boot AND
    /// every restart. The real Sage REPL predefines `x` as a symbolic
    /// variable at startup; the worker's bare star-import does NOT
    /// (PROBLEMS.md V0.5), so raw-Sage inputs like `expand((x+1)^8)` — which
    /// bypass the friendly compiler and its `var('V')` preludes —
    /// NameError'd where the real REPL succeeds. Matching the REPL app-side
    /// keeps worker.py byte-frozen; `x` honestly appears in the Symbols
    /// sidebar from boot (the REPL predefines it too). Re-declaring is
    /// idempotent, so a friendly `var('x')` prelude on top is harmless.
    static let bootPrelude = "var('x')"

    /// Attaches the kernel controller, starts watching its status stream,
    /// and boots Sage (followed by the REPL-matching `var('x')` prelude and
    /// a symbol refresh). With no controller attached (previews, pure model
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
        enqueueKernelWork { [weak self] in
            await controller.connect()
            _ = await controller.evaluate(Self.bootPrelude)
            await self?.refreshSymbols()
        }
    }

    /// Intentionally resets the session's Sage state: kills the worker,
    /// boots a fresh one, re-applies the boot prelude (the fresh namespace
    /// must match the real REPL too), and refreshes the symbol table (now
    /// just `x`). NOT chained behind pending evaluations — restart is the
    /// escape hatch and must preempt a stuck eval (which then finishes as
    /// interrupted).
    func restartKernel() {
        guard let controller else { return }
        Task {
            await controller.restart()
            _ = await controller.evaluate(Self.bootPrelude)
            await refreshSymbols()
        }
    }

    /// Asks the in-flight evaluation to stop (SIGINT, escalating to a hard
    /// kill if Sage won't yield). Safe to call any time; no-op when idle.
    func interruptEvaluation() {
        guard let controller else { return }
        Task { await controller.interruptCurrent() }
    }

    // MARK: - Input compilation & submission

    /// The live compile of the current draft, for the preview line under the
    /// input field. Pure and microsecond-fast, so recomputing per keystroke
    /// is fine — friendly → Sage is always inspectable before submitting.
    var draftPreview: DraftPreview {
        let input = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return .empty }
        switch CompiledInput.compile(input) {
        case let .ready(compiled):
            return compiled.origin == .friendly ? .generated(compiled.sage) : .rawSage
        case let .error(error):
            return .issue(message: error.message, suggestion: error.suggestion)
        case let .ambiguous(candidates):
            return .ambiguous(count: candidates.count)
        }
    }

    /// Return: compile and evaluate, advancing (the draft clears).
    func submitDraft() {
        submit(advancing: true)
    }

    /// ⌘-Return: compile and evaluate WITHOUT advancing — the input stays in
    /// place so the user can iterate on it.
    func evaluateInPlace() {
        submit(advancing: false)
    }

    /// Compile the draft and act on the outcome. A compile error submits
    /// nothing and keeps the draft (the preview line already explains it);
    /// ambiguity hands the candidates to the picker.
    private func submit(advancing: Bool) {
        let input = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        switch CompiledInput.compile(input) {
        case let .ready(compiled):
            submitCompiled(compiled, advancing: advancing)
        case .error:
            break  // shown inline by `draftPreview`; no row, draft kept
        case let .ambiguous(candidates):
            pendingAmbiguity = PendingAmbiguity(
                raw: input, candidates: candidates, advances: advancing)
        }
    }

    /// The user picked an ambiguity candidate: it evaluates as a friendly
    /// submission of the original raw input.
    func resolveAmbiguity(choosing candidate: String) {
        guard let pending = pendingAmbiguity,
              pending.candidates.contains(candidate)
        else { return }
        pendingAmbiguity = nil
        submitCompiled(
            CompiledInput.chosenCandidate(raw: pending.raw, sage: candidate),
            advancing: pending.advances)
    }

    /// Keyboard pick while the ambiguity picker is up: Return = index 0,
    /// digits 2–9 = indices 1–8 (matching the picker's keycap hints). An
    /// out-of-range index does nothing — the picker stays. Returns whether a
    /// candidate was chosen.
    @discardableResult
    func resolveAmbiguity(at index: Int) -> Bool {
        guard let pending = pendingAmbiguity,
              pending.candidates.indices.contains(index)
        else { return false }
        resolveAmbiguity(choosing: pending.candidates[index])
        return true
    }

    /// Esc while the ambiguity picker is up: dismiss it, keep the draft
    /// exactly as typed (restoring focus is the view's job). Returns whether
    /// there was a picker to dismiss.
    @discardableResult
    func cancelAmbiguity() -> Bool {
        guard pendingAmbiguity != nil else { return false }
        pendingAmbiguity = nil
        return true
    }

    @discardableResult
    private func submitCompiled(_ compiled: CompiledInput, advancing: Bool) -> SessionRow.ID {
        let rowID = append(compiled)
        inputHistory.record(compiled.raw)
        if advancing {
            draft = ""
        }
        evaluate(rowID: rowID, compiled: compiled)
        return rowID
    }

    /// Submits sidebar-initiated Sage (forget / inspect / rerun / an action's
    /// command) through the SAME path as typed input — compile, append a tape
    /// row, record history, evaluate on the serial kernel queue — WITHOUT
    /// touching the draft. Returns the new row's identity, or nil if the
    /// input doesn't compile to something submittable.
    @discardableResult
    private func submitProgrammatically(_ input: String) -> SessionRow.ID? {
        guard case let .ready(compiled) = CompiledInput.compile(input) else { return nil }
        return submitCompiled(compiled, advancing: false)
    }

    // MARK: - Sidebar: Symbols actions

    /// Symbols tab → Insert: appends the symbol name to the draft, separated
    /// from a preceding identifier/number character so names never merge
    /// (`2 + ` + `n` → `2 + n`; `2*` + `n` → `2*n`). True at-cursor insertion
    /// isn't buildable — macOS 14's `TextEditor` exposes no cursor to the
    /// model (the documented V1.4 constraint) — and the cursor rests at the
    /// end of the draft in the common case, so append IS the honest version.
    func insertSymbolIntoDraft(_ name: String) {
        guard let last = draft.last else {
            draft = name
            return
        }
        let needsSeparator = last.isLetter || last.isNumber || last == "_" || last == ")"
        draft += needsSeparator ? " \(name)" : name
    }

    /// Symbols tab → Forget: evaluates `del name` through the kernel as a
    /// REGULAR tape row, not a silent op. Deliberate: the tape is the session
    /// log — V1.9's replay re-sends rows in order, so a namespace mutation
    /// that isn't a row would make a restored session diverge from what the
    /// user saw. The eval path refreshes symbols, so the entry disappears.
    func forgetSymbol(_ name: String) {
        submitProgrammatically("del \(name)")
    }

    /// Symbols tab → Inspect: evaluates the bare name (exactly what typing it
    /// would do — the honest "show me this value", leaving a result row on
    /// the tape), selects the new row, and lands on the Inspector tab.
    func inspectSymbol(_ name: String) {
        guard let rowID = submitProgrammatically(name) else { return }
        select(rowID)
        sidebarTab = .inspector
    }

    // MARK: - Sidebar: History actions

    /// History tab → Rerun: re-evaluates a prior row's input through the
    /// normal submit path — a fresh row at the end of the tape, the original
    /// untouched, the draft untouched. An input that compiles ambiguous
    /// re-submits its RECORDED resolution (`row.sage`); rerun never re-asks.
    func rerun(rowID: SessionRow.ID) {
        guard let row = session.rows.first(where: { $0.id == rowID }) else { return }
        switch CompiledInput.compile(row.input) {
        case let .ready(compiled):
            submitCompiled(compiled, advancing: false)
        case .ambiguous:
            submitCompiled(
                .chosenCandidate(raw: row.input, sage: row.sage), advancing: false)
        case .error:
            break  // a previously submitted input can't stop compiling
        }
    }

    // MARK: - Sidebar: result actions

    /// Actions tab → Evaluate Now: submits an action's built command directly
    /// (the insert-into-input path is just `insertIntoDraft`) and selects the
    /// new row so the Inspector and Actions follow the fresh result.
    func evaluateActionCommand(_ command: String) {
        guard let rowID = submitProgrammatically(command) else { return }
        select(rowID)
    }

    // MARK: - History navigation (Up/Down)

    /// Up: recall the previous submitted input. Acts in single-line mode, or
    /// at ANY time while navigation is already in progress — a recalled
    /// multiline entry must not strand the user mid-walk. The moment the
    /// user edits, navigation ends (`draft.didSet`) and the arrows go back
    /// to moving the cursor. Returns whether the key was consumed.
    func recallPreviousInput() -> Bool {
        guard !draft.contains("\n") || inputHistory.isNavigating else { return false }
        guard let recalled = inputHistory.recallPrevious(stashing: draft) else { return false }
        setRecalledDraft(recalled)
        return true
    }

    /// Down: move forward through history; past the newest entry the stashed
    /// in-progress draft is restored. Same multiline rule as Up: it keeps
    /// navigating while navigation is in progress. Returns whether the key
    /// was consumed.
    func recallNextInput() -> Bool {
        guard !draft.contains("\n") || inputHistory.isNavigating else { return false }
        guard let recalled = inputHistory.recallNext() else { return false }
        setRecalledDraft(recalled)
        return true
    }

    /// Writes a recalled entry into the draft WITHOUT counting as a user
    /// edit (a recall must not end the navigation it's part of; it still
    /// dismisses a pending ambiguity, since the draft text changed).
    private func setRecalledDraft(_ text: String) {
        isRecallingHistory = true
        draft = text
        isRecallingHistory = false
    }

    /// Evaluates a pending row in order, applies the outcome in place, and
    /// refreshes the symbol sidebar (the V0.6 op is cheap — ~1ms).
    ///
    /// Prelude policy (FRIENDLY-COMPILER.md, frozen): each required variable
    /// is declared with its own `var('V')` eval BEFORE the generated Sage —
    /// part of what's sent, never part of what the row displays. Prelude
    /// results are discarded (`var` over a valid identifier can't fail and
    /// re-declaring is idempotent).
    private func evaluate(rowID: SessionRow.ID, compiled: CompiledInput) {
        guard let controller else { return }  // pre-kernel: row stays pending
        enqueueKernelWork { [weak self] in
            for prelude in compiled.preludes {
                _ = await controller.evaluate(prelude)
            }
            let evaluation = await controller.evaluate(compiled.sage)
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
    /// input is recompiled (through the real compiler) and the stale result
    /// is cleared, so the row honestly reads as not-yet-evaluated again.
    /// An edit that doesn't compile (error/ambiguous) leaves the row intact.
    func edit(rowID: SessionRow.ID, input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = session.rows.firstIndex(where: { $0.id == rowID }),
              case let .ready(compiled) = CompiledInput.compile(trimmed)
        else { return }
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
