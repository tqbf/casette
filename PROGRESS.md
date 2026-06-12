# Progress Log

## Summary

Casette is a native macOS SageMath-backed calculator with a persistent session tape. The project has completed the V0 proof sequence and V1.1 through V1.10 in the app: the SwiftPM app bundle builds locally, talks to a real Sage worker, renders math and plots, supports friendly input, exact/numeric controls, sidebar workflows, persistence/restore/replay/crash recovery, and now an in-app Sage Doctor for discovery and diagnostics.

Current gates are green: `make check`, `make test` (**297/297**, 47 suites), and `make build` passed at V1.10. Detailed historical notes live in [`progress/`](progress/), newest first. Hard-won bug lessons live in [`PROBLEMS.md`](PROBLEMS.md).

**Latest maintenance:** Friendly Compiler assignment rows now echo the assigned value in the tape. Simple assignments compile as `name = expr\nname`, so `A = [1, 2; 3, 4]` compiles to `A = matrix([[1,2],[3,4]])\nA` and renders the matrix in the same row; `A = Matrix([[1, 2], [2, 3]])` similarly renders `A`. MATLAB-style single-bracket literals still work in command and standalone forms. Actions-tab command rows now evaluate on primary click; right-click offers **Insert into Input** and **Copy Command**. The app toolbar now includes a prominent **Clear Tape** button with a destructive confirmation; it removes visible/persisted tape rows while leaving the live Sage namespace available. Packaging now patches SwiftMath's generated resource accessor so copied `.app` bundles load math fonts from `Contents/Resources` instead of crashing when the developer `.build` fallback is absent. Active app compiler and the V0.7 proof copy are both updated; focused compiler tests, V0 compiler tests, real-Sage integration, `make check`, `make test`, `make build`, and copied-app launch verification are green.

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
