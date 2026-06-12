## 2026-06-12 — V1.6: Sidebar v1 — PASS (live gate PASSED across three rounds + one orchestrator fix round)

**Live gate (opus verifier, computer-use) — PASS, all 13 checks.** Round 1
verified tests 1–8 on screen before the idle screen lock interrupted:
Symbols lists x/n/A/f live; boundary-aware double-click insert (`2*`+`n` →
`2*n` → 209458); Copy Sage (`n = 104729` scalar vs bare `A`); Inspect
(evaluates `A`, selects the row, flips to Inspector); Forget (visible
`del n` row, symbol gone); History Rerun (honest NameError after the
forget); Inspector Artifacts (SVG/PNG "On disk · NN kB", Copy Path verified
against the real file); Actions insert (`(A).det()` → Return → **-2**).
Round 2 (after unlock) verified Evaluate Now (factor → `(x + 1)^4`, fresh
row selected, Inspector follows), non-blocking sidebar during `sleep(8)`,
dark mode across all four tabs, clean exit — but FAILED the footer-wrap
check (Actions hint truncated with "…" at min sidebar width). The
orchestrator's first fix (pin the hint under the List with
`fixedSize(vertical: true)`) introduced — and the next verification round
caught — a far worse bug: **selecting a result ballooned the window's min
height to an unshrinkable 1598pt** (see the new PROBLEMS.md entry: a
wrapping fixedSize Text outside scroll content under
`.windowResizability(.contentMinSize)` is a min-height bomb; bisected by
measurement via AppleScript window probes + CGEvent clicks). Final shape:
the hint is an ordinary final row INSIDE the List — scroll content never
drives window min size, and a row's width proposal is real so it wraps.
Final round verified on screen: no balloon on selection, hint wraps to 3
full lines at min sidebar width with no ellipsis, Determinant smoke
(insert → Return → **-2**), quit clean, `pgrep` clean. `make test` 222/222
after the fix. **Watch item for V1.12/V1.14:** the per-action command
PREVIEWS truncate with "…" at narrow widths (by design, middle-truncated);
fine, but keep an eye on it.

**Session state is now visible AND useful.** All four sidebar tabs act: the
Symbols tab inserts / copies / inspects / forgets live variables through the
real kernel, the History tab reruns and reuses prior inputs, the Inspector
adds artifact references (path + liveness) to its detail set, and the Actions
tab builds real Sage commands from the envelope's per-kind `actions` and can
insert OR evaluate them — the V1.6 exit criterion, and the foundation V1.11
extends. Sidebar work never blocks the calculator: every sidebar evaluation
rides the same serial kernel queue submissions use, asynchronously.

### Design decisions (the ones V1.11 builds on)

- **Action→command strategy (`Model/ResultAction.swift`): stateless re-statement,
  no `ans`.** The worker has no answer variable, so a follow-up command wraps
  the row's own generated Sage: "det" on a `matrix([[1,2],[3,4]])` row builds
  `(matrix([[1,2],[3,4]])).det()`. Honest (the command is exactly what runs,
  visible in the input before evaluating), stateless (no hidden result
  references), replay-safe (re-evaluates correctly from the tape alone). Every
  frozen wire name maps to a title + behavior: ~33 command templates
  (`factor(E)`, `(E).is_prime()`, `(E).rref()`, …); `diff`/`integrate`/`solve`
  name the expression's first free variable via the SAME compiler heuristic
  the prelude policy uses (`FriendlyCompiler.freeVariables`), falling back to
  `x` — visible and editable, never hidden. `copy`/`copy_traceback` copy
  directly; plot actions (`save_png`/`save_svg`/`show`) are listed but inert
  until V1.7, with the reason in a tooltip; unknown future names degrade
  visibly (shown as themselves, inert), never crash. Command actions exist
  only when `SessionRow.reusableExpression` does: status ok, not a statement,
  single-line sage — multiline raw Sage and assignments honestly offer none.
- **Click = insert (preview-first); Evaluate Now on the context menu.** A
  clicked action puts its command in the input (focused — Return evaluates);
  right-click offers Evaluate Now (submits directly, selects the fresh row so
  Inspector/Actions follow it) and Copy Command. Each action row shows the
  concrete command under its title — V1.11's "actions generate visible Sage
  commands" is already true.
- **Forget is a visible tape row, not a silent op.** `forgetSymbol` submits
  `del name` through the NORMAL submit path (compile → row → serial queue →
  symbols refresh). Deliberate: the tape is the session log, and V1.9's
  replay re-sends rows in order — a silent namespace mutation would make a
  restored session diverge from what the user watched happen. The eval path's
  existing symbols refresh removes the entry; the draft is never touched.
- **Inspect evaluates the bare name.** Exactly what typing the name would do
  (REPL-honest, leaves a real result row), then selects the new row and flips
  the sidebar to the Inspector — possible because **tab selection moved from
  view `@State` to `ShellModel.sidebarTab`** (transient UI state, like
  selection, now testable).
