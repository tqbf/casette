# Casette — Master Plan & Documentation Index

Casette is a native macOS calculator backed by SageMath: a calculator with a
persistent **session tape** (hence the name), live Sage state, rich math
rendering, and a progressive bridge from friendly commands to raw Sage.

This file is the **index**. In-depth docs live in `plans/`. The running log of
what actually happened lives in `PROGRESS.md`. Hard-won pattern lessons live in
`PROBLEMS.md`.

> New agent? Read **PLAN.md** then **PROGRESS.md** and you're caught up.

## Documents

| Doc | What it is |
| --- | --- |
| [plans/INITIAL.md](plans/INITIAL.md) | The full phased product plan (V0 proof-points → V1 app bring-up → V2 deferred). The source of truth for scope. |
| [plans/WORKER-PROTOCOL.md](plans/WORKER-PROTOCOL.md) | The stable JSONL protocol + result-envelope reference (fields, kinds, the V0.8 exact/numeric policy + `config`/`numeric`/`precision_digits` API, approx/actions, truncation, framing). V0.4+/V1 build against this. |
| [plans/MATH-RENDERING.md](plans/MATH-RENDERING.md) | V0.4 math rendering: the engine choice (SwiftMath, with the Textual + LaTeXSwiftUI verdicts), the surviving `MathRenderer` abstraction, capabilities/limits found on screen, and the V1.5 recommendation. |
| [plans/FRIENDLY-COMPILER.md](plans/FRIENDLY-COMPILER.md) | V0.7 friendly input compiler: the frozen grammar of accepted command forms, the raw-Sage bypass rule, the variable policy (`requiredVariables` + `var()` preludes), the structured error model, and how V1.4 integrates the pure Swift `FriendlyCompiler` library. |
| [plans/SAGE-DOCTOR.md](plans/SAGE-DOCTOR.md) | V0.9 Sage Doctor: the discovery priority order, version/floor policy, the check list, the `--json` report contract (the V1.10 boundary), the config-storage decision (JSON at Application Support), and the **Swift process-control** pattern (`posix_spawn`+`POSIX_SPAWN_SETSID`, group-kill, SIGINT the real pid) that retires the V1.3 risk. |
| [plans/SESSION-FORMAT.md](plans/SESSION-FORMAT.md) | V0.10 session persistence: the on-disk tape schema (header + rows + the render-ready envelope subset), storage-location policy, the cached-vs-replayed **provenance + supersede** policy, artifact path-refs + liveness (graceful degradation), atomic/incremental save + robust load (corruption quarantine, schema refusal), replay semantics, and the V1.2 (session model) / V1.9 (persistence) integration notes. |
| [SWIFTUI-RULES.md](SWIFTUI-RULES.md) | Imperative SwiftUI rules + the failure modes that taught them. Apply up front; use as a review checklist. |
| [PROGRESS.md](PROGRESS.md) | Dated running log of every meaningful change. |
| [PROBLEMS.md](PROBLEMS.md) | One entry per hard-won pattern lesson (constraint crashes, bundle-loading, etc.). |

## Architecture (target, per INITIAL.md)

```text
Native macOS UI (SwiftUI)
  ↕
SessionController
  ↕ JSONL over stdin/stdout
Sage worker  (sage -python worker.py)
  ↕
Persistent Sage namespace
```

Three UI regions: large results pane / session tape (left), tabbed sidebar
(Symbols / History / Inspector / Actions), bottom input pane.

## Build system

No Xcode IDE, no xcodebuild, no XcodeGen — Xcode is only a toolchain provider.

- `swift build` compiles the SwiftPM `Casette` executable target.
- `./build.sh [debug|release]` assembles `build/Casette.app` (Info.plist,
  icon, PkgInfo) and codesigns (ad-hoc fallback when no identity is set).
- `Makefile` drives it. `make help` lists targets. Key ones:
  - `make` / `make build` — debug build → `build/Casette.app`
  - `make check` — compile-only gate (CI / agent)
  - `make test` — SwiftPM test suite
  - `make run` — build + launch
  - `make icon` — regenerate `build/AppIcon.icns` (cassette glyph)
  - `make dist` — sign → notarize → staple → zip (needs a `vX.Y.Z` tag + signing identity)

