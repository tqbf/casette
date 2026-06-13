# Progress Log

## Summary

Casette is a native macOS SageMath-backed calculator with a persistent session tape. The project has completed the V0 proof sequence and V1.1 through V1.10 in the app: the SwiftPM app bundle builds locally, talks to a real Sage worker, renders math and plots, supports friendly input, exact/numeric controls, sidebar workflows, persistence/restore/replay/crash recovery, and now an in-app Sage Doctor for discovery and diagnostics.

Current gates are green: `swift test` (**637/637**, 97 suites), `make check`,
`make build`, and the worker envelope harness (**97/97**) passed for the
latest statistics/preload work. Detailed historical notes live in [`progress/`](progress/),
newest first. Hard-won bug lessons live in [`PROBLEMS.md`](PROBLEMS.md).

**Latest crash fix:** SwiftMath parser success is no longer treated as enough
to render LaTeX. A crash report showed `MTTypesetter.getInterElementSpace`
asserting while SwiftUI measured an `MTMathUILabel`; the stack passed through
nested `makeLeftRight` calls, matching nested `\left...\right` delimiter groups.
Casette now detects nested delimiter groups after Sage normalization and falls
back to the worker's plain text before SwiftMath can measure them. Sequential
delimiter groups and normalized Sage matrices still render as math. Focused
rendering tests cover tuple-list basis LaTeX, nested braces, sequential groups,
and normalized matrices. Details:
[`problems/027-swiftmath-can-parse-nested-left-right-groups-then-assert.md`](problems/027-swiftmath-can-parse-nested-left-right-groups-then-assert.md).
Validation: `make check`, `swift test` **637/637**, and `make build` green.

**Latest help-system work:** Casette now ships a native Help window for the
Friendly Compiler mini-language. The Help menu has **Friendly Compiler
Language**, opening a separate searchable reference window that covers the
current command families and shows generated Sage for each example. The content
is code-native (`HelpReference`) so it packages reliably with the SwiftPM app
bundle, and `HelpReferenceTests` guard representative command coverage plus the
key boundary rules. Validation: `make check`, `swift test` **634/634**, and
`make build` green. Details: [`plans/HELP-SYSTEM.md`](plans/HELP-SYSTEM.md).

**Latest bug fix:** Sage help output no longer makes the app appear hung.
`help(x)` for a symbolic expression can emit hundreds of KB of pydoc text; the
worker now caps captured stdout/stderr at 32,768 characters and appends a visible
truncation note, so the existing stdout block can show Sage help text without
overwhelming SwiftUI. The stdout view also renders only a 16,384-character
preview for restored rows, so a pre-fix persisted help row cannot slow app
startup. The V0.1 worker harness now covers `help(x)` as bounded stdout.
Validation: worker harness **19/19**, focused stdout display tests, `make check`,
`swift test` **632/632**, and `make build` green.
Details: [`progress/000-2026-06-13-sage-help-stdout-cap.md`](progress/000-2026-06-13-sage-help-stdout-cap.md).

**Latest statistics work:** [plans/STAT.md](plans/STAT.md)'s first and second
batches are implemented, backed by [plans/PRELOAD.md](plans/PRELOAD.md)'s
hidden worker preloads. The canonical worker now installs normal, binomial,
Poisson, exponential, and uniform helper functions before the symbol-table
baseline, so raw Sage can call `normal_between(-1, 1)` and
`binomial_cdf(3, n=10, p=.5)` without those helpers appearing in Symbols.
Friendly compiler Batch G adds 22 distribution commands with compact formula
bars and readable generated Sage; `lambda=` lowers to Python-safe `lambda_=`,
and `min=`/`max=` lower to `low=`/`high=`. Validation: `swift test`
**630/630**, `make check`, `make build`, and the worker envelope harness
**97/97**.

**Latest layout work:** The main tape/input boundary and the sidebar's
top/content boundary are now resizable with app-owned persisted dimensions
(`inputPaneHeight`, `sidebarTopPaneHeight`) alongside the existing sidebar
visibility/tab layout keys. The reusable vertical split container clamps panes
so both sides remain usable and stores changes through `@AppStorage`. The input
pane layout was tightened after live review: the editor now owns the full pane
width, with key hints and exactness/status controls moved to a secondary row so
they do not force an internal editor scrollbar in the middle of the pane.