- **Insert appends at the draft's end with identifier-boundary separation**
  (`2*` + `n` → `2*n`; `foo` + `n` → `foo n`). True at-cursor insertion isn't
  buildable — macOS 14's `TextEditor` exposes no cursor to the model (the
  documented V1.4 constraint) — and the cursor rests at the end in the common
  case, so append is the honest version. Double-click a symbol row = insert
  (same gesture as History).
- **Copy Sage is `name = value` only when that's real Sage:** scalar kinds
  (integer/rational/real/complex/boolean) whose bounded summary IS the value
  and isn't truncated; everything else copies the bare name (a matrix summary
  like "2×2 over Integer Ring" is a description, not a value).
  `SymbolEntry.sageSnippet`, unit-tested.
- **Rerun goes through the normal submit path:** a FRESH row at the tape end,
  original untouched, draft untouched, friendly preludes regenerated. An
  input that compiles ambiguous re-submits its RECORDED resolution
  (`row.sage` via `chosenCandidate`) — rerun never re-asks.

### What changed per surface

- **ShellModel:** `sidebarTab`; `insertSymbolIntoDraft` / `forgetSymbol` /
  `inspectSymbol` / `rerun(rowID:)` / `evaluateActionCommand`; one private
  `submitProgrammatically` funnel (compile → `submitCompiled(advancing:
  false)`) so every sidebar evaluation is a first-class row that never
  touches the draft. `submitCompiled` now returns the row ID.
- **Symbols tab:** rows gain the V1.6 action set — double-click inserts;
  context menu: Insert into Input / Copy Sage / Copy Summary / Inspect /
  Forget *name* (destructive role, divider-separated); accessibility actions
  mirror all three behaviors.
- **History tab:** context menu gains Rerun (plus the existing Insert into
  Input / Copy); newest-first unchanged.
- **Inspector tab:** new Artifacts section for rows that carry them —
  format, liveness ("On disk · 19 KB" / "Missing — rerun the row to
  regenerate it", quiet because missing is the NORMAL restored case,
  PROBLEMS.md V0.10), middle-truncated path with full-path tooltip and Copy
  Path. (`ArtifactInspectorRow`.)