## Status

**V1.1 done — the app shell exists and feels like the product.** The
three-region layout is real: a scrolling **session tape** (rests at the
bottom, follows appends), a **tabbed right sidebar** (Symbols / History /
Inspector / Actions) built as a macOS-14 **`.inspector`** with a toolbar
toggle + ⌘B View-menu command, and a prominent **bottom input pane** that
owns keyboard focus by default (`.defaultFocus` + root-owned `@FocusState`).
Everything is placeholder-driven: `TapeRow`/`SymbolEntry` mirror the frozen
WORKER-PROTOCOL/SESSION-FORMAT field names so V1.2's real model swaps in
without reshaping views; `ShellModel` (`@Observable`, `@MainActor`) is the
seam. Theme = semantic fonts only (monospaced design reserved for math/Sage
content) + a centralized `Theme` metrics enum. Submitting input appends an
honest "Not evaluated — Sage isn't connected yet" row (the kernel is V1.3).
`make check` / `make test` (9/9) / `make build` green; full V0 regression
re-run clean (see PROGRESS.md). **Next: V1.2 — session model** (lift the
v0/10 Codable types verbatim).

**V0 COMPLETE — the gate passed. The kernel bridge is proven end-to-end.** All
ten V0 proof-points are done, and every V0-completion-gate criterion from
INITIAL.md is covered by an executed proof, re-run one final time on 2026-06-11
with **zero failures and `pgrep` clean** (gate table in PROGRESS.md). The project
risk has shifted from "can this work?" to "can this become a good macOS app?"

**V0.10 done — the session tape persists and restores without a document model.**
A Swift SwiftPM package (`v0/10-persistence/`) ships `SessionStore` — the
surviving **library** (the prototype of V1.2's session model + V1.9's persistence,
designed to migrate verbatim) — a `casette-tape` **CLI/harness**, and **21**
swift-testing pure-logic units. It persists a real worker session to one
pretty-printed, human-inspectable `last-session.json` (`~/Library/Application
Support/Casette/sessions/` in V1; `$CASETTE_CONFIG_DIR` hermetic override),
**atomically + incrementally** (temp-write + rename after every row — crash-safety
is the point). Restore reconstructs inputs AND render-ready results
(`plain`/`latex`/`approx`/`exact`) with **Sage genuinely not spawned**; an
optional **replay** re-sends each row's `sage` into a fresh worker **in tape
order**, so state-dependent rows (`A = matrix(...)` then `A.eigenvalues()` → `[3,
2]`) succeed. Each row carries **provenance** (`cached` vs `replayed`, with
timestamps); a differing replay **retains the cached envelope** in
`supersededCache` (replace + keep + reason) so the difference is visible in the
data. **Missing artifacts degrade gracefully** — the V0.5 `/tmp` session-dir dies
with the worker, so a restored plot artifact is essentially always stale: it's
marked `missing`, the row still renders its plain text, and replay regenerates a
fresh artifact. Robust load handles corruption (quarantine + fresh), unknown
schema (polite refusal, file intact), and empty/missing (fresh). `WorkerProcess`
+ `LineReader` are **copied verbatim** from v0/09 (frozen evidence — V1 unifies
them into one `SageKernel`). **`swift test` 21/21 · `casette-tape all` 22/22**
against real Sage 9.5; `pgrep` clean. Frozen in plans/SESSION-FORMAT.md; lessons
in PROBLEMS.md.

