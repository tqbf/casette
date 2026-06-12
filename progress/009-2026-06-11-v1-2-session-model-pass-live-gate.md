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