- **Actions tab:** rebuilt from the preview-only V1.1 list into working
  rows (`ActionRowView`): title (default UI face — they're words, not Sage)
  over the concrete mono command, wired per the strategy above. The footer
  **wraps instead of truncating** (`.fixedSize(horizontal: false, vertical:
  true)`) — the V1.3 polish note, fixed.

### The V1.3 "first click on a sidebar tab sometimes needs a second click" report

Code audit found no defect: the segmented `Picker` is plain SwiftUI state
with no focus dependency, and tab switching has no async work. The most
plausible cause is standard macOS **click-through**: `NSSegmentedControl`
does not accept first mouse, so a click while the Casette window isn't key
only activates the window — and the automation harness frequently moves key
status between checks. Not reproducible headless; the live checklist below
verifies it explicitly (item 1) and tells the verifier what to capture if it
recurs while the window is demonstrably key.

### Gate (all PASS; live gate pending)

- `make check` ✓ · **`make test` 222/222** (33 suites; was 205 — +17:
  `ResultActionTests` ×8 (command mapping incl. the headline det wrap,
  variable-aware diff/integrate, behaviors, order, `reusableExpression`,
  `sageSnippet`), `SidebarFlowTests` ×7 over the fake transport (forget →
  `del n` on the wire as a visible ok row + symbols refreshed + draft
  untouched; rerun fresh-row/draft-untouched and prelude regeneration;
  inspect select+tab-flip; evaluate-action submit+select; insert spacing),
  `SidebarIntegrationTests` ×2 against REAL Sage 9.5 (forget round-trip
  `n = 104729` → `del n` → gone from symbols; matrix det action command
  `(matrix([[1,2],[3,4]])).det()` → `-2`, row selected)).
- **Full V0 regression:** V0.1 **18/18** · V0.2 **35/35** · V0.3 **97/97** ·
  V0.5 **88/88** · V0.6 **24/24** · V0.8 **95/95** · V0.7 swift **69/69** +
  e2e **19/19** · V0.9 swift **32/32** · V0.10 swift **21/21** (first run
  tripped a PRE-EXISTING parallel-test setenv race in the frozen v0/10
  suite — new PROBLEMS.md entry; clean on rerun and under `--no-parallel`).
  `pgrep -fl "sage -python|worker.py"` clean after everything.
- **Skills:** swiftui-pro — `onTapGesture` only with `count: 2` (the
  sanctioned tap-count case) + accessibility actions on every gesture row;
  the one finding applied: the disabled action row became a real disabled
  `Button` (consistent metrics, honest to assistive tech) instead of a
  dimmed label. macos-design — context menus on every actionable row (§7.4),
  destructive Forget carries its target name + `.destructive` role behind a
  divider, no confirmation (visible, recoverable, the row IS the receipt),
  preview-first click with Evaluate Now as the deliberate second step,
  native segmented control retained. typography — no new tokens; action
  titles moved mono→default face (chrome words), commands stay mono (Sage
  voice), per the frozen two-axis system.
- `make build` ✓ (bundled worker.py `cmp` byte-identical) · launched
  `build/Casette.app` via `open`: alive 12s with exactly ONE worker chain,
  AppleScript quit → `pgrep -fl "Casette|sage -python|worker.py"` clean.

### Known gaps (deliberate)

- Symbol insert is append-at-end, not at-cursor (macOS 14 TextEditor; above).
- Actions click inserts; per-action preview-vs-evaluate polish, richer
  per-kind menus (`characteristic polynomial`, `mod`, …) and plot actions
  are V1.11/V1.7.
- `diff`/`integrate`/`solve` name the FIRST free variable (editable in the
  input); a multi-variable picker is V1.11 territory.
- Sidebar evaluations join the serial queue — behind a long-running eval
  they wait their turn (status indicator + ⌘. already cover this).

### On-screen verifier checklist (V1.6 — pending)

In `build/Casette.app` (real Sage), verify on screen:

1. Launch, wait for "Sage ready", click the tape once (window key). Click
   each sidebar tab ONCE each — History, Inspector, Actions, Symbols: each
   switches on the FIRST click. (If one doesn't while the window is key,
   note which tab and whether anything had keyboard focus — V1.3 watch item.)
2. Evaluate `n = 104729` → Symbols lists `n · integer · 104729` (and `x`
   from boot). Evaluate `A = matrix([[1,2],[3,4]])` → `A · matrix · 2×2
   over Integer Ring` appears (sidebar updated after each eval).
3. Right-click `n` → menu reads Insert into Input / Copy Sage / Copy
   Summary / Inspect / — / Forget n. Copy Sage → `pbpaste` is
   `n = 104729`. Copy Sage on `A` → `pbpaste` is `A` (description summaries
   never masquerade as values).
4. Type `1 + ` (don't submit), double-click symbol `n` → the input reads
   `1 + n` with focus in the field (typing works immediately); Return →
   `104730`.
5. Right-click `A` → Inspect → a new tape row `A` evaluates (typeset
   matrix), it is SELECTED, and the sidebar lands on the Inspector showing
   kind `matrix`, Plain, Rendered preview, LaTeX, Generated Sage `A`, and a
   Duration.
6. Right-click `n` → Forget n → a `del n` statement row appears on the
   tape, `n` vanishes from Symbols, and the input draft is untouched.
7. History tab: entries newest-first. Double-click one → inserted into the
   focused input. Right-click `1 + n` → Rerun → a FRESH row evaluates at
   the tape end (now a NameError — n was forgotten; honest), the original
   row unchanged, draft untouched.
8. Evaluate `integral t^2, t=0..2` (→ 8/3), then History → Rerun it → 8/3
   again; the new row's expanded Generated Sage is the clean
   `integrate(t^2, (t, 0, 2))` (preludes regenerated, never shown).
9. Evaluate `plot sin(x), x=-pi..pi` → select the plot row → Inspector
   shows an Artifacts section: SVG and PNG rows with "On disk · ~N KB" and
   middle-truncated paths; right-click → Copy Path → `pbpaste` is a real
   `/tmp/sagecalc/...` path.
10. Select the matrix row (`A`) → Actions tab lists Determinant / Rank /
    Reduced Row Echelon / Eigenvalues / Transpose / Inverse, each showing
    its concrete command (e.g. `(A).det()`). Click Determinant → the input
    reads `(A).det()`, focused; Return → `-2`.
11. Right-click Rank → Evaluate Now → a `(A).rank()` row evaluates and
    becomes SELECTED; the Inspector/Actions now describe the fresh integer
    result (kind-aware follow-through).
12. Drag the sidebar to its minimum width → the Actions footer text WRAPS
    fully (no `…` truncation) — the V1.3 polish fix.
13. Evaluate `1/0`, select it → Actions shows Copy Traceback; click →
    `pbpaste` contains the traceback.
14. Non-blocking: evaluate `sleep(8)`; while it spins, switch all four
    tabs, scroll History, type in the input — everything stays responsive
    (sidebar never blocks the calculator). ⌘. interrupts as before.
15. Dark mode: all four tabs legible (menus, disabled plot actions'
    tooltips, artifact paths).
16. Quit ⌘Q → `pgrep -fl "Casette|sage -python|worker.py"` → empty.

**Next.** V1.7 — plot rendering v1 (the Inspector's artifact references and
the plot card chrome are waiting for the real PNG).

---