**V0.9 done — Sage Doctor finds, tests, and reports a user-installed Sage, and
proves Swift can drive the worker (V1.3 risk retired).** A Swift SwiftPM package
(`v0/09-sage-doctor/`) ships `SageDoctor` — the surviving **library** (migrates
into the app at V1.10) — a `sage-doctor` **CLI**, and **32** swift-testing
pure-logic units (discovery ordering, version/floor policy, config store, report
formatting). It discovers Sage via a documented priority search (`--sage`
override → stored path → Homebrew/`/usr/local`/globbed `SageMath*.app`/conda →
`which sage`; all candidates reported), detects the version against a **9.5
floor** (below-floor warning band), and drives the canonical worker **end-to-end
from Swift**: boot, eval (`2+2→4`), state, LaTeX (`\sqrt{2}`), plot (artifacts on
disk), **interrupt** (SIGINT to the real banner pid → `interrupted` envelope),
**restart** (process-group kill → respawn → fresh-namespace `NameError`) — all
**ok** against real Sage 9.5. **This is the first proof Swift (not Python) can
spawn/drive/interrupt/orphan-free-kill `sage -python worker.py`** —
`Foundation.Process` can't `setsid`, so `WorkerProcess` uses **`posix_spawn` +
`POSIX_SPAWN_SETSID`**, `killpg` for the hard kill, and `kill(realPID,SIGINT)`
for interrupt, with a dedicated single-consumer `LineReader` thread. **=> the
V1.3 `SageKernel` risk is retired.** Failure diagnostics are proven by testing
broken setups (nonexistent `--sage` path → fails loud; non-sage executable;
hang-at-boot script; missing `worker.py`; below-floor version) — each an
actionable one-liner, never a stack trace, and **`pgrep` clean after every run
incl. interrupt/restart and the hang-at-boot case** (the orphan trap, closed in
Swift). Config persists as JSON at `~/Library/Application Support/Casette/`
(`--use`/`--forget`). Frozen in plans/SAGE-DOCTOR.md; Swift process lessons in
PROBLEMS.md; transcripts in the package README (`run-proof.sh`). No worker
regression (V0.9 doesn't touch the worker). **Next: V0.10** — session tape
persistence-lite.

**V0.8 done — exact/numeric is a complete, configurable product policy, proven
through the real worker.** The canonical worker
(`v0/01-worker-protocol/worker.py`, extended in place) now drives the spec's
"exact primary, approximation secondary" display
(`8/15` then `≈ 0.5333333333`). The value envelope gains four V0.8 fields —
**`exact` (true|false|null)**, **`primary_is_approx`**, **`approx_digits`**, and
(in force-numeric mode) **`exact_value`** — plus a session-level
**`config` op** (`precision_digits`, default 10), a **per-request
`precision_digits`** override, and a **per-request `numeric:true`** force-numeric
flag. The load-bearing insight: **exactness cannot be read off
`parent().is_exact()`** (the whole Symbolic Ring is `False`, which would mislabel
`sqrt(2)`/`pi`/`sin(1)`); it's decided per-kind, and for symbolic by a recursive
`operands()` tree-walk for inexact numeric atoms (so `sqrt(2)+pi` is exact,
`2.5+sqrt(2)` isn't). Force-numeric is **display-only** — it never pollutes the
namespace (`y = 1/3` with `numeric:true` leaves `parent(y)` an exact
`Rational Field`); precision is **clamped** to a concrete value's own `prec()` so
`.n(bits)` never raises. The harness (`v0/08-exact-numeric/`, **95/95**) asserts
primary/approx/exact-flag/precision for every spec + trap case and proves the
desired display is **derivable from one envelope with no worker round-trip**.
Frozen in plans/WORKER-PROTOCOL.md; traps in PROBLEMS.md. No regression: V0.1
18/18 · V0.2 35/35 · V0.3 97/97 · V0.5 88/88 · V0.6 24/24 · V0.7 e2e 19/19.
**Next: V0.9** — Sage Doctor / environment discovery.

**V0.7 done — friendly input compiles to Sage, in pure Swift, proven through the
real worker.** A standalone SwiftPM package (`v0/07-friendly-compiler/`) ships
`FriendlyCompiler` — a **pure** library (`String → CompileResult`, no I/O), the
surviving artifact written to migrate into the app — plus a `sagecalc-compile`
CLI (`--json`) and a 69-test swift-testing suite. It's a **command shim, not a
language**: a known command word + space → friendly (rewrite to a single Sage
expression); otherwise the input **bypasses** as raw Sage untouched
(`factor(x^4-1)`, `factorial(5)`, `2+2`, `A = matrix(...)` all pass through). All
16 spec forms compile to the exact reference Sage, including the **double-integral
nesting** (`double integral x*y, x=0..1, y=0..x` →
`integrate(integrate(x*y, (y, 0, x)), (x, 0, 1))` — inner binds the last range).
The result is structured: `success(generatedSage, requiredVariables)` /
`bypass(rawSage)` / `error(message, position?, suggestion?)` /
`ambiguous(candidates)`. **Parse errors are useful** (`integral x^2, x=0..` →
points at the incomplete range; unbalanced brackets carry a UTF-8 position).
**No implicit multiplication** — payloads pass through verbatim. **Variable
policy:** the compiler *reports* free vars in `requiredVariables` and never
injects; V1.4 emits `var('x')` preludes (the worker predefines only `x`).
**Three test layers all green:** `swift test` **69/69**; CLI smoke; **end-to-end
19/19** — every generated Sage piped through the real canonical worker with the
prelude policy, asserting `ok:true` + sensible kinds (solve→list,
eigenvalues→list, plot→plot+artifacts), the double integral == `1/8`, and the wire
intact. Frozen in plans/FRIENDLY-COMPILER.md. No leaked Sage workers. **Next:
V0.8** — exact/numeric display policy.

**V0.6 done — live symbol table works; the sidebar can show user variables
safely.** The canonical worker gained a read-only `symbols` op
(`v0/06-symbol-table/`, **24/24**): it snapshots the pristine namespace and
diffs the live one against it **by object identity**, returning only
user-created `{name, kind, summary}` entries. Spec sequence proven end-to-end —
`x` → `symbolic variable "x"`, `A` → `matrix "2×2 over Integer Ring"`,
`f(x)=sin(x)/x` → `symbolic function "x \|--> sin(x)/x"`, `n = 104729` →
`integer "104729"`, `del n` removes it, reassignment re-classifies. **No Sage
junk leaks** (`[]` before user code; a 23-name probe finds nothing). **Summaries
are bounded and cheap**: a 200×200 matrix → `"200×200 over Integer Ring"`, a
million-item list → `"list of 1000000 items"` — the whole op returns in **~0.6 ms**
over those, never stringifying them; a raising `__repr__` degrades to
`<unprintable: …>`. Identity-diff was load-bearing: Sage exports `n`/`N`/`i` as
builtins, so a name-only diff hid the spec's own `n` (PROBLEMS.md). Kind
vocabulary adds `symbolic variable / symbolic function / module / function` to
the V0.3 kinds; op frozen in plans/WORKER-PROTOCOL.md. No regression: V0.1 18/18,
V0.2 35/35, V0.3 97/97, V0.5 88/88. **Next: V0.7** — friendly input compiler.

**V0.5 done — plot artifacts move from worker to UI; render PNG (SVG corrupts on
macOS NSImage).** The canonical worker now turns a Sage `Graphics`/`GraphicsArray`
into image files and reports them in the envelope's `artifacts` array (SVG+PNG,
session-scoped dir `/tmp/sagecalc/session-<pid>-<rand>/`, monotonic
`plot-NNNNN` names that never collide, structured per-format save errors, a
clean-shutdown lifetime policy). A Python harness drives the spec's three plot
cases + multi-plot + failure through a live worker (**88/88**); a standalone
SwiftUI viewer (`v0/05-plot-artifacts/`, `CasettePlotProof`) loads the files and
renders a scrolling tape with a per-row SVG/PNG toggle, zoom sheet, and empty
state. **Verified on screen:** all three spec plots render correctly in **PNG**
(sine wave, two unit circles), multiple plots don't collide, and the failure case
is readable — but **`NSImage` mis-renders matplotlib SVG as a black blob over the
curve** (the `_NSSVGImageRep` glyph bug), so PNG is the path and SVG is kept only
for a future real SVG engine. No worker regression (V0.1 18/18, V0.2 35/35, V0.3
97/97). Artifact shape frozen in plans/WORKER-PROTOCOL.md; SVG-on-macOS trap in
PROBLEMS.md. (V0.6 — live symbols — is now **done**; see the top of this Status
section.)

**V0.4 done — math renders beautifully and reliably in SwiftUI.** A standalone
proof app (`v0/04-latex-rendering/`, executable `CasetteLatexProof`, not entangled
with the main app) renders the worker envelope's `latex` field as a scrolling tape:
all 5 spec snippets, real Sage-9.5 worker LaTeX, inline + block, an invalid-LaTeX
graceful fallback, and 40 bulk rows. **Engine: SwiftMath** (native Core Text,
offline) behind a surviving `MathRenderer` abstraction. **Textual verdict: not
viable** (macOS-15 floor + markdown-only math); the first fallback **LaTeXSwiftUI
(MathJax) also fell short** here — it fails braced sub/superscripts like `x^{8}` and
`\sum_{n=0}^{\infty}` (a JavaScriptCore-bridge defect), so we swapped engines behind
the abstraction with zero app-code change. Every exit criterion (inline, block,
matrices incl. Sage's `array`→`pmatrix`, dark mode, scrolling, failed-LaTeX
fallback, copy) was verified **on screen** via computer-use; copy double-checked via
`pbpaste`. Details + V1.5 recommendation in
[plans/MATH-RENDERING.md](plans/MATH-RENDERING.md); traps in PROBLEMS.md.

(V0.5 — plot & artifact pipeline — is now **done**; see the top of this Status
section.)

**V0.3 done — Sage results become a stable, renderable envelope.** The worker's
rough V0.1 `kind` is now a real result model (`v0/03-result-envelope/`, 97/97):
`_build_envelope` emits `kind` (a frozen 14-kind set), `plain`, `latex`, `repr`,
`approx` (per-kind numeric approximation, null where it makes no sense), per-kind
`actions` (UI-driving op menus), `artifacts`, and a `truncated` flag with explicit
caps for huge outputs (`list(range(10^6))`, `factorial(10^5)`). Unknown objects
(e.g. a `Permutation`) degrade to `repr`, never failure. The envelope is documented
and frozen in [plans/WORKER-PROTOCOL.md](plans/WORKER-PROTOCOL.md). Worker stays
canonical; V0.1 (18/18) and V0.2 (35/35) harnesses still pass — changes are additive.

(V0.4 — LaTeX rendering — is now **done**; see the top of this Status section.)

**V0.2 done — the kernel is controllable.** On top of the V0.1 worker protocol,
`v0/02-lifecycle/` proves the parent stays in command when Sage misbehaves: a
`SessionController` (reader thread → parent never blocks) with the eight-state
machine (idle/running/completed/error/interrupted/timed_out/crashed/restarting),
eval timeout, SIGINT interrupt **escalating to a hard process-group kill**,
restart-to-fresh-namespace, and crash detection (mid-eval + idle) — 35/35 checks.
Honest interrupt truth: **cysignals owns SIGINT and aborts mid-C Sage computation
promptly** (`factorial(10^8)` killed at +3s), but SIGINT isn't guaranteed, so the
escalation path is mandatory (see PROBLEMS.md). `controller.py` is the design
prototype of V1.3's `SessionController`; the worker stays canonical.

**V0.1 done — the kernel bridge works.** Hello-world SwiftUI app + build system
stand up (V0 bootstrap), and the Sage worker protocol (the first hard gate) is
proven: `v0/01-worker-protocol/` boots Sage, runs a JSONL eval protocol over
stdin/stdout, persists namespace state across evals, captures user stdout/stderr
(incl. raw fd writes) without corrupting the wire, returns structured errors,
and detects worker death — 18/18 checks. `worker.py` there is real app code.

## Roadmap (from INITIAL.md)

- **V0 — COMPLETE (gate passed).** proof-points: worker protocol →
  lifecycle/restart → result envelope → LaTeX rendering → plot artifacts → live
  symbols → friendly compiler → exact/numeric policy → Sage Doctor → session
  persistence-lite. **The kernel bridge is proven; the gate is green.** (Gate
  table in PROGRESS.md.)
- **V1** — app bring-up: shell/layout → session model → kernel integration →
  input pane → result rendering → sidebar → plots → exact/numeric → persistence
  → Sage Doctor in-app → result actions → keyboard pass → command palette →
  packaging.
- **V2 (deferred)** — bundled Sage, sandboxing, full document model, NL input,
  cloud sync, collaboration. Keep these out of V1.
