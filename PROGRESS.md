# Progress Log

Append-only. Newest entries at the top. One entry per meaningful change:
what changed, what I learned, what surprised me.

---

## 2026-06-11 — V1.2: Session model — PASS (live gate PASSED)

**Live gate (opus verifier, computer-use) — PASS.** Full V1.1 regression sweep
intact on screen (focus, layout, ⌘B, selection→Inspector/Actions, History
insert, dark mode, resize/divider). New V1.2 behaviors verified: a submitted
row shows the honest "Not evaluated — Sage isn't connected yet." bolt.slash
presentation (no spinner); its Inspector shows Status/Raw/Generated Sage with
Plain/Approx/LaTeX/Duration correctly omitted; its context menu offers exactly
Copy Input + Copy Generated Sage (Copy Input verified via `pbpaste`). Quit
clean, `pgrep` clean. **Non-blocking note:** placeholder data seeds no
interrupted row, so the orange interrupted style is unverified-by-data —
verify live in V1.3 when interrupt exists, or seed a fixture.

**Did.** Replaced V1.1's placeholder `TapeRow`/`SymbolEntry` world with the real
session model behind the same UI. The V0.10 Codable types were **lifted
verbatim** into `Sources/Casette/Model/` — `SessionModel.swift` (`Session` /
`SessionRow` / `RowStatus` / `Provenance` / `SupersededCache`),
`PersistedEnvelope.swift` (`PersistedEnvelope` / `PersistedError` /
`PersistedArtifact` / `ArtifactStatus`), and `EnvelopeMapping.swift` (the
raw-wire → model boundary V1.3 will call) — kept byte-diffable against
`v0/10-persistence` (headers note the lift; app-side additions live in
`SessionRow+App.swift`). The persisted types ARE the live model — one world,
not two; V1.9's `SessionStore` is a drop-in. The V1.2 spec names
`ResultEnvelope`/`Artifact` are typealiases onto the lifted types.

**New app-side types (the non-persisted half of the V1.2 core-types list):**
- `CompiledInput` — the input-vs-sage split (raw, sage, requiredVariables,
  origin friendly/bypass). Until V1.4 wires `FriendlyCompiler` in, everything
  goes through `CompiledInput.bypass(_:)` (raw == sage), honestly.
- `Evaluation` — a kernel outcome (status / envelope / duration). The V1.3
  seam: `ShellModel.append(_:)` returns the pending row's ID,
  `complete(rowID:with:)` applies the evaluation in place (identity stable,
  provenance stamped `cached`-at-now like the V0.10 recorder).
- `KernelState` — the V0.2 eight-state machine (idle/running/completed/error/
  interrupted/timed_out/crashed/restarting) **plus `.notConnected`** for the
  app-side reality pre-V1.3. Helpers: `isConnected`, `canAcceptWork`. Live
  state, deliberately not Codable.