**Latest calculator-variable maintenance:** The Sage boot prelude now
predefines `u`, `v`, `w`, `x`, `y`, `z`, `x1`...`x9`, `y1`...`y9`, and `t`.
The prelude is generated from `ShellModel.bootVariableNames`, and boot/restart
tests assert against that single source so the Symbols sidebar contract stays
honest. The Symbols tab now hides untouched built-in boot variables by default,
with a persisted **Show Built-in Variables** checkbox for users who want the
full namespace visible; reassigned names such as `x = 5` still appear. The
toolbar's Clear Tape control is now an icon-only trash button, with a matching
menu command that opens the same confirmation dialog.

**Latest maintenance:** Result actions now include **Trig Simplify** for symbolic rows and three basis-producing matrix actions: **Column Space** (`column_space().basis()`), **Row Space** (`row_space().basis()`), and **Right Kernel Basis** (`right_kernel().basis()`). The existing **Simplify** action remains the full simplification path (`simplify_full()`), so no separate `simplify_full` action is exposed. The worker action vocabulary, Swift command mapping, placeholder data, and worker-protocol docs were updated together. A live crash from `right_kernel().basis()` exposed a SwiftMath layout assertion for Sage tuple-list LaTeX (`\left[\left(...\right)\right]`): legacy tuple-list basis LaTeX now falls back before layout, and fresh worker envelopes render Sage `Sequence_generic` values whose elements are vectors as labeled column-vector bases (`\mathcal{B} = \left\{\begin{pmatrix}...\end{pmatrix}\right\}`). Validation: `swift test` **610/610**, `make check`, `make build`, and `v0/03-result-envelope/harness.py` **97/97**. Computer Use live pass on `build/Casette.app`: matrix basis actions rendered one- and two-vector bases in the screenshot-style LaTeX shape, and `sin(x)^2 + cos(x)^2` followed by Trig Simplify produced `1` with no crash.

**Matrix action extension:** Matrix result actions now always include **Change
Ring to RDF** (`change_ring(RDF)`). Matrices whose base ring is already `RDF` or
`CDF` also include **SVD**; the Swift action evaluates
`__casette_svd_labeled((M).SVD())`, and the worker's hidden preload helper
renders Sage's returned `(U, S, V)` triple as labeled `U = ...`, `S = ...`, and
`V = ...` matrices in both plain text and LaTeX. The action vocabulary,
placeholder rows, worker-protocol docs, worker harness, Swift action tests, and
real-Sage rendering/sidebar journeys were updated together.

**Previous maintenance:** Tape entries are now visibly numbered, and prompts can reuse the last 20 successful reusable tape expressions with `#ROW` syntax. Errors still occupy row numbers but are not valid references; missing/stale references surface as normal compile-preview errors. `#57` expands before friendly compilation to the private Sage dictionary lookup `__casette_tape_refs[57]`, and the worker dictionary is refreshed after successful evals and during Replay Session so restored sessions can rebuild reference state. The private dictionary is filtered out of the Symbols sidebar because it is app plumbing, not user-serviceable state. The app's default approximation precision is now 5 digits (configured at boot over the worker's native 10), and the precision menu includes 2- and 3-digit choices. Tests cover reference expansion, missing references, error-skipping with visible row numbers, the 20-entry window, replay rebuild, symbol filtering, default precision, and existing numeric/queue semantics; `swift test` is green at **302/302**.

**Formula autocomplete prototype:** The input pane now grows a compact
Numbers-style formula bar when the draft starts with `integral`/`integrate`.
The bar edits expression, variable, and the two optional definite bounds while
rewriting the source draft back to friendly input, not Sage. The shared IR is
`IntegralFormulaIR` in `FriendlyCompiler`; it preserves app-level source such
as `#14` tape references until `CompiledInput` expands them at the existing
compile boundary. The friendly compiler also accepts explicit indefinite
integrals as `integral expr, wrt var`. Focused tests cover `wrt`, IR rendering,
`#ROW` preservation/expansion, and model draft rewrites. `swift test` is green
at **305/305** and `make build` is green. The function chip is pinned outside
the argument lane, and the formula expansion now sits on its own full-width
lane below the input controls so the optional bounds are visible without
horizontal scrolling at the normal window size.

