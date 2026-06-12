import Foundation
import FriendlyCompiler
import Observation
import os

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
    /// True when `kernelIssue` is a SETUP failure (no Sage found, worker
    /// missing) rather than a runtime crash — the banner then leads with the
    /// Sage Doctor (V1.10's "missing Sage path opens Sage Doctor" hook).
    private(set) var kernelSetupFailed = false
    /// Presents the Sage Doctor sheet (the Sage menu item and the kernel
    /// banner both open it). Transient UI state, never persisted.
    var isDoctorPresented = false
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
    /// V1.8 numeric mode: while on, TYPED submissions evaluate force-numeric
    /// (the V0.8 per-request `numeric:true` — decimal primary, exact form
    /// preserved in `exactValue`; the worker guarantees the namespace stays
    /// exact). A sticky, always-visible toggle (the pressed input-pane
    /// button + the checked Sage-menu item make the scope obvious), scoped
    /// to draft submissions only — sidebar flows (inspect/forget/actions)
    /// are never numeric, and rerun reproduces the ORIGINAL row's recorded
    /// flag. Transient session-display state, never persisted (each row
    /// records its own `numeric`).
    var numericMode = false
    /// Command history (the session's submitted inputs) behind Up/Down.
    private(set) var inputHistory = InputHistory()
    /// True while Replay Session is re-sending the tape (disables the menu
    /// command; the replay itself rides the serial kernel queue).
    private(set) var isReplaying = false
    /// The IDs of rows that arrived via restore THIS run — the transient
    /// state behind the quiet per-row provenance mark (`RowProvenanceMark`):
    /// the persisted `Provenance` records a fresh eval as `cached` (that is
    /// what a later restore loads), so "loaded from disk" vs "evaluated just
    /// now" is only knowable here. Never persisted.
    private(set) var restoredRowIDs: Set<SessionRow.ID> = []

    /// True while a history recall is writing the draft, so `draft.didSet`
    /// can tell a recall apart from a user edit.
    @ObservationIgnored private var isRecallingHistory = false

    /// The persistence engine (V1.9). nil = no persistence: previews and
    /// pure-model tests construct `ShellModel()` and never touch disk; the
    /// real app attaches a store via `restoreLastSession(from:)`. Also
    /// nil-ed deliberately when load refuses a NEWER schema — saving would
    /// clobber a file a future app version can still read.
    @ObservationIgnored private var store: SessionStore?
    @ObservationIgnored private let logger = Logger(
        subsystem: "org.sockpuppet.casette", category: "persistence")
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

    var canClearTape: Bool { !session.rows.isEmpty }

    var tapeReferences: TapeReferenceTable {
        let entries = session.rows.enumerated().compactMap { index, row -> (Int, String)? in
            guard let expression = row.reusableExpression else { return nil }
            return (index + 1, expression)
        }
        return TapeReferenceTable(
            entries: Dictionary(uniqueKeysWithValues: entries.suffix(TapeReferenceTable.capacity))
        )
    }

    var selectedRow: SessionRow? {
        guard let selectedRowID else { return nil }
        return session.rows.first { $0.id == selectedRowID }
    }

    /// Prior inputs, newest first, for the History tab.
    var historyRows: [SessionRow] { session.rows.reversed() }

    // MARK: - Persistence (V1.9)

    /// Attaches the session store and restores the last session, BEFORE the
    /// kernel connects — restore needs no worker (the V0.10 guarantee: rows
    /// render from their persisted envelopes with Sage genuinely not
    /// spawned), so a machine with no Sage still gets its tape back,
    /// read-only, under the honest kernel banner (V1.10 puts the full Doctor
    /// behind that banner).
    ///
    /// Outcome handling per SESSION-FORMAT.md:
    ///   * restored — adopt the session (artifact liveness already
    ///     re-resolved by `load()`; a restored plot's PNG is essentially
    ///     always `missing` — V1.7's honest box renders it). Rows persisted
    ///     mid-eval (`running` — the crash case) flip to `interrupted` with
    ///     a readable synthetic result: nothing will ever complete them, and
    ///     an eternal spinner would be a lie.
    ///   * fresh — first launch / no file; nothing to do.
    ///   * corruptQuarantined — the bad file was moved aside; start fresh
    ///     (saving continues — the quarantine IS the recovery).
    ///   * refusedSchema — a NEWER app wrote that file; start fresh and
    ///     DISABLE saving so this run never clobbers the future.
    func restoreLastSession(from store: SessionStore) {
        self.store = store
        switch store.load() {
        case .restored(var restored):
            for index in restored.rows.indices where restored.rows[index].status == .running {
                let message = "Casette quit before this evaluation finished."
                restored.rows[index].status = .interrupted
                restored.rows[index].result = PersistedEnvelope(
                    kind: "error",
                    plain: message,
                    error: PersistedError(type: "Interrupted", message: message))
            }
            session = restored
            restoredRowIDs = Set(restored.rows.map(\.id))
            for row in restored.rows {
                inputHistory.record(row.input)
            }
            logger.info("restored \(restored.rows.count) row(s) from the last session")
            persist()  // re-resolved liveness + any flipped rows, on disk now
        case .fresh:
            break
        case let .corruptQuarantined(quarantinePath, detail):
            logger.error(
                "last-session.json was corrupt — quarantined to \(quarantinePath, privacy: .public): \(detail, privacy: .public)")
        case let .refusedSchema(found, supported):
            self.store = nil
            logger.warning(
                "last-session.json has schema \(found) (this app supports \(supported)) — leaving it intact; persistence is off for this run")
        }
    }

    /// The quiet provenance mark a row's card shows, or nil for a row
    /// evaluated fresh this run (the normal case shows nothing).
    func provenanceMark(for row: SessionRow) -> RowProvenanceMark? {
        guard restoredRowIDs.contains(row.id) else { return nil }
        return row.provenance.kind == .replayed ? .replayed : .cached
    }

    /// Whether row-derived commands can honestly run against the current Sage
    /// namespace. Restored cached rows are render-ready tape history, but they
    /// were not recomputed after launch; Replay Session is what makes them
    /// live again.
    func rowIsLiveInKernel(_ row: SessionRow) -> Bool {
        provenanceMark(for: row) != .cached
    }

    /// Saves the session atomically (temp-write + rename — the V0.10
    /// pattern), called after EVERY row mutation and header change, so a
    /// crash at any moment leaves a complete file up to the last completed
    /// row. A save failure is logged, never fatal — persistence must not
    /// take the calculator down.
    private func persist() {
        guard let store else { return }
        do {
            try store.save(session)
        } catch {
            logger.error("session save failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Kernel

    /// The boot prelude, sent (and discarded) right after every boot AND
    /// every restart. The real Sage REPL predefines only `x` as a symbolic
    /// variable at startup; the worker's bare star-import predefines NONE
    /// (PROBLEMS.md V0.5), so raw-Sage inputs — which bypass the friendly
    /// compiler and its `var('V')` preludes — NameError'd where the real
    /// REPL succeeds.
    ///
    /// V1.7 deliberately goes BEYOND strict REPL fidelity (an approved
    /// product call, documented in plans/FRIENDLY-COMPILER.md): a calculator
    /// user reasonably expects `implicit_plot(x^2+y^2==1, (x,-2,2),
    /// (y,-2,2))`, parametric plots over `t`, and 3D examples over `y`/`z`
    /// to work out of the box, exactly as the upstream docs write them.
    /// `var('x, y, z, t')` covers the conventional calculator variables; all
    /// four honestly appear in the Symbols sidebar from boot. Declaring is
    /// idempotent, so friendly `var('V')` preludes on top are harmless, and
    /// worker.py stays byte-frozen (the prelude is app-side).
    static let bootPrelude = "var('x, y, z, t')"

    /// The worker's own default `precision_digits` (WORKER-PROTOCOL.md
    /// `config` op). A fresh worker boots at this value, so the boot/restart
    /// path only sends a `config` op when the session differs from it.
    static let workerDefaultPrecisionDigits = 10

    /// The session-level approximation precision (decimal digits for the
    /// envelope's `approx` and numeric-mode primaries). Reads/writes the
    /// session header's `precisionDigits` (SESSION-FORMAT.md — V1.9 persists
    /// and restores it); the setter pushes the worker `config` op through the
    /// serial kernel queue, so it lands between evals in submission order.
    var precisionDigits: Int {
        get { session.precisionDigits }
        set { setPrecision(newValue) }
    }

    /// Applies a new session precision: updates the session header and sends
    /// the worker `config` op (queued, so in-flight evals keep their old
    /// precision and later ones get the new — strictly in tape order).
    /// Non-positive and no-op values are ignored (the worker would reject
    /// them anyway; the UI offers only valid choices).
    func setPrecision(_ digits: Int) {
        guard digits > 0, digits != session.precisionDigits else { return }
        session.precisionDigits = digits
        session.updated = .now
        persist()  // a header change is a session change (V1.9)
        guard let controller else { return }
        enqueueKernelWork {
            _ = await controller.configure(precisionDigits: digits)
        }
    }

    /// The session precision IF it differs from a fresh worker's default —
    /// what boot/restart must re-apply (the worker holds precision as session
    /// state, so a restart silently resets it to 10 otherwise).
    private var precisionNeedingReapply: Int? {
        session.precisionDigits == Self.workerDefaultPrecisionDigits
            ? nil : session.precisionDigits
    }

    /// Attaches the kernel controller, starts watching its status stream,
    /// and boots Sage (followed by the `var('x, y, z, t')` boot prelude and
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
                kernelSetupFailed = status.isSetupFailure
            }
        }
        enqueueKernelWork { [weak self] in
            await controller.connect()
            self?.scheduleSageVersionRefresh()
            _ = await controller.evaluate(Self.bootPrelude)
            if let digits = self?.precisionNeedingReapply {
                _ = await controller.configure(precisionDigits: digits)
            }
            await self?.refreshSymbols()
        }
    }

    // MARK: - Sage Doctor (V1.10)

    /// Opens the Sage Doctor sheet — the Sage menu item and the kernel
    /// banner's recovery action both land here.
    func openDoctor() {
        isDoctorPresented = true
    }

    /// Probes a Sage binary's version for the session header. Injectable so
    /// fake-transport tests never spawn `sage --version`; the default runs
    /// the same bounded detector the Doctor uses.
    @ObservationIgnored var sageVersionProbe: @Sendable (String) async -> String? = { path in
        await SageVersionDetector.detect(sagePath: path).displayVersion
    }

    /// Fills the session header's `sageVersion` (nil since V0.10 — V1.10's
    /// criterion) from the CURRENT worker's binary. Runs un-chained off the
    /// kernel queue: the probe spawns `sage --version` (~1s) and must never
    /// delay the first evaluation; the header write lands whenever it lands.
    private func scheduleSageVersionRefresh() {
        guard let controller else { return }
        Task { [weak self, probe = sageVersionProbe] in
            guard let path = await controller.currentSagePath else { return }
            guard let version = await probe(path) else { return }
            self?.recordSageVersion(version)
        }
    }

    private func recordSageVersion(_ version: String) {
        guard session.sageVersion != version else { return }
        session.sageVersion = version
        session.updated = .now
        persist()  // a header change is a session change (V1.9)
    }

    /// Intentionally resets the session's Sage state: kills the worker,
    /// boots a fresh one, re-applies the boot prelude (the fresh namespace
    /// gets the same calculator variables) AND the configured session
    /// precision (the fresh worker resets to 10 — V0.8 session state), and
    /// refreshes the symbol table (back to `x, y, z, t`).
    ///
    /// Two-part ordering (the V1.8 fix for a latent race):
    ///   * The `restart()` call itself is NOT chained behind pending
    ///     evaluations — restart is the escape hatch and must preempt a
    ///     stuck eval (which then finishes as interrupted; chaining it would
    ///     deadlock behind the very eval it's meant to kill).
    ///   * The RE-INIT (prelude, precision, symbols) IS enqueued on the
    ///     serial kernel queue, awaiting the restart first — so a submission
    ///     typed right after ⌘⇧R deterministically evaluates AFTER the fresh
    ///     worker has its calculator variables and session precision. (The
    ///     old shape ran the whole pipeline un-chained; a fast next
    ///     submission could land on the fresh namespace before the prelude
    ///     and NameError where the REPL succeeds.)
    func restartKernel() {
        guard let controller else { return }
        let restart = Task { await controller.restart() }
        enqueueKernelWork { [weak self] in
            await restart.value
            self?.scheduleSageVersionRefresh()  // the binary may have changed (Doctor)
            _ = await controller.evaluate(Self.bootPrelude)
            if let digits = self?.precisionNeedingReapply {
                _ = await controller.configure(precisionDigits: digits)
            }
            await self?.refreshSymbols()
        }
    }

    /// Whether Replay Session can act right now: a connected kernel (a
    /// replay against no worker would clobber every cached result with
    /// "Sage isn't running" errors), rows to replay, and no replay already
    /// in flight.
    var canReplaySession: Bool {
        controller != nil && kernelState.isConnected && !isReplaying && !session.rows.isEmpty
    }

    /// The V1.9 "Replay Session" command: restarts the worker (replay is
    /// defined against a FRESH namespace — V0.10 semantics) and re-sends
    /// each row's `sage` in tape order, so state-dependent rows
    /// (`A = matrix(...)` then `A.eigenvalues()`) succeed. Per row:
    ///   * required-variable preludes are re-emitted (`SessionReplay.preludes`,
    ///     the same policy submission uses);
    ///   * a NUMERIC row replays with its recorded `numeric` flag — replay
    ///     re-sends the REQUEST shape, not just the `sage`, so the restored
    ///     display matches what the user originally saw (SESSION-FORMAT.md
    ///     V1.8 note);
    ///   * provenance flips `cached → replayed` (original `cachedAt` kept);
    ///   * a DIFFERING result supersedes the cached envelope into
    ///     `supersededCache` (replace + keep + reason; artifact paths are
    ///     never compared — V0.10 policy);
    ///   * the file is re-saved after every replayed row (incremental).
    ///
    /// The whole replay is ONE serial-queue item, so a submission typed
    /// during a replay evaluates after it, in the replayed namespace.
    func replaySession() {
        guard let controller, canReplaySession else { return }
        isReplaying = true
        let rows = session.rows
        let restart = Task { await controller.restart() }
        enqueueKernelWork { [weak self] in
            defer { self?.isReplaying = false }
            await restart.value
            _ = await controller.evaluate(Self.bootPrelude)
            if let digits = self?.precisionNeedingReapply {
                _ = await controller.configure(precisionDigits: digits)
            }
            for row in rows {
                for prelude in SessionReplay.preludes(for: row) {
                    _ = await controller.evaluate(prelude)
                }
                let evaluation = await controller.evaluate(
                    row.sage, numeric: row.numeric == true)
                self?.applyReplay(rowID: row.id, with: evaluation)
                if let code = self?.tapeReferenceAssignmentCode(rowID: row.id) {
                    _ = await controller.evaluate(code)
                }
            }
            await self?.refreshSymbols()
        }
    }

    /// Applies one replayed outcome to its row: the new result becomes
    /// current with `.replayed` provenance; a differing cached envelope is
    /// retained in `supersededCache` (the V0.10 supersede policy, verbatim
    /// from `WorkerDriver.replay`).
    func applyReplay(rowID: SessionRow.ID, with evaluation: Evaluation, at date: Date = .now) {
        guard let index = session.rows.firstIndex(where: { $0.id == rowID }) else { return }
        var row = session.rows[index]
        if let cached = row.result, let replayed = evaluation.result,
           let reason = SessionReplay.difference(cached: cached, replayed: replayed) {
            row.supersededCache = SupersededCache(
                envelope: cached,
                cachedAt: row.provenance.cachedAt,
                reason: reason)
        }
        row.result = evaluation.result
        row.status = evaluation.status
        row.durationSeconds = evaluation.duration
        row.provenance = Provenance(
            kind: .replayed,
            cachedAt: row.provenance.cachedAt,
            replayedAt: date)
        session.rows[index] = row
        session.updated = date
        persist()
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
        switch CompiledInput.compile(input, tapeReferences: tapeReferences) {
        case let .ready(compiled):
            return compiled.origin == .friendly ? .generated(compiled.sage) : .rawSage
        case let .error(error):
            return .issue(message: error.message, suggestion: error.suggestion)
        case let .ambiguous(candidates):
            return .ambiguous(count: candidates.count)
        }
    }

    /// The formula-bar IR for drafts that begin with a known friendly
    /// command. It renders back to friendly input, so `#14` tape references
    /// and other app-side source forms stay untouched until
    /// `CompiledInput.compile`.
    var formulaIR: FormulaIR? {
        FormulaIR.parse(draft)
    }

    var integralFormula: IntegralFormulaIR? {
        guard case let .integral(ir) = formulaIR else { return nil }
        return ir
    }

    var unaryFormula: UnaryFormulaIR? {
        guard case let .unary(ir) = formulaIR else { return nil }
        return ir
    }

    var solveFormula: SolveFormulaIR? {
        guard case let .solve(ir) = formulaIR else { return nil }
        return ir
    }

    var derivativeFormula: DerivativeFormulaIR? {
        guard case let .derivative(ir) = formulaIR else { return nil }
        return ir
    }

    var limitFormula: LimitFormulaIR? {
        guard case let .limit(ir) = formulaIR else { return nil }
        return ir
    }

    var taylorFormula: TaylorFormulaIR? {
        guard case let .taylor(ir) = formulaIR else { return nil }
        return ir
    }

    var seriesRangeFormula: SeriesRangeFormulaIR? {
        guard case let .seriesRange(ir) = formulaIR else { return nil }
        return ir
    }

    var plotFormula: PlotFormulaIR? {
        guard case let .plot(ir) = formulaIR else { return nil }
        return ir
    }

    var implicitPlotFormula: ImplicitPlotFormulaIR? {
        guard case let .implicitPlot(ir) = formulaIR else { return nil }
        return ir
    }

    var parametricPlotFormula: ParametricPlotFormulaIR? {
        guard case let .parametricPlot(ir) = formulaIR else { return nil }
        return ir
    }

    func updateFormula(_ formula: FormulaIR) {
        let newDraft = formula.friendlyInput
        guard draft != newDraft else { return }
        draft = newDraft
    }

    func updateIntegralFormula(_ formula: IntegralFormulaIR) {
        updateFormula(.integral(formula))
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
        switch CompiledInput.compile(input, tapeReferences: tapeReferences) {
        case let .ready(compiled):
            submitCompiled(compiled, advancing: advancing, numeric: numericMode)
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
            advancing: pending.advances,
            numeric: numericMode)
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
    private func submitCompiled(
        _ compiled: CompiledInput, advancing: Bool, numeric: Bool = false
    ) -> SessionRow.ID {
        let rowID = append(compiled, numeric: numeric)
        inputHistory.record(compiled.raw)
        if advancing {
            draft = ""
        }
        evaluate(rowID: rowID, compiled: compiled, numeric: numeric)
        return rowID
    }

    /// Submits sidebar-initiated Sage (forget / inspect / rerun / an action's
    /// command) through the SAME path as typed input — compile, append a tape
    /// row, record history, evaluate on the serial kernel queue — WITHOUT
    /// touching the draft. Returns the new row's identity, or nil if the
    /// input doesn't compile to something submittable.
    @discardableResult
    private func submitProgrammatically(_ input: String) -> SessionRow.ID? {
        guard case let .ready(compiled) = CompiledInput.compile(
            input,
            tapeReferences: tapeReferences
        ) else { return nil }
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
    /// A row evaluated in numeric mode reruns numeric (the recorded flag,
    /// not the toggle's current state — rerun reproduces the original).
    func rerun(rowID: SessionRow.ID) {
        guard let row = session.rows.first(where: { $0.id == rowID }) else { return }
        guard rowIsLiveInKernel(row) else { return }
        let numeric = row.numeric == true
        switch CompiledInput.compile(row.input, tapeReferences: tapeReferences) {
        case let .ready(compiled):
            submitCompiled(compiled, advancing: false, numeric: numeric)
        case .ambiguous:
            submitCompiled(
                .chosenCandidate(raw: row.input, sage: row.sage),
                advancing: false, numeric: numeric)
        case .error:
            break  // a previously submitted input can't stop compiling
        }
    }

    // MARK: - Sidebar: result actions

    /// Actions tab primary click: submits an action's built command directly
    /// (the context-menu insert path is just `insertIntoDraft`) and selects
    /// the new row so the Inspector and Actions follow the fresh result.
    func evaluateActionCommand(_ command: String, sourceRowID: SessionRow.ID? = nil) {
        if let sourceRowID,
           let row = session.rows.first(where: { $0.id == sourceRowID }),
           !rowIsLiveInKernel(row) {
            return
        }
        guard let rowID = submitProgrammatically(command) else { return }
        select(rowID)
    }

    /// Card context menu → Approximate Numerically: evaluates the row's
    /// `approx` action command (`(<expr>).n()` — the same stateless command
    /// the Actions tab builds) as a fresh, visible tape row and selects it.
    /// The V1.8 "approximation is one click away" affordance for exact
    /// results, right on the card.
    func approximateNumerically(rowID: SessionRow.ID) {
        guard let row = session.rows.first(where: { $0.id == rowID }),
              rowIsLiveInKernel(row),
              let command = row.approximateCommand
        else { return }
        evaluateActionCommand(command, sourceRowID: rowID)
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
    private func evaluate(rowID: SessionRow.ID, compiled: CompiledInput, numeric: Bool = false) {
        guard let controller else { return }  // pre-kernel: row stays pending
        enqueueKernelWork { [weak self] in
            for prelude in compiled.preludes {
                _ = await controller.evaluate(prelude)
            }
            // `numeric` rides only on the row's own eval, never the preludes
            // (a `var('V')` echoes nothing to re-present anyway).
            let evaluation = await controller.evaluate(compiled.sage, numeric: numeric)
            guard let self else { return }
            complete(rowID: rowID, with: evaluation)
            if let code = tapeReferenceAssignmentCode(rowID: rowID) {
                _ = await controller.evaluate(code)
            }
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
    /// when the kernel answers. A numeric-mode submission records the flag on
    /// the row (`SessionRow.numeric`, the V1.8 additive field — nil, not
    /// false, for a normal eval so the persisted shape stays unchanged).
    @discardableResult
    func append(_ compiled: CompiledInput, numeric: Bool = false, at date: Date = .now) -> SessionRow.ID {
        let row = SessionRow(
            input: compiled.raw,
            sage: compiled.sage,
            result: nil,
            status: .running,
            timestamp: date,
            numeric: numeric ? true : nil
        )
        session.rows.append(row)
        session.updated = date
        persist()  // a crash now restores the row as honestly incomplete
        return row.id
    }

    /// Clears the visible/persisted tape without resetting the live Sage
    /// namespace. This is closer to a calculator "clear tape" than a kernel
    /// restart: variables still exist, but the transcript and selection are
    /// gone.
    func clearTape(at date: Date = .now) {
        guard !session.rows.isEmpty else { return }
        session.rows.removeAll()
        session.updated = date
        selectedRowID = nil
        restoredRowIDs.removeAll()
        persist()
    }

    /// Applies a finished evaluation to its pending row (the V1.3 seam).
    /// Unknown IDs are ignored (the row may have been removed meanwhile).
    func complete(rowID: SessionRow.ID, with evaluation: Evaluation, at date: Date = .now) {
        guard let index = session.rows.firstIndex(where: { $0.id == rowID }) else { return }
        session.rows[index].apply(evaluation, at: date)
        session.updated = date
        persist()  // incremental save after EVERY completed row (V1.9)
    }

    private func tapeReferenceAssignmentCode(rowID: SessionRow.ID) -> String? {
        guard let index = session.rows.firstIndex(where: { $0.id == rowID }) else { return nil }
        return tapeReferences.assignmentCode(for: index + 1)
    }

    /// Edits a row's input in place. Identity and timestamp are stable; the
    /// input is recompiled (through the real compiler) and the stale result
    /// is cleared, so the row honestly reads as not-yet-evaluated again.
    /// An edit that doesn't compile (error/ambiguous) leaves the row intact.
    func edit(rowID: SessionRow.ID, input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = session.rows.firstIndex(where: { $0.id == rowID }),
              case let .ready(compiled) = CompiledInput.compile(
                trimmed,
                tapeReferences: tapeReferences
              )
        else { return }
        session.rows[index].input = compiled.raw
        session.rows[index].sage = compiled.sage
        session.rows[index].result = nil
        session.rows[index].status = .running
        session.rows[index].durationSeconds = nil
        session.updated = .now
        restoredRowIDs.remove(rowID)  // its restored content is gone
        persist()
    }

    /// Flips a row's expanded/collapsed state (the V1.2 row field; V1.5's
    /// result cards give it a visible affordance).
    func toggleExpanded(rowID: SessionRow.ID) {
        guard let index = session.rows.firstIndex(where: { $0.id == rowID }) else { return }
        session.rows[index].expanded.toggle()
        persist()  // `expanded` is the one persisted UI-state field
    }

    func select(_ rowID: SessionRow.ID?) {
        selectedRowID = rowID
    }

    /// Place text in the input draft (History → "Insert into Input").
    func insertIntoDraft(_ text: String) {
        draft = text
    }
}