- `SymbolSnapshot` — `{entries, capturedAt}`, replaced whole per refresh
  (V0.6 semantics; §3.2 rebuild-don't-patch). `SymbolEntry` stays the element.

**Decisions (the load-bearing ones).**
- **"Not evaluated" is presentation, not a new status.** `RowStatus` stays
  frozen (ok/error/interrupted/running; SESSION-FORMAT.md semantics: `running`
  = *incomplete*, not a result). A submitted row with no kernel is appended as
  `.running` with `result == nil`; the tape decides the honest message from
  `KernelState` — `.notConnected` → "Not evaluated — Sage isn't connected
  yet." (bolt.slash, same V1.1 copy), connected → spinner + "Evaluating…".
  V1.3 therefore needs **zero model change** on submit.
- **UI state out of the result data.** The exit criterion targets *result
  data*: `PersistedEnvelope` carries zero UI fields (tested — encoding is
  byte-identical across UI-state flips, and its vocabulary contains no
  expanded/selected/hovered). Transient UI state (selection, draft, kernel
  presentation) lives only on `ShellModel`, never Codable. The one durable UI
  field, `SessionRow.expanded`, stays on the row **because SESSION-FORMAT.md
  schema v1 persists it** (tape restores collapsed/expanded) — it's session
  state like a notebook's cell fold, and it sits outside `result`, so flipping
  it can never change what a result *is*.
- **`ShellModel` keeps its name and stays the `@Observable @MainActor` seam**,
  now wrapping a real `Session` (`session.updated` bumped on every mutation).
  New API: `append`/`complete`/`edit` (recompile + clear stale result, ID
  stable)/`toggleExpanded`. Views read envelope fields (`row.result?.plain`,
  `.approx`, `.actions`, `.error?.type`); derived helpers (`isStatement`,
  `isPlot`, `isPending`, `errorType`, `duration`) are computed, never stored.
- **Interrupted rows render** (orange type-line over message — error anatomy,
  different tint; rows differ by text too, so it's not color-only).
  PlaceholderData now exercises the artifact path-ref shape: the plot row
  carries svg+png `PersistedArtifact`s marked `missing` (the expected restored
  state per PROBLEMS.md V0.10).

**Deviation from SESSION-FORMAT.md: none.** Field names, Codable keys, enum
raw values, and semantics are identical (pinned by a test that asserts the
encoded JSON speaks the frozen vocabulary, `schemaVersion : 1` included).

**Gate.** `make check` ✓ · `make test` **34/34** (6 suites: Session model /
ShellModel / PlaceholderData / CompiledInput / KernelState / envelope
mapping — every V1.2 exit criterion has a named test) · `make build` ✓ ·
launched the .app, alive 13s, killed clean, no strays. **Full V0 regression,
all green:** V0.1 **18/18** · V0.2 **35/35** · V0.3 **97/97** · V0.5 **88/88**
· V0.6 **24/24** · V0.7 **69/69 + e2e 19/19** · V0.8 **95/95** · V0.9
**32/32** · V0.10 **21/21**. `pgrep -fl "sage -python|worker.py"` clean.

**Skill reviews applied (swiftui-pro / macos-design).**
- swiftui-pro: Actions-tab empty state is now three-way honest ("select a
  result" / "hasn't been evaluated yet" / "no actions"), with the copy logic
  out of `body`; the running row's spinner+text combine into one
  accessibility element (a bare ProgressView reads as an anonymous "in
  progress"). Accepted, documented deviations: the two lifted model files
  keep multiple types per file (verbatim-lift diffability beats one-type-
  per-file here); tape-row selection stays `onTapGesture` +
  `.accessibilityAddTraits(.isButton)` (V1.1-vetted — a Button fights text
  selection).
- macos-design: semantic `.red`/`.orange` status tints (dark mode free),
  native small-ProgressView idiom, no structural insert/remove (§1.1), no
  layout/chrome changes. Typography untouched → typography-designer not run.

**Learned / surprised.** Nothing PROBLEMS.md-worthy — the phase was the
payoff of V0.10 writing the types for verbatim migration: the lift compiled
first try, and the only real design work was deciding where "not evaluated"
lives (answer: in the *presentation*, derived from row + `KernelState`, so
the frozen on-disk enum never grows an app-only case).

**Live gate (pending — on-screen verifier).** Everything V1.1 verified should
look/behave **identically** (layout, ⌘B/toolbar/menu sidebar toggle, focus in
input, selection → Inspector/Actions, History double-click insert, tape
bottom-rest + follow-append, dark mode, Copy Result via pbpaste). New to
exercise: submit `2+2` → pending row reads "Not evaluated — Sage isn't
connected yet." with bolt.slash (NOT a spinner); select it → Inspector shows
"Status: Not evaluated" + Raw/Generated Sage, Actions tab says "This row
hasn't been evaluated yet."; the `1/0` row still red with ZeroDivisionError;
plot placeholder row still renders its caption box; `≈ 0.5333333333`
secondary line still present on `1/3 + 1/5`.

**Next.** V1.3 — kernel integration: unify v0/09+v0/10's `WorkerProcess` /
`LineReader` into one `SageKernel`, drive `KernelState`, and wire
`append`/`complete` to real evaluations via `PersistedEnvelope(workerResponse:)`.

---

## 2026-06-11 — V1.1: App skeleton & layout — PASS

**Did.** Replaced the hello-world `ContentView` with the real three-region
shell in `Sources/Casette/` (18 source files, one type per file):

- **Layout container:** the main content is `VStack { SessionTapeView /
  Divider / InputPaneView }` with the tabbed sidebar attached as a macOS-14
  **`.inspector(isPresented:)`** — the modern idiom for a right-side
  inspector-style panel (full height like Xcode/Keynote, system resize handle
  via `inspectorColumnWidth(min: 240, ideal: 280, max: 400)`). Toggle =
  toolbar button (`sidebar.trailing`, `.primaryAction`) **plus** a proper
  View-menu item carrying **⌘B**, wired through
  `FocusedValues`/`@FocusedBinding` (`SidebarToggleCommands`) so it's
  discoverable in the menu bar and disabled with no window focused.
- **Session tape:** `ScrollView` + `LazyVStack`, `defaultScrollAnchor(.bottom)`
  (calculator-tape semantics) + `ScrollViewReader` follow-append. Rows render
  input echo + timestamp over a result that switches on shape: value (+ the
  V0.8 `≈ approx` secondary line), statement (no output), error
  (type + message in red), plot (placeholder thumbnail box — V1.7 renders the
  real PNG), not-evaluated. Selection (tap) drives Inspector/Actions tabs;
  hover/selected backgrounds per SWIFTUI-RULES §7.2; context menus copy
  input / generated Sage / result / LaTeX (all real, nothing stubbed).
- **Sidebar tabs:** segmented control (Xcode-inspector style) over Symbols
  (name/kind/summary rows), History (newest first; double-click or
  context-menu **Insert into Input** — genuinely sets the draft + refocuses
  input), Inspector (grouped `Form` of the envelope fields: kind, plain,
  approx, LaTeX, raw input, generated Sage, duration, time), Actions (the
  per-kind `actions` list, rendered as labels not stubbed buttons, with an
  honest "runs once Sage is connected" footer). Every tab has a designed
  `ContentUnavailableView` empty state.
- **Focus model:** root-owned `@FocusState` + `.defaultFocus($isInputFocused,
  true)` + a `.task` fallback — input owns keyboard focus on launch; sidebar
  insert hands focus back via a `focusInput` closure.
- **Placeholder data (`PlaceholderData`):** 11 product-shaped rows (integer,
  rational + approx, symbolic, assignments, friendly-compiled `factor x^4-1`,
  long polynomial, eigenvalues list, solve, plot, `1/0` error) with faithful
  kinds/LaTeX/actions from the frozen contracts; 4 symbols matching the
  worker `symbols` op shape. `ShellModel` (`@Observable @MainActor`) is the
  V1.2/V1.3 seam: rows, symbols, selection, draft, `submitDraft()` (appends
  an honest `.notEvaluated` row — no kernel until V1.3).
- **Theme (`Theme` enum):** centralized metrics (8-grid) + a two-axis type
  system — semantic styles only for scale (caption/callout/body/title3),
  monospaced design reserved for math/Sage content, weight carries emphasis
  (medium result hero, semibold symbol names), de-emphasis via
  .secondary/.tertiary. Dark mode is free (semantic styles/materials only;
  input pane on `.bar`, inspector gets system material).

**Gate.** `make check` ✓ · `make test` **9/9** (new ShellModel +
PlaceholderData suites) · `make build` ✓ (ad-hoc signed, verifies) · launched
the .app twice, alive 16s+ (constraint crashes fire in the first display
cycle), killed clean, no strays. **Full V0 regression, all green:** V0.1
**18/18** · V0.2 **35/35** · V0.3 **97/97** · V0.5 **88/88** · V0.6 **24/24**
· V0.7 **69/69 + e2e 19/19** · V0.8 **95/95** · V0.9 **32/32** · V0.10
**21/21**. `pgrep -fl "sage -python|worker.py"` clean.

**Skill reviews applied (swiftui-pro / macos-design / typography-designer).**
- swiftui-pro: manual `FocusedValueKey` → the **`@Entry` macro**;
  `contentShape(Rectangle())` → `.contentShape(.rect)`; tap-selected tape row
  got `.accessibilityAddTraits(.isButton)` (a Button would fight text
  selection + hover); History double-click got an
  `accessibilityAction(named: "Insert into Input")`; if/return →
  if-expressions; `task()` over `onAppear`; `Duration.formatted(.units)` for
  eval times (no C-style formatting); sidebar list rows
  `.listRowSeparator(.hidden)` (§4.3).
- macos-design: confirmed `.inspector` over NavigationSplitView/HSplitView
  for a right-side utility panel; menu-bar parity for ⌘B; sparse toolbar;
  empty states everywhere; opacity-faded "return to evaluate" hint (never
  insert/remove, §1.1).
- typography-designer: the two-axis scale above; removed a confusing
  whole-picker `.help`; timestamps/meta at `.caption` only for metadata.

**Live gate (opus verifier, computer-use) — PASS, all 10 checks.** Verified on
screen: launch-fast + focus lands in input (typed `2+2` with zero clicks,
Return appended an honest "Not evaluated" row, focus retained); three-region
layout reads as a real Mac app; ⌘B + toolbar + View-menu all toggle the
sidebar; row selection drives Inspector (kind/plain/approx/LaTeX/Sage/duration)
and Actions (kind-appropriate, honest "runs once Sage is connected" footer);
History double-click inserts into input with focus; tape rests at bottom and
scrolls smoothly with the `≈ 0.5333333333` line, red `1/0` error row, and plot
placeholder all present; resize + inspector-divider drag never break layout;
dark mode fully legible; Copy Result verified via `pbpaste`; app responsive
after everything, quit clean, no stray processes. **Non-blocking polish notes
for later passes:** min window width is ~900pt (can't reach 720-wide; revisit
if a compact window matters); right-clicking directly on selectable result
*text* shows the OS text menu instead of the custom Copy menu (background
right-click shows the custom one); selecting a row doesn't auto-reveal the
Inspector tab.

**Learned / surprised.**
- `#expect(rows.contains(where: \.isPlot))` does not compile under
  swift-testing — the macro rewrites `contains(where:)` into a context where
  the key-path-as-function argument is treated as throwing. Use a closure
  (`rows.contains { $0.isPlot }`) inside `#expect`.
- `pgrep -fl "sage"` is a useless cleanliness check on a real Mac — it
  matches `iconservicesagent`, `MessagesBlastDoorService`, `UsageTracking…`.
  The discriminating check is `pgrep -fl "sage -python|worker.py"`.

**Next.** V1.2 — session model: lift `Session`/`SessionRow`/
`PersistedEnvelope`/`PersistedArtifact`/`Provenance`/`RowStatus` from
v0/10-persistence verbatim, replace `TapeRow` placeholder fields with the
real types, keep `ShellModel` as the view-facing seam.

---

## 2026-06-11 — V0.10: Session tape persistence-lite — PASS · **V0 COMPLETE (gate passed)**

**Did.** Built session persistence as a Swift SwiftPM package
(`v0/10-persistence/`): a `SessionStore` **library** (the surviving artifact — the
prototype of V1.2's session model + V1.9's persistence), a `casette-tape`
**CLI/harness**, and **21 swift-testing** pure-logic units. The Codable types
(`Session` / `SessionRow` / `PersistedEnvelope` / `PersistedArtifact` /
`Provenance` / `RowStatus`) mirror the V1.2 core-types list and the frozen
WORKER-PROTOCOL.md envelope, and are written to migrate into the app **verbatim**.
`WorkerProcess.swift` + `LineReader.swift` are **copied verbatim** from
`v0/09-sage-doctor` (frozen evidence — not refactored); V1 should unify them into
one `SageKernel`. **`swift test` 21/21 · `casette-tape all` 22/22** against real
Sage 9.5. `pgrep -fl "sage -python|worker.py"` clean.

**Exit criteria — all PASS (executed evidence in README):**
- **Last session tape restored** — record a real 5-row worker session
  (friendly-compiled `factor x^4 - 1` + raw-Sage bypasses incl. a
  state-dependent `A = matrix(...)` then `A.eigenvalues()`), persisted
  **incrementally + atomically** after every row; `load()` reconstructs it.
- **Inputs + rendered results survive restart, Sage NOT involved** — Phase 2
  restores with the worker **genuinely never spawned**; restored row 0's
  `plain`/`latex` match what was saved, row 1 renders `8/15` + `≈ 0.5333333333`
  with `exact=true` from one persisted envelope, no round-trip.
- **Optional replay into a fresh worker** — re-send each row's `sage` in tape
  order into a fresh worker; the state-dependent `A.eigenvalues()` → `[3, 2]`
  **because order is preserved** (A established first).
- **Replayed vs cached distinguishable** — provenance flips `cached → replayed`
  with a fresh `replayedAt` (keeping the original `cachedAt`); a deterministic
  row's value is unchanged (only provenance flips). A **differing** replay
  retains the cached envelope in `supersededCache` (policy: replace current, keep
  old + reason) — proven by forcing a wrong cache (`999`) and replaying `1+1`→`2`.
- **Missing artifacts degrade gracefully** — persist a plot row, delete the
  artifact files (the V0.5 `/tmp` session-dir-dies-with-worker case, which is the
  EXPECTED case on restore), restore → artifacts marked `missing`, row still
  renders with `plain` + `kind:plot`; replay regenerates fresh present artifacts.
- **Robustness** — corrupt JSON → quarantined aside + fresh start (no crash);
  unknown schema (9999) → polite refusal, file left intact; empty/missing → fresh.

**Storage policy.** One `last-session.json` rewritten in place (NOT
document-oriented): `~/Library/Application Support/Casette/sessions/` in V1,
`$CASETTE_CONFIG_DIR/sessions/` for the hermetic proof. Pretty-printed, sorted
keys, unescaped slashes, ISO-8601 dates → human-inspectable. Frozen in
plans/SESSION-FORMAT.md (schema, field choices, provenance/supersede policy,
replay semantics, V1.2/V1.9 integration notes).

**Learned / surprised.**
- **A "missing artifact" is the normal case, not an error.** PROBLEMS.md V0.5
  said the worker's `/tmp/sagecalc/session-<pid>-<rand>/` dir dies with the
  worker — so on a real relaunch a plot artifact is **essentially always stale**.
  Modeling `missing` as expected (row restores with plain text; replay
  regenerates) rather than as a failure is what makes restore robust.
- **Difference detection must ignore artifact PATHS.** A fresh worker writes new
  `/tmp` paths every replay, so a naive envelope `==` would flag every plot row as
  "superseded." The supersede check compares kind/plain/latex/approx and the
  artifact FORMAT set, never paths — so a deterministic tape shows zero spurious
  supersession.
- **Schema version must be PEEKED before the strict decode.** A
  forward-incompatible future shape would fail strict `Codable` decoding and get
  mis-quarantined as "corrupt." Reading just `schemaVersion` via
  `JSONSerialization` first lets restore refuse the future **politely** and leave
  the file intact for a newer app. (PROBLEMS.md.)
- **`FileManager` isn't `Sendable`** — a struct holding one can't be `Sendable`
  under Swift 6 strict concurrency. Dropped the conformance (the store doesn't
  need it); a top-level CLI `let` is `@MainActor`-isolated, so free helper
  functions take the checklist as a parameter rather than referencing a global.

### V0 COMPLETION GATE — **PASSED** (all prior harnesses re-run this date, clean)

Every gate criterion from INITIAL.md is covered by an executed proof, re-run one
final time today with **zero failures and `pgrep` clean**:

| Gate criterion (INITIAL.md) | Proof | Result |
| --- | --- | --- |
| Sage worker protocol is reliable | v0/01 harness | **18/18** |
| Worker can be killed and restarted | v0/02 harness (+ v0/09 restart, from Swift) | **35/35** (+ ok) |
| Common Sage results can be classified | v0/03 harness | **97/97** |
| LaTeX renders in SwiftUI | v0/04 (on-screen, prior) + v0/08 latex fields | verified (SwiftMath) |
| Plots can render as artifacts | v0/05 harness (+ on-screen PNG verdict, prior) | **88/88** |
| Live symbols can populate a sidebar | v0/06 harness | **24/24** |
| Friendly command compiler proves the interaction model | v0/07 swift test + e2e | **69/69 + 19/19** |
| (V0.8 exact/numeric policy) | v0/08 harness | **95/95** |
| (V0.9 Sage Doctor — Swift drives the worker; V1.3 risk retired) | v0/09 swift test + real doctor run | **32/32 + all checks ok** |
| (V0.10 session persistence) | v0/10 swift test + casette-tape all | **21/21 + 22/22** |

**Verdict: V0 COMPLETE.** The kernel bridge is proven end-to-end; the project
risk now shifts from "can this work?" to "can this become a good macOS app?"
**Next frontier: V1.1** — app skeleton & layout.

## 2026-06-11 — V0.9: Sage Doctor / environment discovery — PASS (and **Swift can drive the worker — V1.3 risk retired**)

**Did.** Built the Sage Doctor as a Swift SwiftPM package
(`v0/09-sage-doctor/`): a `SageDoctor` **library** (the surviving artifact,
migrates into the app at V1.10) + a `sage-doctor` **CLI** + **32 swift-testing**
pure-logic units. It discovers a user-installed Sage, detects its version against
a 9.5 floor, drives the canonical worker end-to-end, and reports each check
`ok`/`FAIL`/`skipped` with actionable detail (human report + `--json` contract).

**Headline: this is the first proof that Swift — not Python — can spawn, drive,
interrupt, and orphan-free hard-kill `sage -python worker.py`.** All seven
worker checks pass against real Sage 9.5 *from Swift*: boot, eval (`2+2→4`),
state-persistence, LaTeX (`sqrt(2)→\sqrt{2}`), plot (artifacts on disk),
**interrupt (SIGINT to the real banner pid → `interrupted` envelope)**, and
**restart (process-group kill → respawn → fresh namespace `NameError`)**.
**`pgrep` clean after every run, including interrupt/restart and the deliberate
hang-at-boot fixture.** => **The V1.3 `SageKernel` risk is retired.**

**Swift process-control story (the V1.3 dry run).** `Foundation.Process` exposes
no `start_new_session` knob, so `WorkerProcess` drops to **`posix_spawn` with
`POSIX_SPAWN_SETSID`** (the Swift equivalent), wiring stdin/stdout via
`posix_spawn_file_actions`. Hard-kill is `killpg(getpgid(pid), SIGKILL)` (wrapper
+ worker together); interrupt is `kill(realPID, SIGINT)` to the banner pid;
cysignals is left in charge (never reinstall the handler). A dedicated
`LineReader` thread drains stdout (raw `read()` → JSONL → locked queue), with the
control thread the sole consumer (mirrors `controller.py`). Boot-failure
`hardKill()`s before throwing, so a hung wrapper + its children never leak.

**Discovery & config.** Priority search: `--sage` override → stored path →
well-known paths (Homebrew arm/intel, `/usr/local`, **globbed `SageMath*.app`
bundles**, conda prefixes) → `which sage`; all candidates reported, first
existing selected, pure/injectable so it's unit-tested with no Sage. Config is a
JSON file at `~/Library/Application Support/Casette/sage-doctor.json` (`--use`
stores, `--forget` clears; `CASETTE_CONFIG_DIR` keeps the proof hermetic).

**Failure diagnostics — proven by testing broken setups** (each an actionable
one-liner, no stack trace, no orphan): nonexistent `--sage` path (**fails loud**,
doesn't fall through), a non-sage executable (`/bin/ls`), a sage-like script that
hangs at boot, a missing `worker.py`, and a below-floor (9.2) version warning.

**Exit criteria — all met:** manual binary selection ✓ · common paths searched ✓
· version detected ✓ · `sage -python worker.py` works **from Swift** ✓ · useful
failure diagnostics ✓ · configured path stored ✓. No worker regression — V0.9
doesn't touch the worker. `pgrep` clean.

**Learned / surprised.**
- **`Foundation.Process` can't put a child in its own process group** — no
  `setsid`, no pre-exec hook. You must drop to `posix_spawn` +
  `POSIX_SPAWN_SETSID` to get the group-kill semantics the orphan-avoidance
  strategy depends on. (PROBLEMS.md.)
- **An explicit override that doesn't exist will silently fall through** if you
  treat it as just another candidate — `--sage /typo` ran the *real* Sage and
  hid the typo. An explicit override must fail loud. (PROBLEMS.md.)
- **The macOS SageMath app layout is not where you'd guess** — the binary is at
  `Contents/Resources/sage/sage` (plus a top-level `sage` symlink), and the
  `SageMath-9-5.app` here ships **no** `sage` binary at all — a real
  searched-but-empty candidate the discovery report shows honestly.

Frozen in plans/SAGE-DOCTOR.md; Swift process lessons in PROBLEMS.md; full
transcripts in `v0/09-sage-doctor/README.md` (reproduce via `run-proof.sh`).
**Next: V0.10** — session tape persistence-lite.

---

## 2026-06-11 — V0.8: Exact/numeric display policy — PASS

**Did.** Hardened V0.3's per-kind `approx` into a complete, configurable
exact/numeric **product policy** in the **one canonical worker**
(`v0/01-worker-protocol/worker.py`, extended in place). New harness
(`v0/08-exact-numeric/`, **95/95**) drives every spec case + the exactness traps
through a live worker. No regression: V0.1 18/18 · V0.2 35/35 · V0.3 97/97 ·
V0.5 88/88 · V0.6 24/24 · V0.7 e2e 19/19. `pgrep -fl "sage -python"` clean.

**The policy (envelope gains 4 fields + `exact_value`).**
- **`exact: true|false|null`** — is the *primary* result exact? `true` for
  integer/rational/exact-symbolic; `false` for an inherently approximate
  real/complex/inexact-symbolic; `null` where exactness isn't a scalar property
  (matrix/list/relation/plot/…).
- **`primary_is_approx: bool`** — does the `≈` belong on the *primary* value (it
  already is a float, or force-numeric) vs the secondary line?
- **`approx_digits: int|null`** — the precision `approx` carries.
- **`exact_value: string`** — only in `numeric:true` evals: the original exact
  form, preserved while `plain` shows the decimal.

**API (frozen in WORKER-PROTOCOL.md).**
- **Configurable precision, two levers:** a session default via a new
  `{"op":"config","precision_digits":N}` op (default **10**, matching the spec's
  `0.5333333333`; omit the field to read it; rejects non-positive); and a
  **per-request** `precision_digits` eval field that overrides the session *for
  that request only*.
- **Force-numeric per request:** `{"code":..,"numeric":true}` makes the primary
  the numeric value WITHOUT polluting the session (it's a display
  re-presentation: eval runs normally, then `N()` is applied to the echoed
  value). Honors `precision_digits` too.

**Exit criteria — all PASS (executed evidence in README):**
- **Exact primary by default** — `plain` is the exact form (`8/15`, `sqrt(2)`,
  `pi`, `2^100`); `exact:true`, `primary_is_approx:false`.
- **Approx available for exact results** — `8/15`→`0.5333333333`,
  `sqrt(2)`→`1.414213562`, etc.
- **Precision configurable** — `config` to 20 → `8/15` shows 20 digits;
  per-request `precision_digits=6` → `0.533333` without changing the session;
  invalid rejected.
- **User can force numeric** — `numeric:true` on `y` → primary `0.333…`,
  `exact_value:"1/3"`; the **next** normal `y` is exactly `1/3`, `parent(y)` is
  `Rational Field` (namespace untouched).
- **No global float coercion** — exact-in→exact-out across integer/rational/
  symbolic/matrix; a stored `N(sqrt(2),digits=50)` keeps its **170-bit** RealField
  precision after a low-precision numeric request.
- **Spec display derivable, no round-trip** — a pure renderer over the
  `1/3+1/5` envelope produces exactly `8/15` + `≈ 0.5333333333`.

**Learned / surprised.**
- **`parent().is_exact()` is useless for the Symbolic Ring** — it's uniformly
  `False`, so `sqrt(2)`, `pi`, `sin(1)` would all read "inexact." Exactness must
  be decided **per kind**, and for symbolic by a recursive `operands()`
  tree-walk that flags a leaf as inexact iff `is_numeric()` and its
  `pyobject().parent().is_exact()` is False. That cleanly separates `sqrt(2)+pi`
  (exact) from `2.5+sqrt(2)` and `1.5*x` (inexact). → PROBLEMS.md.
- **`sin(1)` is the headline trap** — Sage keeps it **symbolic and exact** (it is
  NOT evaluated to `0.841…`). The handoff from V0.7 (a definite integral/limit is
  `kind:"symbolic"` yet exact) is the same shape: don't key "is exact?" off the
  kind being `rational`/`real`.
- **Precision must be clamped to the value's own `prec()`** — `.n(bits)` raises
  ("cannot approximate to N bits, use at most M") if you ask a 53-bit object for
  more. Clamping (vs the V0.3 `str(value)`-for-reals approach) lets a single
  code path serve "fewer digits than the value holds" (e.g. show
  `N(sqrt(2),digits=50)` at 10 digits) AND "more than it holds" (clamp), without
  ever raising or downcasting the stored object.
- **Force-numeric is free if it's display-only.** Because the worker already
  evaluates normally and only *then* re-presents the echoed value, namespace
  isolation needs no special machinery — `y` stays a `Rational`. The temptation
  to `N()` the assignment itself (which would pollute storage) is the wrong path.

**Next.** V0.9 — Sage Doctor / environment discovery. For V1.8 (the in-app
exact/numeric UI): render `plain` as primary; if `primary_is_approx` put `≈` on
it, else show `approx` as a secondary `≈ …` line; offer a "force numeric" toggle
(`numeric:true`) and a precision control wired to per-request `precision_digits`
(and/or the session `config` op). The UI needs **no** Sage round-trip to render
the default exact+approx display — one envelope carries everything.

---

## 2026-06-11 — V0.7: Friendly input compiler (command shim → Sage) — PASS

**Did.** Built a standalone SwiftPM package `v0/07-friendly-compiler/` with three
targets: **`FriendlyCompiler`** (the surviving artifact — a **pure** library,
`String → CompileResult`, no I/O, written to migrate into the app), a
**`sagecalc-compile`** CLI (`--json`), and a **swift-testing** suite. Plus a
Python **`e2e.py`** that pipes every generated Sage string through the **real
canonical worker** (`../01-worker-protocol/worker.py`). Written in **Swift, not
Python**, per the orchestrator decision: V1.4 compiles input → Sage
*synchronously on every keystroke/submit* to show "Generated Sage" without
round-tripping through the worker. **Three layers all green: `swift test` 69/69 ·
CLI smoke · e2e 19/19.** `pgrep -fl "sage -python"` clean.

**The contract.** `enum CompileResult`:
`success(generatedSage, requiredVariables)` / `bypass(rawSage)` /
`error(CompileError{message, position?, suggestion?})` / `ambiguous(candidates)`.
A command shim, **not a language**: we tokenize only enough to find the command,
the expression, and the clauses (ranges `x=0..1`, `wrt x`, `->`, `order=7`,
`for x`); expression payloads pass through **structurally**. We DO validate
balanced parens/brackets.

**Exit criteria — all PASS:**
- **Compiler emits Sage, not direct eval** — every form returns a Sage *string*;
  the library never touches a worker. All 16 spec forms map to the exact
  reference Sage (verified by CLI + unit tests).
- **Generated Sage can be shown to the user** — it's a returned `String`; `--json`
  exposes it + `requiredVariables` for tooling.
- **Raw Sage bypass works** — `factor(x^4-1)`, `factorial(5)`, `2+2`, `sin(pi/3)`,
  `A = matrix(...)`, `x.diff()`, `foobar x^2`, `""` all bypass **untouched**. Rule:
  *known command word that is the whole input OR immediately followed by
  whitespace* → friendly; else bypass.
- **Ambiguous → candidates** — `solve x*y = 1` → `[solve(x*y == 1, x),
  solve(x*y == 1, y)]`; same for `derivative x*y`, `integral x*y`. `for x`/`wrt y`
  collapses it to `.success`.
- **Parse errors are useful** — `integral x^2, x=0..` → "Range `x=0..` is
  incomplete — missing the upper bound after `..`." + a fix; unbalanced brackets
  carry a UTF-8 `position` ("Unbalanced `(` — it is never closed."); mismatched /
  orphan-close / missing-`=` / missing-`order=` / bad-order / missing-`->` /
  bare-command / non-bracketed-matrix each get a specific message + `Try: …`.
- **No implicit multiplication** — `factor 2x` → `factor(2x)` (payload verbatim;
  Sage's preparser decides, not us).

**The double-integral nesting (load-bearing, got it right).**
`double integral x*y, x=0..1, y=0..x` →
`integrate(integrate(x*y, (y, 0, x)), (x, 0, 1))`: the **inner** integral binds
the **last** range (`y`), the **outer** the **first** (`x`); the inner bound may
reference the outer var (`y=0..x`). The e2e driver confirms it **evaluates to
`1/8`**.

**Variable policy (decided + documented + proven).** The compiler **reports** free
variables in `requiredVariables` and **never injects** declarations — the
generated Sage is a single clean expression. Inference: bare identifiers not
followed by `(`, not reserved (`pi e I i oo …`, common builtins), plus the
command-bound variable; ordered command-bound-first then body order.
**Decision for V1.4: emit a `var('V')` prelude per required variable before
evaluating** (the worker's `from sage.all import *` predefines only `x`, per
PROBLEMS.md V0.5). `e2e.py` does exactly this and it works for every form.

**End-to-end (layer 3).** For each form: compile via the CLI (`--json`), declare
each required var with `var('V')`, eval the generated Sage in the real worker,
assert `ok:true` + sensible kind. **19/19**: solve→list, eigenvalues→list,
plot→plot **with 2 artifacts**, matrix→matrix, rref→matrix; definite
integrals/limits come back as Sage **symbolic**-ring elements whose `plain` is the
exact value. Bonus checks: bypass `2+2`→`4`, double integral→`1/8`, wire intact
(`1+1`→`2`) after all evals.

**Learned / surprised.**
- **A definite integral is `kind:"symbolic"`, not `rational`/`real`.**
  `integrate(x^2,(x,0,1))` returns `1/3` and `limit(sin(x)/x, x=0)` returns `1` —
  but as elements of the **symbolic ring** (`plain` is the exact value), so V0.3's
  `_classify` lands them in `symbolic`. My first e2e expectations assumed
  `rational`/`real` and "failed" 3 cases — the *compiler* was right, the *test*
  was wrong. Worth knowing for V0.8 (exact/numeric): the exact value is in
  `plain`, the float in `approx` (`0.125`), even though the kind is symbolic.
- **The bypass rule is the whole design.** Making "command word + space →
  friendly, else raw Sage untouched" the single gate means the shim is purely
  additive and progressive disclosure to raw Sage is free — `factor(...)` (a call)
  and `factorial(...)` both correctly fall through with no special-casing beyond
  the space-boundary check.
- **Reporting vars beats injecting them.** Keeping `var(...)` out of
  `generatedSage` keeps "Generated Sage" clean to show the user and lets V1.4 own
  declaration strategy (always-declare vs. skip-if-already-in-`symbols`). The
  proof (`e2e.py`) exercises the always-declare path.

**Next.** V0.8 — exact/numeric display policy. Note for it: a definite
integral/limit is symbolic with the exact value in `plain` and the float in
`approx` — don't coerce it to a float by default.

---

## 2026-06-11 — V0.6: Live symbol-table introspection — PASS

**Did.** Added a read-only `symbols` op to the **one canonical worker**
(`v0/01-worker-protocol/worker.py`, extended in place) and a Python harness
(`v0/06-symbol-table/`) that drives the spec sequence through a live worker —
**24/24 checks**. The op returns the user-created bindings as
`{name, kind, summary}`, sorted by name. No worker regression: V0.1 18/18 · V0.2
35/35 · V0.3 97/97 · V0.5 88/88. `pgrep -fl "sage -python"` clean.

**How it works.** At startup, right after `exec("from sage.all import *", NS)`,
the worker snapshots the **pristine namespace** (`_SYMBOL_BASELINE = dict(NS)` —
the star-import, dunders, plumbing). The op diffs the live `NS` against it: a
name surfaces iff it's **new** OR **rebound to a different object**
(`live is not baseline_obj`). Each surfaced value is classified (`_symbol_kind`,
which extends V0.3's `_classify`) and summarized cheaply (`_symbol_summary`).

**Exit criteria — all PASS (executed evidence in README):**
- **User symbols appear** — spec sequence → `x` (symbolic variable, "x"),
  `A` (matrix, "2×2 over Integer Ring" via `parent()` dims+base ring),
  `f(x)=sin(x)/x` (symbolic function, "x |--> sin(x)/x"), `n` (integer,
  "104729").
- **Junk filtered** — `[]` before any user code; a 23-name probe
  (`var matrix SR ZZ pi x i e I __builtins__ NS preparse latex …`) finds nothing.
- **Deleted disappears** — `del n` → n gone.
- **Reassigned updates** — `n=5` → integer "5"; `n="hello"` → text "hello"
  (kind+summary re-derived live each call).
- **Summaries bounded** — `M = matrix(ZZ,200,200,…)` → "200×200 over Integer
  Ring" (25 ch); `big_list = list(range(10**6))` → "list of 1000000 items"
  (21 ch), NOT the 7.9 MB string. Cap = 200 ch.
- **No huge computation** — the op over M + big_list returns in **~0.6–0.9 ms**
  (timed in-harness). Cheap structural summary ~1e-5 s vs `str()` ~0.05 s and
  megabytes; the op never `str()`s a matrix or a big container.
- **Bonus robustness** — a `Boom` whose `__repr__`/`__str__` raise →
  "<unprintable: …>", op survives, shape intact; `import numpy` → module
  "numpy"; `def g` → function "g()"; wire intact (`1+1`→`2`) afterward.

**Kind vocabulary.** V0.3's kinds plus four symbol-table-only kinds:
`symbolic variable` (SR `is_symbol()`), `symbolic function` (callable-expression
`parent()`), `module` (`types.ModuleType`), `function`
(`types.FunctionType/Lambda/Builtin`). A user-defined class → `unknown` (a type
isn't a math kind) but still shows. Frozen in plans/WORKER-PROTOCOL.md.

**Learned / surprised.**
- **The diff MUST be by object identity, not name** — and this was the only real
  trap. Sage's `from sage.all import *` exports `n` (= `numerical_approx`), `N`
  (also `numerical_approx`), and `i` (the Gaussian unit) as builtins. A name-only
  baseline diff therefore **hid the spec's own `n = 104729`** (it "already
  existed"). First harness run was 20/24 for exactly this reason. Fix: snapshot
  the pristine **objects** and surface a baseline name when it's rebound to a
  *different* object. → PROBLEMS.md.
- **Retain the baseline objects, not their `id()`s.** If the baseline only stored
  `id()` ints, a freed baseline object's id could be recycled by a later user
  object and make `==` on ids lie. Holding the objects + using `is` is exact.
- **`f(x) = sin(x)/x` is "just" an assignment.** Sage preparses it to an
  assignment of a *callable symbolic expression* (parent = a `Callable…` ring,
  str = `x |--> sin(x)/x`), so it lands as a normal binding and needs no special
  eval path to surface — only a kind detector.
- **Bounded ≠ slow.** The win is summarizing **structurally** (matrix dims, list
  `len`) instead of stringifying. That's what makes inspection both bounded AND
  ~microseconds — the same move solves "don't emit 7.9 MB" and "don't take 50 ms"
  at once.

**Next.** V0.7 — friendly input compiler. V1.6 (Symbols sidebar) should call the
`symbols` op (cheap enough to refresh after every eval), render
`{name, kind, summary}`, and rely on it never leaking Sage internals or
stringifying huge values.

---

## 2026-06-11 — V0.5: Plot & artifact pipeline — PASS (render PNG; SVG corrupts on macOS NSImage)

**Did.** Extended the **one canonical worker**
(`v0/01-worker-protocol/worker.py`, in place) so a Sage plot becomes image
artifacts in the envelope's `artifacts` array, built a Python harness that drives
the spec's plot cases through a live worker (**88/88 checks**), and built a
standalone SwiftUI viewer (`v0/05-plot-artifacts/`, executable
`CasettePlotProof`, own `Package.swift`, **not** wired to the main app) that
loads those artifacts and renders them in a scrolling tape. No worker regression:
V0.1 18/18 · V0.2 35/35 · V0.3 97/97.

**Worker side.** When an eval produces a `Graphics`/`GraphicsArray`, it's saved
to **SVG + PNG** (SVG first) under a session-scoped dir
`/tmp/sagecalc/session-<pid>-<rand>/`, named with a monotonic per-worker counter
(`plot-00001.svg`, …) so plots never collide across one eval or rapid successive
evals. Two capture channels: the **echoed value** (last expr is a plot) and a
wrapped **`.show()`** (captures instead of opening a GUI window — this is how
several plots come out of one eval), de-duped by identity. **Lifetime:** the dir
is removed on clean `shutdown`; a hard kill leaves it, but it's pid+rand-
namespaced under /tmp so it never collides. **Failures are structured:** a bad
plot *call* → normal error envelope; a *save* failure → a per-format
`{"type":"image","path":null,"error":...}` entry with the eval still `ok:true`
and the wire intact (proven: `1+1`→`2` right after forced failures). Spec
documented + the `artifacts` shape frozen in plans/WORKER-PROTOCOL.md.

**Viewer side.** No third-party deps — SVG and PNG both load through `NSImage`.
Scrolling `List` of plot cards (source caption, per-row SVG/PNG segmented
toggle, byte size, the rendered image), a global default-format toggle, a
click-to-expand **zoom sheet**, context-menu Reveal-in-Finder / Copy-Path, and a
designed empty state. Auto-discovers the newest `/tmp/sagecalc/session-*` dir.

**The finding (verified ON SCREEN, computer-use):**
- **All three spec plots render correctly in PNG** — `plot(sin(x))` is a clean
  sine wave −π..π peaking at ±1; `implicit_plot(x²+y²==1)` is a clean unit
  circle (axes −2..2); `parametric_plot((cos t,sin t))` is a clean unit circle
  (axes −1..1). Zoomed PNG stays crisp.
- **Multiple plots don't collide** — the one-eval multi-plot produced two
  distinct files (`plot-00004` sin, `plot-00005` cos), both render; rapid
  sin(n·x) evals each got their own file.
- **SVG is the trap.** `NSImage` *loads* Sage/matplotlib SVG (via the system
  `_NSSVGImageRep`, non-nil, sane size) but **rasterizes the axis-label glyphs
  as a giant opaque black blob** over the (correct) curve — unusable, though not
  a crash. The per-row toggle shows it side-by-side with the perfect PNG.
  **Verdict: render PNG; keep SVG only for a future real SVG engine.** → PROBLEMS.md.
- **Failure case is readable, not blank/crash** — the viewer's
  `ContentUnavailableView` handles an unrenderable file; the app survived sheet
  open/close, toggles, scrolling, zoom, then quit clean. `pgrep` clean (no
  worker, no viewer).

**Learned / surprised.**
- **A non-nil `NSImage` from an SVG is NOT proof it renders right** — it silently
  produces a wrong raster (black-blob glyphs). Only the on-screen check caught
  it; every file-level assertion (exists, nonempty, parses as SVG) passed. The
  classic SWIFTUI-RULES §9 lesson, now in the artifact pipeline.
- **`from sage.all import *` doesn't predefine `x`** the way the REPL does — the
  spec's `plot(sin(x), …)` raised `NameError` in the worker until the harness
  declared `x, y, t = var('x y t')`. (Already noted in the protocol doc.)
- **Sage 9.5 saves SVG/PNG/PDF all cleanly** for 2D plots — the save side was
  never the problem; the macOS *render* side was.
- **`.show()` is the multi-plot lever.** The REPL echo only returns the last
  expression, so capturing every `.show()` is what makes several plots per eval
  work — and it doubles as the headless "don't open a GUI window" guard.

**Next.** V0.6 — live symbol-table introspection. V1.7 (in-app plots) should
render **PNG** from the `artifacts` array, keep the SVG for later, and reuse the
session-dir lifetime policy (clean the tree on launch).

---

## 2026-06-11 — V0.4: LaTeX rendering in SwiftUI — PASS (engine: SwiftMath)

**TEXTUAL VERDICT — NOT VIABLE; did NOT silently substitute.** The product
decision named "Textual." Research found two real packages by that name and
neither fits. The IRC client (`Codeux-Software/Textual`) is irrelevant. The
SwiftUI rich-text engine (`gonzalezreal/textual`, the one almost certainly meant)
is **disqualified**: platform floor is **macOS 15** (we need 14), and its math is
markdown-`$…$`-only through an immature 26-star engine (`gonzalezreal/swiftui-math`,
v0.1.0) with no standalone LaTeX-string API and no `array` support. Per the spec,
we kept the `MathRenderer` abstraction and documented the gap loudly rather than
swap it in. Full evidence in plans/MATH-RENDERING.md.

**Did.** Built a standalone SwiftPM proof app under `v0/04-latex-rendering/`
(executable `CasetteLatexProof`, own `Package.swift`, **not** wired to the main
app). Renders a 59-row scrolling tape: all 5 spec snippets, **real worker LaTeX
captured live from the V0.1 worker** (Sage 9.5: `\frac{8}{15}`, Sage's
`\left(\begin{array}{rr}…\right)` matrices, `expand((x+1)^8)`, solve list, complex
`4i+3`, 50-digit √2, …), inline + block, a deliberately invalid row, and 40 bulk
rows. In-app System/Light/Dark toggle; per-row Copy LaTeX (hover button +
right-click menu).

**The engine journey (the surprising part).**
1. **Chose LaTeXSwiftUI (MathJax-in-JavaScriptCore, offline)** after research —
   it was the only candidate that handled Sage's `array` and met the macOS-14
   floor.
2. **On screen, it failed.** Every *braced* sub/superscript — `\sum_{n=0}^{\infty}`,
   `\int_{0}^{1}`, and crucially `x^{8}` (which Sage emits) — rendered as raw text;
   MathJax errored "Extra open brace or missing close brace". Single-char scripts
   (`\int_0^1`) and Sage's `array` matrices worked, but braced scripts are
   unavoidable in real worker output. Proven it's the MathJaxSwift/JSC bridge, not
   packages or the parser: `loadPackages:.all`, `\[…\]`, `$$…$$`, and
   `parsingMode(.all)` (bypasses the parser) all failed identically. → PROBLEMS.md.
3. **Swapped to SwiftMath** (native Core Text, no JS bridge) behind the
   `MathRenderer` abstraction — **one line + a renderer file, zero app-code
   change.** SwiftMath renders every spec case and every worker case beautifully.
   Its one gap (no `array` env) is handled by a Sage-`array`→`pmatrix` rewrite in
   the normalizer. This is exactly the "if the named lib falls short, prove it
   behind the abstraction with the best fallback" path the spec called for.

**Exit criteria — all PASS, each verified ON SCREEN (computer-use screenshots +
zoom), app confirmed alive then quit clean:**
- **Inline math** — renders within a sentence (baseline alignment is the lone
  polish item; block is the 99% case and is perfect).
- **Block math** — all 5 spec snippets crisp: `∫₀¹x²dx`, bmatrix `[1 2/3 4]`,
  `∂²f/∂x∂y`, `∑_{n=0}^{∞} xⁿ/n!`, set-builder `{x∈ℝ : x²<2}`.
- **Matrices** — bmatrix **and** Sage's `array` form (rewritten to `pmatrix`,
  renders `(1 2/3 4)` with parens).
- **Dark mode** — math re-tints white via semantic `NSColor.labelColor`, fully
  legible; verified by flipping the in-app toggle.
- **Scrolling** — 59 lazy rows scroll smoothly, no hitch.
- **Failed LaTeX → graceful fallback** — the malformed row shows raw source in red
  plain text, no crash.
- **Copy** — Copy LaTeX (hover button + context menu) verified via **both**
  `pbpaste` and computer-use `read_clipboard` (got the exact worker LaTeX).

**Learned / surprised.**
- **"A passing build is not a passing app" (SWIFTUI-RULES §9) earned its keep
  twice.** LaTeXSwiftUI compiled, resolved, and rendered *some* rows — only the
  on-screen check exposed that braced scripts (the common case) silently fell
  back to raw text. Live-gating found the engine defect before V1.5 built result
  cards on it.
- **swiftui-pro review caught two P1s pre-verification:** `.renderingStyle(.wait)`
  would block the main thread per lazy row (scroll hitch) — switched to
  `.progress`; and a fragile hidden-Text/overlay inline hack — replaced with a
  direct baseline HStack and extracted the math hero into its own subview so
  header-state redraws don't churn the math graph.
- **Bare SwiftPM executables don't get a computer-use grant or reliable
  `Bundle.module` resources** — wrapped the proof in a minimal `.app` (`bundle.sh`).
- **MathJaxSwift's `tex2svg` deadlocks against a main-thread semaphore** (it hops
  back to the main queue); a probe must use an async Task + `RunLoop.main.run()`.

**Next.** V0.5 — plot/artifact pipeline (worker generates image artifacts; UI
renders them). V1.5 result rendering should adopt SwiftMath behind this
`MathRenderer` abstraction and keep the Sage-`array`→matrix rewrite. See
plans/MATH-RENDERING.md for the V1.5 recommendation.

---

## 2026-06-11 — V0.3: Result envelope & type classification — PASS

**Did.** Turned the worker's rough V0.1 `kind` into a real result model: a proper
classifier + envelope builder in the **one canonical worker**
(`v0/01-worker-protocol/worker.py`, extended in place). Test harness under
`v0/03-result-envelope/` — **97/97 checks**, no stray Sage processes.

- Replaced `_classify`/`_safe_plain`/`_safe_latex` with `_classify` (a frozen
  14-kind set) + `_build_envelope`, which emits the V0.3 envelope:
  `kind, plain, latex, repr, approx, actions, artifacts, truncated` (+ a
  `truncation` policy object when capped). Error/interrupted envelopes gained the
  same shape (`repr`/`approx`/`actions`) so the contract is uniform.
- Documented and **froze** the protocol + envelope in
  `plans/WORKER-PROTOCOL.md` (fields, kinds, approx/actions policy, truncation,
  framing) and added it to PLAN.md's Documents table. V0.4+/V1 build against it.
- `harness.py` drives every spec case (`ZZ(104729)`, `1/3+1/5`, `sqrt(2)`,
  `N(sqrt(2),digits=50)`, `sin(pi/3)`, `x^2+5*x+6`, the `== 0` relation, `solve`,
  `matrix`, `rref`) plus `complex` (`3+4*I`), `plot`, `text`, `error` (`1/0`),
  an `unknown` (`Permutation([2,1,3])`), and huge outputs — asserting kind
  stability and envelope sanity for each.

**Exit criteria — all PASS (evidence in README):** every common result has a
**stable kind** (13 cases matched exactly); every value-bearing result has
non-empty `plain`; math results carry **LaTeX** (rational `\frac{8}{15}`, matrix
`array`, relation `… = 0`, even the unknown Permutation); **unknown degrades to
repr, not failure** (`Permutation` → `ok:true, kind:unknown, repr:"[2, 1, 3]"`);
**large outputs capped** with a flag + policy (`list(range(10^6))` → `truncated`,
8192 of 7,888,890 chars; `factorial(10^5)` → 8192 of 456,574); **actions drive the
UI** (matrix → `det/rank/rref/eigenvalues/transpose/inverse`, etc.).

**Policy decisions (the load-bearing ones).**
- **`approx` is per-kind, not blind.** Only rational/real/complex/symbolic-constant
  get a numeric approximation; integer/matrix/list/relation/plot/boolean → `null`
  (an integer is already exact; a matrix approx isn't a scalar). A symbolic expr
  with **free variables** (`x^2+5*x+6`) → `null`; a constant one (`sin(pi/3)`) →
  `0.866…`. High-precision reals keep their **own** precision via `str(value)` —
  `.n()` silently downcasts `N(sqrt(2),digits=50)` to 53-bit.
- **`actions` is a static per-kind name table.** The proof that result metadata can
  drive UI; V1.10 maps a chosen action to a follow-up eval.
- **Truncation is explicit.** `plain`/`repr` capped at 8192, `latex` at 16384, with
  a `truncation{plain_len,repr_len,plain_cap,repr_cap}` object so the UI can say
  "N of M chars". Never an unbounded string on the wire.

**Learned / surprised.**
- **`3 + 4*I` is not a `sage.rings.complex` object** — it's a
  `NumberFieldElement_gaussian` (an element of `QQ[i]`, module
  `sage.rings.number_field.…`). The rough V0.1 classifier's `mod` check would have
  missed it; added an explicit Gaussian/cyclotomic number-field branch → `complex`.
- **`solve(...)` returns a `Sequence_generic`, not a plain list** — but it
  subclasses `list`, so `isinstance(v,(list,tuple))` catches it. No special case
  needed; it lands as `list` with the solve roots inside.
- **`bool` is an `int` subclass** — must test `boolean` *before* `integer` or
  `True` classifies as integer.
- **`.n(digits=15)` can raise on an already-53-bit `ComplexNumber`** ("cannot
  approximate to 54 bits, use at most 53") — so the approx path uses the value's
  *native* precision (`.n()` no-arg, or `str` for concrete reals/complexes), never
  a fixed `digits=`.
- **Unknowns still carry LaTeX.** A `Permutation` is `kind:unknown` yet
  `latex(value)` renders `[2, 1, 3]` — so `latex` is best-effort regardless of kind.

**Next.** V0.4 — LaTeX rendering in SwiftUI/Textual. Render the envelope's `latex`
field beautifully; keep a `MathRenderer` abstraction so we're not trapped if one
path falls short.

---

## 2026-06-11 — V0.2: Worker lifecycle, interrupts & restart — PASS

**Did.** Built the parent-side `SessionController` and proved the app can stay in
command when Sage misbehaves. Under `v0/02-lifecycle/`. **35/35 checks**, stable
across repeated runs; no stray Sage processes left.

- `controller.py` (`SessionController`, prototype of V1.3's controller) — owns one
  worker + a **reader thread** draining stdout into a queue (parent never blocks),
  the eight-state machine (idle/running/completed/error/interrupted/timed_out/
  crashed/restarting), and the command surface `evaluate / request_cancel / kill /
  restart / poll_health`. `evaluate` enforces a timeout and escalates **SIGINT →
  hard process-group kill** if the worker won't yield.
- Extended the **one canonical worker** (`v0/01-worker-protocol/worker.py`, not a
  copy): it now reports its **real pid** in the ready banner (so the parent can
  SIGINT the actual worker, not the `sage` bash wrapper) and returns a distinct
  `kind:"interrupted"` envelope on `KeyboardInterrupt`. V0.1 harness still 18/18 —
  changes are backward-compatible.
- `harness.py` — runs every exit criterion against the spec's hostile cases for
  real. `README.md` — full evidence + the honest interrupt story.

**Exit criteria — all PASS (evidence in README):** parent stays responsive during
a 5s eval (state reads <50ms, max measured 0.0ms; RUNNING observed live);
`while True: pass` interrupted in 0.02s; `sleep(30)` timed out in 2.03s;
`factorial(10^8)` (runs >60s) aborted mid-C in ~2s by SIGINT and the worker
**survived**; a SIGINT-ignoring runaway hard-killed (rc -9) and recovered by
restart; restart yields a fresh namespace (`secret` → `NameError`); crash detected
both mid-eval and idle (rc -9); all eight states observed.

**Learned / surprised.**
- **cysignals is what makes Sage interruptible — and it owns SIGINT.** The worker's
  SIGINT handler is `cysignals.python_check_interrupt`, NOT the one I installed:
  `from sage.all import *` makes cysignals install its handler on top. cysignals
  wraps Sage C/Cython in `sig_on()/sig_off()` and longjmps out at an interrupt
  check, so **SIGINT promptly aborts mid-flight C computation** (`factorial(10^8)`
  interrupted at +3.00s vs >60s to run). My own handler is a harmless fallback.
- **The contradiction that taught it.** A standalone probe that installed a plain
  Python SIGINT handler *after* the Sage import (clobbering cysignals) deferred the
  interrupt **23s** — until the GMP call returned — because plain-Python handlers
  only run between bytecodes and a C call doesn't yield. Same code, different
  handler, 23s vs prompt. Don't overwrite cysignals' handler.
- **SIGINT is still not guaranteed** (unwrapped C, `SIG_IGN`, tight pure-C loop) —
  so the controller always escalates SIGINT → hard process-group kill. Proved both
  halves.
- **Restart had a sneaky race:** a stale reader thread hitting EOF on the dead
  worker's pipe tripped a *shared* EOF flag and made the fresh worker look
  crash-on-boot. Fix: each worker generation owns its own queue + EOF event,
  captured by that generation's reader thread.
- **Two threads draining one response queue is a bug.** First cut had `interrupt()`
  and `evaluate()` both reading the queue → the interrupt response got consumed by
  the wrong reader and `interrupt()` looked like it timed out. Fix: `evaluate` is
  the sole consumer; cancel/timeout only *signal*.
- `integrate(sin(x^x), x)` doesn't hang — Sage 9.5 returns it unevaluated (no
  closed form) in ~1.5s.

**Next.** V0.3 — result envelope / classification refinement. (Lifecycle + state
machine are now a clean base for V1.3's `SessionController`.)

---

## 2026-06-11 — V0.1: Sage worker protocol (the first real gate) — PASS

**Did.** Built and proved the Sage worker bridge under
`v0/01-worker-protocol/`. The first hard V0 gate is green: **18/18 checks**.

- `worker.py` (real app code, survives into V1) — `sage -python worker.py`.
  Reads JSONL requests on stdin, writes JSONL responses on stdout. One
  persistent Sage namespace (`exec("from sage.all import *", NS)`) reused for
  every eval. Runs user code through `sage.repl.preparse.preparse`, then uses
  `ast` to exec leading statements and `eval` the trailing expression for a
  REPL-style value echo. Envelope: `id, ok, kind, plain, latex, stdout,
  stderr, artifacts, value` + `error{type,message,traceback}` on failure.
  `kind` is a rough classifier (V0.3 refines it).
- `harness.py` (test scaffold, plain Python 3) — boots ONE worker, drives all
  spec test cases sequentially (proving namespace persistence), then kills it
  to prove death detection. Exit 0 iff all criteria pass. `--json` dumps each
  envelope.
- `README.md` — run instructions + the full exit-criteria evidence table.

**Exit criteria — all PASS (evidence in README):** Sage boots from parent;
multiple evals in one persistent namespace; assignment state survives
(`x=var("x")`→`factor(x^4-1)`, `A=matrix(...)`→`A.eigenvalues()`, `A.det()` even
after an exception); `1/0` → structured `ZeroDivisionError` with traceback;
`print("hello")` captured into `stdout` (`value:false`); raw `os.write(1,…)`
(the Cython hazard) also captured, framing intact; parent detects worker death.

**Learned / surprised.**
- **`sage -python` is a bash wrapper** that fork-execs the real Python worker
  as a *child*. SIGKILL to the Popen PID kills only the wrapper and orphans the
  worker, which keeps answering on the inherited stdout pipe. Fix:
  `start_new_session=True` + `os.killpg`. This bit me directly and is a
  must-carry into V0.2 lifecycle and V1.3 `SageKernel`. → PROBLEMS.md.
- **`contextlib.redirect_stdout` is not enough.** It only swaps the Python
  `sys.stdout` object; C/Cython writes to fd 1 sail past it. Had to also
  `os.dup2` fds 1/2 into pipes during eval and drain them. Protocol output goes
  to a *private dup'd fd* established before Sage even imports. → PROBLEMS.md.
- A bare `print(...)` returns `None`; my first cut echoed `plain:"None"`.
  Suppressing `None` results (like the REPL) fixed it.
- Sage 9.5 orders `factor(x^4-1)` as `(x^2 + 1)*(x + 1)*(x - 1)` — fine,
  just don't string-compare factor output against the spec's illustrative order.

**Next.** V0.2 — worker lifecycle: timeouts, interrupt/cancel, hard kill,
restart, crash detection, and the idle/running/…/crashed state machine. The
process-group kill pattern is already proven and ready to reuse.

---

## 2026-06-11 — Bootstrap: hello-world app + build system

**Did.** Stood up the project skeleton and the `swift build` + `build.sh` +
`Makefile` build system, modeled on `Makefile.example` (the Moves pipeline).
No Xcode IDE, no xcodebuild.

- `Package.swift` — SwiftPM, `swift-tools-version:6.0`, macOS 14 floor,
  executable target `Casette` + `CasetteTests` (swift-testing).
- `Sources/Casette/CasetteApp.swift` — `@main` `App` with a `WindowGroup`,
  `.windowResizability(.contentMinSize)`.
- `Sources/Casette/ContentView.swift` — hello-world: `f(x)` glyph + title +
  subtitle. Semantic fonts, centralized `Metrics` enum, `accessibilityHidden`
  on the decorative glyph (per SWIFTUI-RULES §5.1, §2.4).
- `Resources/Info.plist` — bundle plist with `__SHORT_VERSION__` /
  `__BUILD_VERSION__` placeholders substituted by `build.sh`.
- `Casette/Casette.entitlements` — App Sandbox **off** (will spawn a Sage
  worker process in V1.3); hardened-runtime exceptions for exec'ing an
  interpreter. Sandboxed/bundled Sage is a V2 concern.
- `build.sh` — `swift build` → assemble `build/Casette.app` (MacOS binary,
  Info.plist w/ version substitution, PkgInfo, optional icon) → codesign with
  `SIGN_IDENTITY` and **ad-hoc fallback** so `make run` works with no certs.
- `scripts/make-icon.swift` — pure-CoreGraphics icon: draws a cassette tape
  (the "session tape") into `build/AppIcon.iconset` at all 10 sizes;
  `iconutil` packs it. No asset files, runs under bare `swift`.
- `Makefile` — adapted from `Makefile.example`: `build/check/test/run/icon/
  clean/install/register` + the full `dist` sign→notarize→staple→zip pipeline.
  Defaults are ad-hoc-friendly (`DEV_IDENTITY := -`, signing identity / team id
  left blank until someone fills them for `make dist`).
- `.gitignore` — `.build/ build/ dist/`.

**Gate passed (per SWIFTUI-RULES §9.1, "launch + alive check").**
`make check` ✓ · `make test` ✓ (1 smoke test) · `make build` ✓ (ad-hoc signed,
`codesign --verify` clean) · launched `Casette.app`, alive after 4s, renders
correctly (screenshotted), quit clean.

**Learned / surprised.**
- `${VAR:-default}` in `build.sh` covers the empty-string case, not just unset
  — so `VERSION=""` from the Makefile (no tag, no VERSION file) still resolves
  to `0.0.0`. Confirmed in the stamped Info.plist.
- `swiftui-pro` flagged a `.windowToolbarStyle(.unified)` I'd added with no
  toolbar present — removed it (keep it simple).

**Next.** V0.1 — the Sage worker protocol. The first real gate: can we boot
Sage, send eval requests, preserve state, and get structured JSONL responses
reliably? Nothing else matters until that works.