**Completion UI hitlist (2026-06-12, branch `fable/completion-hitlist`):** The
integral formula bar's architecture now covers **36 completions** across six
batches, all dispatched through one new seam: `FormulaIR` (FriendlyCompiler)
wraps each family's typed IR, `ShellModel.formulaIR`/`updateFormula` is the
single draft funnel, and `FormulaBarView` switches the hint lane. Every bar
follows the COMPLETION-UI.md Extension Rule — parse the draft, edit a typed
IR, render BACK to friendly input (never Sage), `#ROW` references preserved
verbatim until `CompiledInput`, optional args grouped as one semantic chip.
Implemented (trigger words): expand, factor, simplify, solve · derivative
(+optional order clause), limit (+optional left/right direction), taylor, sum,
product (new lowerings) · plot, parametric_plot, implicit_plot (new lowerings;
equation sugar `=`→`==`, bare expr → `== 0`) · matrix, vector, det/determinant,
inverse, transpose, rank, rref, eigenvalues, eigenvectors (matrix methods now
accept variables/expressions/tape refs: `det A` → `(A).det()`) · gradient,
jacobian, hessian, subs, numeric/approx/decimal, latex · var, assume, forget
(lowering only — a no-argument command needs no lane), choose, gcd, lcm,
factorial, is_prime, factor_integer/prime_factorization, mean (owned exact
lowering `sum(D)/len(D)`; Sage's global mean() is removed upstream).
**Deliberately deferred:** stddev (no stable Sage backend; an owned
sample-stddev expression repeats the payload three times — unreadable as
user-visible Generated Sage), the hitlist's solve `==0` normalization and plot
default range (each would flip a frozen V0.7 contract test: `solveWithoutEquals`,
`plotNoRange`), and the infix `n choose k` spelling (the shim only matches
leading command words). **Live-verified on screen** (computer-use, isolated
`CASETTE_CONFIG_DIR`): all 30 checked lanes match the integral bar's look/feel;
11 submitted results correct (sum k^2 1..10 → 385, det → −2, subs → 13, choose
→ 120, factor #1 + 2 → 2·3, …). The verification round also caught and fixed:
(1) partial range edits losing data — the IRs now re-parse through a tolerant
`parsePartialRange` (compiler lowerings stay strict) with a
`PartialEditInvarianceTests` net asserting no per-field edit sequence ever
drops typed text; (2) no keyboard path into the lane — Tab in the editor now
enters the token fields via the key-view loop when a lane is showing
(`.ignored` otherwise; Return still submits only from the editor); (3) long
equation payloads render-clipping at the fixed token ideal width — eq/eqn/
bindings/condition tokens now grow with content (capped 220pt). `make check` /
`make test` **608/608** / `make build` green.

**Previous maintenance:** Restored tape rows now read as **not live** until Replay Session recomputes them into the current Sage namespace. The tape still restores render-ready from disk, but cached rows are visually deemphasized and row-derived execution affordances (History rerun, plot regenerate, Approximate Numerically, and Actions-tab command buttons) are disabled/guarded so users do not fire commands against variables that are only present in the old persisted transcript. Replayed rows become live again and regain the normal affordances. A focused persistence test covers the stale-row guard; `make check`, `make test` (**298/298**), and `make build` are green.

**Current phase:** V1.10 complete — Sage Doctor in app. **Next:** V1.11 — Result Actions, starting by reconciling the existing V1.6 Actions-tab implementation with `plans/INITIAL.md`.

## Detailed Entries

| # | Entry | Status | Summary |
| ---: | --- | --- | --- |
| 0 | [Statistics + preload implementation](progress/000-2026-06-13-stat-preload-planning.md) | PASS | Hidden worker preload helpers plus normal/binomial/Poisson/exponential/uniform friendly commands and formula bars. |
| 1 | [V1.10: Sage Doctor in app](progress/001-2026-06-12-v1-10-sage-doctor-in-app-pass.md) | PASS | In-app Sage Doctor sheet, diagnostic checks, setup-failure recovery. |
| 2 | [V1.9: Session persistence and recovery](progress/002-2026-06-12-v1-9-session-persistence-and-recovery-pass.md) | PASS | Persistent session tape: restore, replay, crash recovery, layout memory. |
| 3 | [V1.8: Exact/numeric controls](progress/003-2026-06-12-v1-8-exact-numeric-controls-pass-live.md) | PASS | Exact/numeric display controls, precision menu, numeric replay semantics. |
| 4 | [V1.7: Plot rendering v1](progress/004-2026-06-12-v1-7-plot-rendering-v1-pass-live.md) | PASS | Inline PNG plot rendering, zoom sheet, missing-artifact honesty. |
| 5 | [V1.6: Sidebar v1](progress/005-2026-06-12-v1-6-sidebar-v1-pass-live-gate.md) | PASS | Symbols/History/Inspector/Actions sidebar workflows. |
| 6 | [V1.5: Result rendering v1](progress/006-2026-06-11-v1-5-result-rendering-v1-pass-live.md) | PASS | Math result rendering with SwiftMath and graceful fallbacks. |
| 7 | [V1.4: Input pane v1](progress/007-2026-06-11-v1-4-input-pane-v1-pass-live.md) | PASS | Input pane editing, preview, ambiguity picker, keyboard behavior. |
| 8 | [V1.3: Kernel integration](progress/008-2026-06-11-v1-3-kernel-integration-pass-live-gate.md) | PASS | Real Sage kernel connection, serial work queue, interrupt/restart. |
| 9 | [V1.2: Session model](progress/009-2026-06-11-v1-2-session-model-pass-live-gate.md) | PASS | Session row/envelope model lifted from V0.10. |
| 10 | [V1.1: App skeleton & layout](progress/010-2026-06-11-v1-1-app-skeleton-layout-pass.md) | PASS | Native app skeleton, three-region layout, build/run path. |
| 11 | [V0.10: Session tape persistence-lite](progress/011-2026-06-11-v0-10-session-tape-persistence-lite-pass.md) | PASS | Persistence proof and final V0 gate. |
| 12 | [V0.9: Sage Doctor / environment discovery](progress/012-2026-06-11-v0-9-sage-doctor-environment-discovery-pass.md) | PASS | Sage discovery/config/reporting proof. |
| 13 | [V0.8: Exact/numeric display policy](progress/013-2026-06-11-v0-8-exact-numeric-display-policy-pass.md) | PASS | Exact vs numeric worker policy proof. |
| 14 | [V0.7: Friendly input compiler (command shim → Sage)](progress/014-2026-06-11-v0-7-friendly-input-compiler-command-shim.md) | PASS | Friendly command compiler proof. |
| 15 | [V0.6: Live symbol-table introspection](progress/015-2026-06-11-v0-6-live-symbol-table-introspection-pass.md) | PASS | Live symbol-table introspection proof. |
| 16 | [V0.5: Plot & artifact pipeline](progress/016-2026-06-11-v0-5-plot-artifact-pipeline-pass-render.md) | PASS | Plot artifact pipeline proof. |
| 17 | [V0.4: LaTeX rendering in SwiftUI](progress/017-2026-06-11-v0-4-latex-rendering-in-swiftui-pass.md) | PASS | LaTeX rendering engine proof. |
| 18 | [V0.3: Result envelope & type classification](progress/018-2026-06-11-v0-3-result-envelope-type-classification-pass.md) | PASS | Result envelope classification proof. |
| 19 | [V0.2: Worker lifecycle, interrupts & restart](progress/019-2026-06-11-v0-2-worker-lifecycle-interrupts-restart-pass.md) | PASS | Worker lifecycle, interrupt, restart proof. |
| 20 | [V0.1: Sage worker protocol (the first real gate)](progress/020-2026-06-11-v0-1-sage-worker-protocol-the-first.md) | PASS | JSONL Sage worker protocol proof. |
| 21 | [Bootstrap: hello-world app + build system](progress/021-2026-06-11-bootstrap-hello-world-app-build-system.md) | done | Initial SwiftPM/macOS app build system. |
