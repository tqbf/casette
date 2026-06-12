# Progress Log

## Summary

Casette is a native macOS SageMath-backed calculator with a persistent session tape. The project has completed the V0 proof sequence and V1.1 through V1.10 in the app: the SwiftPM app bundle builds locally, talks to a real Sage worker, renders math and plots, supports friendly input, exact/numeric controls, sidebar workflows, persistence/restore/replay/crash recovery, and now an in-app Sage Doctor for discovery and diagnostics.

Current gates are green: `swift test` (**302/302**, 47 suites) passed for the latest tape-reference work; previous `make check`, `make test` (**298/298**, 47 suites), and `make build` gates were green before this maintenance pass. Detailed historical notes live in [`progress/`](progress/), newest first. Hard-won bug lessons live in [`PROBLEMS.md`](PROBLEMS.md).

**Latest maintenance:** Tape entries are now visibly numbered, and prompts can reuse the last 20 successful reusable tape expressions with `#ROW` syntax. Errors still occupy row numbers but are not valid references; missing/stale references surface as normal compile-preview errors. `#57` expands before friendly compilation to the private Sage dictionary lookup `__casette_tape_refs[57]`, and the worker dictionary is refreshed after successful evals and during Replay Session so restored sessions can rebuild reference state. The private dictionary is filtered out of the Symbols sidebar because it is app plumbing, not user-serviceable state. The app's default approximation precision is now 5 digits (configured at boot over the worker's native 10), and the precision menu includes 2- and 3-digit choices. Tests cover reference expansion, missing references, error-skipping with visible row numbers, the 20-entry window, replay rebuild, symbol filtering, default precision, and existing numeric/queue semantics; `swift test` is green at **302/302**.

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

**Completion UI Batch B:** Formula bars now also cover `derivative`, `limit`,
`taylor`, `sum`, and `product`. New keyword lowerings `sum`/`product` mirror the
definite-integral branch (`sum k^2, k=1..n` → `sum(k^2, k, 1, n)`, lowercase
symbolic Sage). The `derivative` lowering gained an optional trailing `, N`
order (comma form only; `derivative sin(x), 2` → `derivative(sin(x), x, 2)`)
and `limit` gained an optional `left`/`right` third clause
(`dir='-'`/`dir='+'`); both extensions are byte-identical to before when the new
clause is absent, so the frozen V0.7 contract is untouched. Four new IRs
(`DerivativeFormulaIR`, `LimitFormulaIR`, `TaylorFormulaIR`, and the
sum/product `SeriesRangeFormulaIR`) parse/round-trip back to friendly input and
preserve `#ROW` references; `FormulaIR` dispatch, `ShellModel` accessors, the
four bar views (the limit bar uses a `.menu` Picker for the direction), and
`FormulaBarView` are wired up. Bounds remain one semantic chip group. New
lowering/IR/round-trip/`#ROW` tests plus model-rewrite tests for sum and limit;
`make check` and `make test` green at **366/366**.

**Previous maintenance:** Restored tape rows now read as **not live** until Replay Session recomputes them into the current Sage namespace. The tape still restores render-ready from disk, but cached rows are visually deemphasized and row-derived execution affordances (History rerun, plot regenerate, Approximate Numerically, and Actions-tab command buttons) are disabled/guarded so users do not fire commands against variables that are only present in the old persisted transcript. Replayed rows become live again and regain the normal affordances. A focused persistence test covers the stale-row guard; `make check`, `make test` (**298/298**), and `make build` are green.

**Current phase:** V1.10 complete — Sage Doctor in app. **Next:** V1.11 — Result Actions, starting by reconciling the existing V1.6 Actions-tab implementation with `plans/INITIAL.md`.

## Detailed Entries

| # | Entry | Status | Summary |
| ---: | --- | --- | --- |
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
