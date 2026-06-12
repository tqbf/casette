# Progress Log

## 2026-06-12 — V1.8: Exact/numeric controls — PASS (live gate PASSED across two rounds)

**Live gate (opus verifier, computer-use) — PASS, all 14 checks.** Round 1
verified 12/14 on screen: default exact (`8/15` + exactly-10-digit ≈),
Approximate Numerically → fresh selected `.n()` row, precision menu 20 →
zoom-counted 20 digits → back to 10, restart keeps precision AND
`expand((x+1)^2)` immediately after restart works (the chained re-init race
fix), numeric toggle (pressed state + menu checkmark, decimal hero +
`= 1/3 exactly`), namespace purity on screen (`parent(y)` → Rational Field),
toggle-off exact again, Copy Approximation / Copy Exact Value via pbpaste
(contextually swapped — nice), dark mode, min-width layout, no min-height
balloon, clean exit. Round 1 reported a "blocking" tab-bar defect (clicks
opening System Settings → Time Machine) — round 2 PROVED it a verifier
environment artifact (their System Settings window from the dark-mode toggle
overlapped Casette's tab strip and swallowed the clicks; with it closed, all
four tabs switch perfectly). Round 2 completed the two blocked checks:
Inspector shows Exact Value `1/3` on the numeric row, and History Rerun
reproduces the row's recorded numeric flag with the toggle OFF. **Checklist
correction:** the checklist expected "Exact: No" on a force-numeric rational;
the app shows "Exact: Yes" — the app is right (it faithfully displays the
frozen V0.8 envelope's `exact` flag for the underlying rational; the
checklist, not the app, was wrong). **Verifier-environment lesson recorded:**
on-screen verifiers must close System Settings after appearance toggles —
an overlapping window reads as phantom app defects.

**Exactness is now a product feature, not a Sage weirdness.** The default
display was already the V0.8 contract (exact primary, `≈ approx` secondary —
verified intact); V1.8 adds the CONTROLS: a sticky **"≈ Numeric" toggle** in
the input pane (mirrored as a checked **Numeric Results** item on the Sage
menu), a session-scoped **precision menu** ("10 digits" → 5/10/15/20/30/50)
wired to the worker `config` op and **re-applied after restart** like the
boot prelude, an **Approximate Numerically** one-click affordance on the
card's context menu (a real `(expr).n()` tape row), copyable ≈/exact lines,
and the preserved exact form (`= 1/3 exactly`) on every force-numeric card +
an Exact Value field in the Inspector.

### The controls and their scope semantics (the design decisions)

- **Numeric mode is a sticky, always-visible toggle, scoped to TYPED
  submissions only.** macos-design call: a per-submit modifier key is
  invisible state; a pressed accent `Toggle(.button)` next to the input IS
  the scope indicator (and the Sage-menu checkmark always agrees — same
  model flag). While on, each draft submission sends the V0.8 per-request
  `numeric:true` — display-only, worker-guaranteed namespace purity — and
  the row records it (`SessionRow.numeric`, the ONE additive schema field,
  documented in SESSION-FORMAT.md like `truncation`/`error` were). Sidebar
  flows (inspect/forget/actions) are NEVER numeric in either toggle state;
  **rerun reproduces the original row's recorded flag**, not the toggle's
  current state. The exit criterion "numeric mode does not pollute global
  behavior accidentally" is structural: per-request wire flag + visible
  sticky state + per-row honesty (`≈ 0.3333333333` hero with `= 1/3
  exactly` under it — the force-numeric card can't be mistaken for a float).
- **Precision is a SESSION control, deliberately NOT a Settings window.**
  It's worker session state (the `config` op's `precision_digits`, default
  10, recorded in the session header's `precisionDigits` — in the schema
  since V0.10, now actually driven), so it lives next to the input where
  its effect appears, not in app preferences. `ShellModel.setPrecision`
  updates the header and queues the `config` op on the serial kernel queue
  (a precision change never reorders ahead of submitted work); boot/restart
  re-apply it whenever it differs from the worker default 10 (a fresh
  worker silently resets — V0.8 session state). V1.9 persists + restores it
  with the session; a restored non-standard value is injected into the
  menu's choices so the control never shows blank.
- **"Approximation is one click away", honestly:** for every constant exact
  result the approximation is already ZERO clicks (the ≈ secondary line,
  now right-click-copyable on the line and the row). The new context-menu
  **Approximate Numerically** (shown exactly when the envelope offers the
  `approx` action and the row has a reusable expression —
  `SessionRow.approximateCommand`) evaluates the same stateless
  `(expr).n()` command the Actions tab builds, as a fresh SELECTED row.
  Kinds where approximation makes no sense (matrix, list, error) honestly
  offer nothing.
- **Force-numeric cards render `plain`, never `latex`:** the worker's
  numeric envelope keeps the EXACT form's LaTeX (it computes latex before
  re-presenting the echoed value), so the old hero path would have typeset
  `≈ 1/3` over a decimal `plain`. `ResultHeroView` now branches on
  `exactValue != nil` → mono decimal hero `≈ 0.3333333333` + the
  `= 1/3 exactly` secondary (value in the mono Sage voice, "exactly" as a
  chrome word at the meta scale — no new type tokens).

### Kernel API changes (wire shapes per WORKER-PROTOCOL.md; worker.py untouched)

- `SessionController.evaluate(_:numeric:precisionDigits:)` — additive
  defaulted parameters; a plain eval's wire shape is byte-identical to
  V1.3's (`numeric`/`precision_digits` keys appear only when asked).
- `SessionController.configure(precisionDigits:) async -> Bool` — the
  session `config` op (send + poll with the metadata timeout, single-
  consumer discipline preserved); reports the worker's accept/reject.
- **`restartKernel` re-architected (a latent race the gate caught):** the
  `restart()` call stays un-chained (it must preempt a stuck eval) but the
  re-init (boot prelude + precision re-apply + symbols refresh) now rides
  the serial kernel queue awaiting it — a submission typed right after ⌘⇧R
  deterministically evaluates AFTER the fresh worker is initialized. The
  pre-existing flake it fixed ("expand((x+1)^2) → NameError right after
  restart") and the rules are in PROBLEMS.md ("Restart re-init must
  CHAIN…").

### Gate (all PASS; live gate pending)

- `make check` ✓ · **`make test` 249/249** (39 suites; was 236 — +13:
  `ExactNumericTests` ×10 over the fake transport (eval wire shape sends
  the V0.8 fields only when asked; `config` op shape + accept/reject +
  no-kernel; numeric-mode scope: flag on the wire AND the row, off after
  toggle, never on sidebar flows in either toggle state, rerun reproduces
  the recorded flag; setPrecision header+config in queue order, no-op/
  invalid guarded; boot-at-default sends NO config, restart re-applies a
  changed precision across worker generations; approximateNumerically →
  fresh selected row + draft untouched + no-approx-action rows offer
  nothing; `SessionRow.numeric` Codable round-trip incl. omitted-when-nil
  + legacy decode), `ExactNumericIntegrationTests` ×3 against REAL Sage
  9.5 (the V0.8 harness cases through the app's seams: `y = 1/3` →
  numeric eval → decimal primary + `exact_value` "1/3" + next plain `y`
  exact again + `parent(y)` = Rational Field + per-request 5-digit
  override leaves the session at 10; config 20 →
  `0.53333333333333333333` and sqrt(2) to 20 digits → back to 10, 0
  rejected; the full model journey: toggle scope, precision through the
  UI seam, restart re-applies 20 — proven via a sentinel symbol so the
  restart pipeline is OBSERVABLY complete — and the card's one-click
  `(1/3 + 1/5).n()` row)).
- **Full V0 regression:** V0.1 **18/18** · V0.2 **35/35** · V0.3 **97/97**
  · V0.5 **88/88** · V0.6 **24/24** · V0.8 **95/95** · V0.7 swift **69/69**
  + e2e **19/19** · V0.9 swift **32/32** · V0.10 swift **21/21** (run
  `--no-parallel` per the documented setenv race).
  `pgrep -fl "sage -python|worker.py"` clean.
- **Skills:** swiftui-pro — bindings are real (`@Bindable` +
  `$model.numericMode` / the computed `$model.precisionDigits`, no
  `Binding(get:set:)` in body), controls keep their system typography
  (§5.1), the glyph-labeled toggle carries an `accessibilityLabel`
  ("Numeric results"), context menus on actionable rows, no new
  non-scrolling wrapping text (the min-height-bomb check), no NSView
  changes (AttributeGraph invariant untouched). macos-design — session
  state controlled AT the session surface (input pane, beside the kernel
  status), not a Settings window; sticky pressed-button state as the scope
  indicator; menu mirror for discoverability; NO keyboard shortcut
  advertised for the new controls (V1.12 certifies keys; PROBLEMS.md
  "never advertise a key unverified"). typography-designer — no new
  tokens; the one new line reuses `resultSecondary` (mono value) + `meta`
  ("exactly" chrome word), per the frozen two-axis system.
- `make build` ✓ (bundled worker.py `cmp` byte-identical) · launched
  `build/Casette.app` via `open`: alive 14s with exactly ONE worker chain,
  AppleScript quit → `pgrep -fl "Casette|sage -python|worker.py"` clean.

### Known gaps (deliberate)

- The precision menu offers fixed choices (5/10/15/20/30/50 + the current
  value when restored non-standard); a free-form digits field is later
  polish if ever needed.
- "Approximate Numerically" uses `.n()` at Sage's default 53-bit precision
  (the frozen V1.6 Actions-tab command), NOT the session digits — the
  session digits drive the envelope's `≈` line. Visible and editable
  before evaluating, like every action command.
- Numeric mode doesn't re-render EXISTING rows (each row keeps the display
  it was evaluated with — deliberately: rows are honest records, and the
  recorded `numeric` flag is what V1.9's replay reproduces).
- A non-constant symbolic row (e.g. `x^2 + 5*x + 6`) still offers
  Approximate Numerically (the worker lists `approx` for all symbolic);
  evaluating it yields a readable TypeError row — honest, visible, cheap.
- No keyboard shortcut for the toggle yet (V1.12 keyboard pass).

### On-screen verifier checklist (V1.8 — pending)

In `build/Casette.app` (real Sage), verify on screen:

1. **Default exact:** evaluate `1/3 + 1/5` → typeset `8/15` hero with
   `≈ 0.5333333333` (exactly 10 digits) beneath it. `sqrt(2)` → radical
   hero + `≈ 1.414213562` line.
2. **One-click approx:** right-click the `8/15` row → menu shows Copy
   Approximation (→ `pbpaste` = `0.5333333333`) and **Approximate
   Numerically**; click the latter → a FRESH row `(1/3 + 1/5).n()`
   evaluates at the tape end showing `≈ 0.533333333333333`, SELECTED
   (Inspector follows it). The original `8/15` row is untouched.
3. **No approx where it makes no sense:** evaluate `matrix([[1,2],[3,4]])`
   → its context menu offers neither Copy Approximation nor Approximate
   Numerically.
4. **Precision to 20:** click the input-pane "10 digits" menu → choose
   "20 digits" → evaluate `1/3 + 1/5` → `≈ 0.53333333333333333333`
   (20 digits). `sqrt(2)` → `≈ 1.4142135623730950488`.
5. **Back to 10:** choose "10 digits" → `1/3 + 1/5` → `≈ 0.5333333333`.
6. **Numeric toggle ON:** click "≈ Numeric" (button reads pressed/accent;
   Sage menu → Numeric Results shows a checkmark). Evaluate `1/3` → hero
   `≈ 0.3333333333` with the secondary line `= 1/3 exactly`; the
   Inspector for that row shows Kind `rational`, Exact `Yes`, and an
   **Exact Value** field `1/3`. Row context menu → Copy Exact Value →
   `pbpaste` = `1/3`.
7. **Namespace purity on screen:** with the toggle still ON, evaluate
   `y = 1/3` (statement row), then `parent(y)` → `Rational Field`;
   Symbols tab lists `y · rational · 1/3` — the stored value stayed exact
   through a numeric-mode assignment.
8. **Toggle OFF → exact again:** click "≈ Numeric" off (button
   un-presses, menu checkmark clears) → evaluate `1/3` → plain `1/3` hero
   with `≈ 0.3333333333` secondary — the very NEXT eval is exact; nothing
   global changed.
9. **Rerun honesty:** History tab → right-click the NUMERIC `1/3` row →
   Rerun → the fresh row is numeric again (`≈ 0.3333333333` +
   `= 1/3 exactly`) even though the toggle is now off.
10. **Restart re-applies precision:** set 20 digits, evaluate `1/3 + 1/5`
    (20-digit ≈), then Sage → Restart Sage (menu item; ⌘⇧R doesn't fire
    through the MCP key tool — V1.7 harness note). After "Sage ready" +
    Symbols shows `t x y z`, evaluate `1/3 + 1/5` →
    `≈ 0.53333333333333333333` STILL 20 digits (the menu still reads
    "20 digits").
11. **Immediately-after-restart ordering (the race fix):** restart again
    and, as soon as the input accepts typing, submit `expand((x+1)^2)` →
    `x^2 + 2*x + 1` with NO NameError (the re-init is queue-ordered ahead
    of it).
12. **Dark mode:** the toggle's pressed state, the precision menu, the
    `= 1/3 exactly` line, and the Inspector's Exact/Exact Value fields
    all legible in dark mode.
13. **Layout:** at the window's minimum width with the sidebar open, the
    input pane still shows editor + controls + status without clipping;
    clicking either control never steals keyboard focus from the editor
    (typing continues immediately).
14. Quit ⌘Q → `pgrep -fl "Casette|sage -python|worker.py"` → empty.

**Next.** V1.9 — session persistence (after the V1.8 live gate passes).

---

## 2026-06-12 — V1.7: Plot rendering v1 — PASS (live gate PASSED after one fix round)

**Final live gate (opus verifier, computer-use) — PASS, all 9 re-checks.**
On screen: `implicit_plot(x^2+y^2==1, (x,-2,2), (y,-2,2))` renders a clean
unit circle out of the box with `t x y z` in Symbols from boot AND after
restart; **all three hang repros are dead** — Copy Image context menu, Save
panel cancel, selected-plot-row through scroll+eval — each followed by 10s
CPU sampling at 0.0–0.1% (was a sustained 100% AttributeGraph spin); a ~2 min
mixed-interaction stress (menus, Esc dismissals via send-key, row selection,
tab switches, brisk scrolling, evals, a fresh plot) never exceeded 0.1% CPU
and ended fully responsive; multi-plot card stacks sine+cosine; zoom sheet
opens/closes via Done and Esc; quit clean, `pgrep` clean. **Cosmetic note for
a later pass:** the fixed input bar overlaps tall plot cards at the default
window height. **Verifier env note:** ⌘⇧R doesn't fire through the MCP key
tool (harness limitation, like Esc) — the menu item works; re-confirm the
shortcut in V1.12 with send-key.swift.

### Fix round (2026-06-12, two agents — the first killed mid-work by quota; this entry covers the completed round)

**The live gate failed on two things; both are fixed.**

1. **CRITICAL: main-thread hang — an infinite SwiftUI AttributeGraph update
   loop** (100% CPU, frozen app; three occurrences: during plot-image
   context-menu tracking ×2 and when a selected plot row updated/scrolled).
   Diagnosed by `sample(1)`: every sample inside one runloop-observer graph
   update, `updateNSView` → AppKit invalidation
   (`_invalidateEffectiveFont` / `invalidateIntrinsicContentSize`), never
   converging. **Root cause — two co-conspirators, both needed fixing:**
   (a) unguarded NSView property writes that self-invalidate during the
   graph update — `MTMathUILabel`'s setters unconditionally invalidate
   intrinsic size/layout, and `sizeThatFits` wrote to the LIVE label;
   (b) intrinsic-size negotiation on plot images
   (`.resizable().scaledToFit()` + max-frames) re-proposing every pass
   inside rows that also host AppKit-backed views. **Fixes
   (structural):** `SwiftMathRenderer.swift` — `sizeThatFits` is now PURE
   (measures via `MathMeasurementCache`, an offscreen never-hosted label
   behind a bounded memo) and EVERY `configure` write is change-guarded;
   `PlotImageWell.swift` — the displayed size is computed ONCE from the
   decoded raster by the pure, unit-tested
   `PlotImageWell.fittedDisplaySize` (fit into measured available width ×
   `Theme.plotMaxHeight`, aspect-preserving, never upscaled, whole points)
   and applied as an explicit `.frame(width:height:)`; the available width
   is measured with `onGeometryChange` off the well's full-width container
   (parent-determined, so the feedback can't oscillate). Full mechanism,
   sample-trace anatomy, and the invariant ("no representable may write to
   its own NSView during measurement; every `updateNSView` write must be a
   real change"): **new PROBLEMS.md entry "AttributeGraph spin"**.
2. **`implicit_plot(x^2+y^2==1, (x,-2,2), (y,-2,2))` NameError'd out of the
   box** — raw-Sage input bypasses the friendly compiler's `var('V')`
   preludes, and boot predefined only `x`. **Decision (approved product
   call, a deliberate deviation from strict REPL fidelity):**
   `ShellModel.bootPrelude` is now **`var('x, y, z, t')`** — the
   conventional calculator variables, so implicit/parametric/3D doc
   examples work verbatim; all four show honestly in Symbols from boot and
   after ⌘⇧R. Documented in plans/FRIENDLY-COMPILER.md (Variable policy,
   V1.7 extension). Friendly `var('V')` preludes are unchanged and still
   load-bearing for everything else (the integration test now proves `u`).

**Fix-round gate.** `make check` ✓ · **`make test` 236/236** (38 suites;
was 231 — +4 `PlotImageWell.fittedDisplaySize` unit tests (aspect preserved
under the height cap, never upscale, width cap wins when narrower,
unmeasured-width first pass + degenerate input) and +1 real-Sage
integration test (`implicitPlotWorksWithoutDeclaringVariables`: the
docs-verbatim implicit_plot through the ShellModel seam — the REAL app
path, boot prelude only — evaluates ok with a present, decode-verified
PNG; the prior plot-journey test had masked the failure by declaring
`x, y` itself). Boot-prelude tests updated to the 4-variable contract
(fake-transport wire order ×2, restart symbols `t x y z`, real-Sage
prelude test; the friendly-prelude integration test now binds `u`).
swiftui-pro on the changed views — clean (no findings; `onGeometryChange`
is the sanctioned measurement API, fitting math pure and out of `body`).
`make build` ✓ · **live stress (Bash-driven CGEvent/osascript, CPU sampled
every 2s for ~5.5 min, 163 samples):** submitted all three plot shapes
(friendly `plot sin(x)`, raw `implicit_plot` — worked, PNG saved, NO
NameError — and the multi-`show()` pair), then 20 iterations of
click-a-plot-row + scroll up/down + evaluate `1+1` (per-iteration CPU
1.1–5.1%), plus the three exact hang repros: right-click the plot image →
Copy Image via the menu (TIFF verified on the clipboard; CPU 0.7%),
Save Image As… opened and CANCELLED via `send-key 53` (CPU → 0.0%), and a
SELECTED plot row through scroll + a new eval (CPU → 0.0%). **Max
momentary CPU across the whole run: 20.2% (render bursts); idle 0.0% — no
trace of the 100% spin.** AppleScript quit →
`pgrep -fl "Casette|sage -python|worker.py"` clean.

**What remains for the verifier (fix-round additions to the checklist
below):** the three hang repros — right-click a plot image → Copy Image,
then Save Image As… and CANCEL the panel; click-select a plot row and
scroll briskly; leave a selected plot row on-screen during a new eval —
each followed by ~10s of `ps -o %cpu= -p <pid>` staying at idle levels
(a sustained 100% = the spin is back); and
`implicit_plot(x^2+y^2==1, (x,-2,2), (y,-2,2))` rendering a unit circle
with NO NameError straight after boot, with `t x y z` listed in Symbols.

---

**Plot rows render the real PNG.** The V1.5 placeholder box is gone:
a plot row's card shows the actual image(s) the worker saved — bounded
height (280pt cap, aspect-preserving, never upscaled past natural size),
PNG ONLY (the frozen V0.5 verdict: `NSImage` mis-rasterizes matplotlib SVG
into a black blob; SVG entries stay in the model and the Inspector but are
never rendered). Click an image → a **standard sheet** at full resolution
(two-axis scroll past the cap sizes; the Done button carries
`.cancelAction`, so **Esc just works natively** — no EscapeInterceptor; the
sheet opens at the image's natural size capped to 1000×760). Right-click
the image → **Expand Plot / Copy Image / Save Image As… / Reveal in
Finder** (the row's own context menu still owns everything outside the
image). A multi-plot eval (`p1.show(); p2.show()`) stacks one image per
plot in call order in the same card, each with its own zoom/menu. The
caption stays the envelope's `plain`, selectable below the images.

### How it works (the V1.7 surfaces)

- **`Model/PlotRendition.swift`** — the testable selection logic: a
  result's renderable plots are its **PNG artifacts in worker order**
  (each captured plot yields one SVG+PNG pair, so the PNGs ARE the plots —
  multi-plot included). A failed PNG save still yields a rendition (path
  nil + the save error) so the card carries the honest state.
- **`Rendering/PlotImageCache.swift`** — image loading off the main
  thread: a `@MainActor` bounded cache (64, whole-reset on overflow —
  §3.2, the `MathRenderCache` precedent) over a `nonisolated` async decode
  (`CGImageSource` with `ShouldCacheImmediately`, so the PNG decode happens
  on the global executor, not lazily at first draw). A non-nil image IS a
  decoded raster — `CGImageSource` has no "loads fine, renders wrong" PNG
  path (the V0.5 lesson respected: decode-verify, don't trust a non-nil
  `NSImage`). Keyed by path; paths are never rewritten (monotonic
  `plot-NNNNN`, rerun = new row + new paths), so cache entries can go
  unused, never stale. Point size = pixel size, so "natural size" in the
  zoom sheet is the full-resolution raster.
- **`Views/PlotCardView.swift` / `PlotImageWell.swift`** — the card stacks
  one well per rendition; each well: quiet fixed-size loading box (no tape
  jumping) → the image as a **plain-style `Button`** (click = expand;
  honest to assistive tech) → or the missing state. The well's `.task(id:)`
  checks the cache synchronously first so recycled LazyVStack rows re-show
  instantly.
- **`Views/PlotMissingView.swift`** — the honest missing state ("Plot
  image missing — rerun to regenerate it", quiet, because the worker's
  /tmp session dir dying IS the normal case) with a **Rerun button** wired
  to the existing History rerun path (`ShellModel.rerun(rowID:)` — fresh
  row, original untouched). A worker save FAILURE shows its structured
  reason instead ("PNG couldn't be saved — OSError: …").
- **`PersistedArtifact.error`** — ONE additive schema field (same pattern
  as V1.5's `truncation`, documented in SESSION-FORMAT.md): the worker's
  per-format save error now survives the mapping, optional +
  omitted-when-nil, schema v1 unchanged. The Inspector's artifact rows
  show "Failed to save — <error>" when it's present.
- **Wiring:** `TapeRowView`/`TapeRowResultView` gain `onRerun`;
  `SessionTapeView` supplies `model.rerun(rowID:)`. `Pasteboard.copy(image:)`
  added. The Actions tab's plot actions (`save_png`/`save_svg`/`show`)
  stay inert but the tooltip now points at the plot card's context menu
  (V1.11 may wire them properly). `PlotPlaceholderView` deleted.

### Gate (all PASS; live gate pending)

- `make check` ✓ · **`make test` 231/231** (37 suites; was 222 — +9:
  `PlotRenderingTests` ×5 (multi-plot mapping → renditions in call order,
  save-error mapping, SVG-only → no rendition, non-plot → none, additive
  `error` field Codable round-trip incl. omitted-when-nil + legacy decode),
  `PlotImageCacheTests` ×2 (real-PNG decode + memoization same-instance;
  gone file and garbage data both nil, failures uncached),
  `PlotRowFlowTests` ×1 over the fake transport (a multi-plot envelope's 4
  artifact entries land on the SESSION ROW, 2 renditions, liveness
  resolved; card rerun = fresh row), `PlotIntegrationTests` ×1 against
  REAL Sage 9.5 (the journey: `plot(sin(x), (x, -pi, pi))` → present PNG
  on disk that decode-verifies; `implicit_plot(x^2+y^2==1, …)` works;
  `p1.show(); p2.show()` → 2 present renditions at distinct paths; the
  failing plot is a normal readable error envelope with no artifacts; the
  worker survives)).
- **Full V0 regression:** V0.1 **18/18** · V0.2 **35/35** · V0.3 **97/97**
  · V0.5 **88/88** · V0.6 **24/24** · V0.8 **95/95** · V0.7 swift
  **69/69** + e2e **19/19** · V0.9 swift **32/32** · V0.10 swift **21/21**
  (no flakes this round). `pgrep -fl "sage -python|worker.py"` clean.
- **Skills:** swiftui-pro — one finding applied:
  `PlotMissingView`'s `.accessibilityElement(children: .combine)` would
  have merged the Rerun button into one inert element; now the icon is
  decorative-hidden and the button stays individually activatable. Image
  click is a plain `Button` (not a tap gesture), actions extracted to
  methods, `.task(id:)` for loading, no GCD, a Save As failure shows an
  `NSAlert` (never swallowed silently). macos-design — standard sheet for
  zoom (window-modal, native Esc via `.cancelAction`), context-menu
  vocabulary is the Finder idiom ("Reveal in Finder", "Save Image As…"
  with ellipsis), missing state reads quiet (it's normal), fixed-size
  loading box so the tape never jumps, no min-height bombs (everything
  lives in scroll content). typography — no new tokens; the caption stays
  `meta`, the sheet title is the input echo in `rowInput` (mono = Sage
  voice).
- `make build` ✓ (bundled worker.py `cmp` byte-identical) · launched
  `build/Casette.app` via `open`: alive 12s+ with exactly ONE worker
  chain, AppleScript quit → `pgrep -fl "Casette|sage -python|worker.py"`
  clean.

### Known gaps (deliberate)

- SVG is never rendered (frozen V0.5 verdict) — a real SVG engine is a
  future-engine question, not V1.7.
- The Actions tab's `save_png`/`save_svg`/`show` are still inert (tooltip
  points at the plot card); wiring them is V1.11 territory.
- Artifacts comfortably outlive their evals in-session (the exit
  criterion): the dir is only rmtree'd by a clean worker `shutdown` op,
  and the app's restart/quit paths hard-kill (group kill, no cleanup) —
  so files survive even ⌘⇧R, and the in-memory cache keeps
  already-rendered images alive regardless. Net: the file-missing box is
  effectively a RESTORE-time state (V1.9) plus the save-failure case;
  in-session it's nearly unreachable, by design.
- The zoom sheet shows the PNG at its natural raster size (no zoom
  slider / pinch); the PNG is ~100 DPI so it reads slightly large on
  Retina — acceptable for v1.

### On-screen verifier checklist (V1.7 — pending)

In `build/Casette.app` (real Sage), verify on screen:

1. Evaluate `plot sin(x), x=-pi..pi` (friendly) → the card shows a real
   sine-wave PNG (axis labels readable — no black blob), bounded height,
   with the "Graphics object …" caption below; the row's input echo and
   timestamp render as before.
2. Evaluate `implicit_plot(x^2+y^2==1, (x,-2,2), (y,-2,2))` (raw) → a unit
   circle renders.
3. Multi-plot: evaluate
   `p1 = plot(sin(x)); p1.show(); p2 = plot(cos(x)); p2.show()` → ONE card
   with TWO stacked images (sine then cosine, call order).
4. Failing plot: `plot(sin(x), (x, 0, 'notanumber'))` → a normal red error
   card (readable type + message, traceback behind the expanded
   disclosure), NO image, and the next eval still works.
5. Click the sine image → a sheet opens at full resolution with the input
   echo as its title; the window behind is blocked (sheet is modal). Click
   Done → it closes. Re-open it, then press Esc — **inject via
   `scripts/send-key.swift 53 <pid>`** (the harness EATS Esc; PROBLEMS.md)
   → the sheet closes.
6. Right-click the sine image → menu reads Expand Plot / — / Copy Image /
   Save Image As… / Reveal in Finder. Copy Image → paste into Preview
   (File → New from Clipboard) shows the plot, or verify
   `osascript -e 'clipboard info'` lists image data.
7. Reveal in Finder → a Finder window opens selecting
   `/tmp/sagecalc/session-…/plot-NNNNN.png`.
8. Select the plot row → Inspector's Artifacts section shows SVG and PNG
   "On disk · ~N KB" (the V1.6 rows, still working).
9. Save-failure → honest box + rerun: in Terminal,
   `chmod 555 /tmp/sagecalc/session-*` (the worker's plot dir read-only),
   then evaluate `plot tan(x), x=-1..1` (friendly) → the eval still
   SUCCEEDS (V0.5 structured per-format errors) but the card shows the
   quiet box "PNG couldn't be saved — PermissionError: …" with a Rerun
   button; the Inspector's Artifacts for that row read "Failed to
   save — …".
10. `chmod 755 /tmp/sagecalc/session-*`, then click that box's Rerun →
    a FRESH row evaluates at the tape end with a real rendered image;
    the failed row keeps its honest state. (The file-GONE variant of the
    box — "Plot image missing — rerun to regenerate it" — is the V1.9
    restored case; in-session files survive even ⌘⇧R because restart
    hard-kills without the worker's cleanup. Its selection logic is
    unit-tested.)
11. Select a plot row → Actions tab lists Show / Save PNG / Save SVG as
    disabled rows whose tooltip points at the plot card's context menu.
12. Dark mode: the plot card (white matplotlib canvas) sits acceptably on
    the dark row, caption/missing text legible, sheet chrome legible.
13. Scroll performance: with ~10 mixed rows including 4+ plot images,
    scroll the tape briskly up and down — no hitching; images reappear
    instantly when scrolled back (cache, no placeholder flash).
14. Save Image As… → save to ~/Desktop → the PNG opens in Preview
    byte-identical (same pixel size).
15. Quit ⌘Q → `pgrep -fl "Casette|sage -python|worker.py"` → empty.

**Next.** V1.8 — exact/numeric controls (after the V1.7 live gate passes).

---

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

## 2026-06-11 — V1.5: Result rendering v1 — PASS (live gate PASSED after one fix round)

**Final live gate (opus verifier, computer-use) — PASS, all 8 re-checks.**
On screen: `expand((x+1)^8)` typesets the full polynomial with braced
superscripts, no NameError, `x` predefined from boot AND after ⌘⇧R restart;
the `8/15` fraction hero is now visibly larger than its input echo (hierarchy
correct); matrix rows fully visible at default window size; Inspector
"Rendered" leading-aligned and whole; pasted curly-quoted `print("hello")`
normalizes and prints; solve list shows `[x = -3, x = -2]` with no redundant
parens while Copy LaTeX preserves Sage's original; dark mode re-tints all
typeset math correctly; quit clean, `pgrep` clean. **Verifier's aesthetic
verdict: "a polished, native-feeling macOS calculator tape."**

> **This phase spans three agent runs.** The implementation agent built the
> feature and was killed (quota) before running the gate or writing docs; a
> completion agent audited the work against the INITIAL.md V1.5 spec (all
> items found genuinely implemented), applied the skill findings, ran the FULL
> gate below, and wrote these docs. The live on-screen verifier then returned
> **PASS with caveats**; a fix agent resolved all six flagged items (next
> section) — the caveats need one focused on-screen re-check.

**The tape renders math.** The V0.4-proven SwiftMath engine is in the app
behind the lifted `MathRenderer` abstraction, and every row is now a V1.5
result card.

### Fix round (2026-06-11) — the verifier's caveats, all six resolved

1. **`expand((x+1)^8)` NameError'd** — raw-Sage bypasses hit the worker
   namespace where `x` is NOT predefined (PROBLEMS.md V0.5), unlike the real
   Sage REPL. **Decision implemented: match the REPL.** `ShellModel` now
   sends a `var('x')` boot prelude (`ShellModel.bootPrelude`) after every
   boot AND every restart, app-side (worker.py stays byte-frozen, `cmp`
   verified), then refreshes symbols — `x` honestly shows in the sidebar
   from boot, exactly like the REPL predefining it. The friendly compiler's
   own `var('x')` preludes on top are idempotent and harmless. Tests:
   fake-transport boot/restart prelude wire order, two updated order
   assertions, and a real-Sage integration test (`expand((x+1)^8)` →
   symbolic envelope with `x^{8}` straight after boot; after restart,
   symbols == `[x]` and `expand((x+1)^2)` still works).
2. **Fraction hero undersized (the headline beauty flaw) — root cause was
   NOT labelMode** (the hero already used `.display`): the representable's
   `sizeThatFits` read `MTMathUILabel.intrinsicContentSize`, **which
   SwiftMath overrides on iOS only** — on macOS it returns NSView's
   no-intrinsic sentinel (-1, -1), so EVERY math hero was laid out 0pt wide
   × (fontSize+6 = 25)pt tall. Single-line math drew outside its frame
   unclipped and *looked* right (which is how v0/04 passed); the hero's
   clipping `ScrollView` squeezed fractions (39pt tall at 19pt display
   mode) and matrices. Fixed: read `fittingSize` (the macOS accessor for
   the typeset size). Display-mode `\frac{8}{15}` measures 19×39 vs
   text-mode 13×23 — both the engine fact and the hero=display policy are
   locked in by the new `SwiftMathSizingTests`. PROBLEMS.md V0.4 sizing
   entry CORRECTED; MATH-RENDERING.md extended (fix-round section).
3. **Matrix bottom row clipped at default window size** — largely the same
   0×25 sizing bug (the matrix overdrew its frame downward, past the scroll
   viewport); additionally the tape now has a real bottom inset:
   `.contentMargins(.bottom, Theme.tapeBottomMargin, for: .scrollContent)`
   (a scroll-content margin, NOT a spacer), so the bottom rest position and
   `scrollTo(anchor: .bottom)` always leave the last row's full height
   clear of the input pane.
4. **Inspector "Rendered" preview clipped/right-aligned** — width-0 sizing
   (same root cause) compounded by `LabeledContent`'s trailing value
   alignment. Now leading-aligned filling the value column, with a
   horizontal ScrollView for wide matrices (scroll keeps the typeset size
   honest where scale-to-fit would shrink it unreadably — macos-design
   reviewed), and `accessibilityHidden` (the NSView is silent to VoiceOver;
   the adjacent Plain/LaTeX fields are the spoken value — swiftui-pro
   finding, applied).
5. **Smart quotes** — `print(“hello”)` SyntaxError'd. `CompiledInput` now
   normalizes U+201C/U+201D → `"` and U+2018/U+2019 → `'` at the compile
   boundary, BEFORE the bypass/friendly decision (and for chosen ambiguity
   candidates and the multiline bypass path), so the row's recorded raw
   input is exactly what was evaluated. Documented trade-off: pasted string
   literals CONTAINING curly quotes are altered too — acceptable for a
   calculator input field. Tests: compile-boundary unit tests + a
   fake-transport test proving the wire and the row both see ASCII.
6. **Solve-list `[x = (−3)]` redundant parens** — done (it turned out
   cheap and safe as a display-only normalizer rule):
   `SageLatexNormalizer.stripRedundantRelationParens` rewrites
   `= \left(-3\right)` → `= -3` only after a relation sign, only for a bare
   signed integer / `a/b` / `\frac{a}{b}`, and never when the group carries
   a script (load-bearing parens). Shapes verified against real Sage 9.5
   latex output; Copy LaTeX still yields Sage's own unmodified string.

**Fix-round gate.** `make check` ✓ · **`make test` 205/205** (30 suites; was
197/197 — +8 new: boot/restart prelude over fakes, wire-level smart quotes,
compile-boundary smart quotes, relation-parens strip ×2, SwiftMath sizing
facts ×2, real-Sage boot-prelude integration) · **v0/07 e2e 19/19** (the
worker and kernel were untouched — quick regression sanity only; bundled
worker.py `cmp` byte-identical) · swiftui-pro (one finding, applied: a11y-
hide the silent NSView preview in the Inspector) + macos-design (clean:
content margin over spacer, scroll over scale-to-fit, hero-dominates-echo
hierarchy) · `make build` ✓ · launched `build/Casette.app` via `open`: alive
14s with exactly ONE worker chain, AppleScript quit →
`pgrep -fl "Casette|sage -python|worker.py"` clean.

**Re-verification checklist (the six caveats, on screen):**
1. `expand((x+1)^8)` → a typeset polynomial card, NO NameError; the Symbols
   tab lists `x` from boot. Then ⌘⇧R and `expand((x+1)^2)` → works; Symbols
   shows exactly `x` again right after the restart.
2. `1/3 + 1/5` → the `8/15` fraction hero typesets LARGER than the input
   echo line (full-size digits, display mode), `≈ 0.5333333333` below it.
3. `matrix([[1,2],[3,4]])` at the default window size → BOTH matrix rows
   fully visible with the tape rested at the bottom — nothing tucked behind
   the input pane; clear breathing room below the last row.
4. Select the matrix row → Inspector "Rendered" preview is leading-aligned
   and fully visible in the column (whole matrix incl. both parens); a wide
   matrix scrolls horizontally inside the preview.
5. Type/paste `print(“hello”)` WITH curly quotes → statement card with
   stdout `hello`, no SyntaxError; the row's input echo shows straight
   quotes (exactly what was evaluated).
6. `solve x^2 + 5*x + 6 = 0` (friendly) → list card reads `[x = -3, x = -2]`
   with no redundant parens; context-menu Copy LaTeX still yields Sage's
   original parenthesized string via `pbpaste`.

### What was built

- **`Sources/Casette/Rendering/`** — the v0/04 surviving artifact, split
  one-type-per-file: `MathRenderer` (protocol), `SwiftMathRenderer` (active
  engine; `MTMathUILabel` representable with `sizeThatFits` →
  ~~`intrinsicContentSize`~~ *(superseded by the fix round: that override is
  iOS-only — on macOS it's `fittingSize`)* so math never collapses/overlaps,
  `.labelColor` for free dark mode), `SageLatexNormalizer` (the load-bearing Sage
  `array`→`pmatrix`/`bmatrix`/`vmatrix`/`Bmatrix` rewrite, byte-equivalent
  rules), `MathView` (the one `activeMathRenderer` line), plus two V1.5
  additions: **`MathRenderCache`** (bounded `@MainActor` memo of
  normalize+parse keyed by raw latex — hover/selection re-renders and
  LazyVStack recycling stop re-running regexes/parser; typeset stays on main
  because `MTMathUILabel` is an NSView and native typeset is fast) and
  **`MathContent`** (the card-level fallback decision: `.math` only when the
  cached parse succeeds, else `.plain`). `LaTeXSwiftUIRenderer` deliberately
  NOT lifted (multi-MB MathJax bundles for an engine V0.4 measured broken
  here); the seam is what survives. Details: plans/MATH-RENDERING.md §V1.5;
  perf traps: PROBLEMS.md (new entry).
- **`Model/ResultCardKind.swift`** — the spec's card vocabulary as a derived
  (never stored) presentation enum off the frozen envelope: scalar exact /
  scalar approximate (incl. V0.8 force-numeric via `primaryIsApprox`) /
  symbolic (+relation) / matrix / list (incl. tuple + solve's Sequence) /
  plot / text (boolean/unknown degrade here) / error, plus
  pending/statement/interrupted row states.
- **Card anatomy.** Collapsed: chevron + input echo + timestamp +
  hover-revealed Copy button, then the rendered result (`ResultHeroView`:
  block math hero with horizontal scroll for wide results,
  VoiceOver-bridged to `plain`; `≈ approx` secondary line; honest
  truncation note). Expanded (chevron toggles the persisted
  `SessionRow.expanded` via `ShellModel.toggleExpanded`): Input / Generated
  Sage / Plain sections (`CardSectionView`, each with its own copy context
  menu) + the traceback disclosure. Structural conditional, NO transition
  (§1.1). Errors/interrupts: type + message prominent (red/orange),
  traceback hidden behind `TracebackDisclosureView` (hand-rolled, not
  `DisclosureGroup` — it animates insertion), scrolling past 180pt, also in
  the Inspector. `stdout` renders as a labeled mono block ABOVE the result
  (execution order) for every card; statement rows show it alone. Plot rows
  keep the placeholder chrome until V1.7.
- **Truncation honesty.** `PersistedEnvelope` gains the optional
  `truncation` sizes object (`plain_len`/`repr_len`/caps) — the ONE additive
  deviation from the verbatim V0.10 lift, documented in SESSION-FORMAT.md
  (schema v1 unchanged; omitted-when-nil). `factorial(10^5)` now reads
  "Truncated — showing 8,192 of 456,574 characters" instead of a bare flag.
- **Copy affordances:** row context menu (Input / Generated Sage / Result /
  LaTeX / Traceback, each gated on presence), hover button (result, falling
  back to input), per-section menus in the expanded card, traceback menu.
- **Inspector additions:** small rendered LaTeX preview (only when the
  engine parses it), truncation note, traceback disclosure.
- **Theme:** card metrics + four type tokens (`cardSectionLabel`,
  `cardMono`, `tracebackMono`, `truncationNote`) on the existing two-axis
  system; math point sizes 19/13 are the one documented §5.1 deviation
  (`MTMathUILabel` takes raw points; 19 > title3's 15 because typeset math
  reads optically smaller).
- **Build:** Package.swift pins SwiftMath ≥1.7.3 (same as the v0/04 proof);
  `build.sh` copies SwiftPM resource bundles (`SwiftMath_SwiftMath.bundle`
  with `mathFonts.bundle`) into `Contents/Resources` — verified present in
  the assembled app (without it math renders nothing at runtime).

### Gate (completion agent, all PASS)

- `make check` ✓ · **`make test` 197/197** (28 suites) — incl. new
  `MathRenderingTests` (normalizer rules + `MathContent` fallback + cache
  consistency), `ResultCardKindTests` (mapping + presentation-only +
  truncation-note + Codable round-trip), and `ResultRenderingIntegrationTests`
  against REAL Sage (matrix `array`→pmatrix end-to-end, `expand((x+1)^8)`
  braced scripts parse, solve-list latex renders, `1/3+1/5` exact + approx,
  `print("hello")` → statement card with stdout, `factorial(10^5)` truncated
  with sizes).
- **Full V0 regression:** V0.1 **18/18** · V0.2 **35/35** · V0.3 **97/97** ·
  V0.5 **88/88** · V0.6 **24/24** · V0.8 **95/95** · V0.7 swift **69/69** +
  e2e **19/19** · V0.9 swift **32/32** · V0.10 swift **21/21**. `pgrep`
  clean after (see anomaly note below).
- **Skills applied:** swiftui-pro — one finding (chevron disclosure button
  rewritten from icon-only `Image` label to the `Button(_:systemImage:)` +
  `.labelStyle(.iconOnly)` form, matching the Copy button); everything else
  conformed (no deprecated API, `.animation` always has `value:`, semantic
  fonts, a11y bridges on the math NSView and the tap-selection row).
  macos-design — clean (progressive disclosure, hover-reveal via opacity,
  context menus, `.help` tooltips, semantic colors; the no-transition
  expand is the project's own §1.1 rule). typography-designer — clean (new
  tokens land on the existing scale; hierarchy stays monotonic: math hero
  19 > title3 hero > callout mono > caption).
- `make build` ✓ (fonts bundle in Resources) · launched `build/Casette.app`
  via `open`: alive ~13s with exactly ONE Sage worker, AppleScript quit →
  `pgrep -fl "Casette|sage -python|worker.py"` clean.
- **Anomaly noted (not V1.5 code):** a leftover Casette.app from the killed
  implementation run was found holding THREE live workers (boot 21:29 + two
  more sessions at 22:04, per the worker log). V1.5 touched nothing under
  Kernel/, the cause couldn't be reconstructed (the run was killed
  mid-phase), and the quit-time reaper cleanly killed all three generations
  on AppleScript quit. If the verifier ever sees multiple workers under one
  app pid, capture `ps` ancestry + the worker log BEFORE quitting.

### On-screen verifier checklist (V1.5 — pending)

In `build/Casette.app` (real Sage), verify on screen:

1. `1/3 + 1/5` → scalar-exact card: rendered `8/15` fraction hero,
   `≈ 0.5333333333` secondary line below it.
2. `sqrt(2)` → symbolic card: rendered radical, `≈ 1.414213562` line.
3. `expand((x+1)^8)` → long polynomial with braced superscripts (`x^{8}`)
   typeset correctly; wide math scrolls horizontally inside the card.
4. `matrix([[1,2],[3,4]])` → parenthesized 2×2 matrix (the `array`→pmatrix
   rewrite, on screen).
5. `solve x^2 + 5*x + 6 = 0` (friendly) → list card with rendered solutions.
6. `print("hello")` → statement card: labeled `stdout` block, no value hero.
7. `1/0` → error card: `ZeroDivisionError` + message in red, NO traceback
   visible; expand the row → Traceback disclosure → click → traceback text,
   scrolls if long; context menu has Copy Traceback.
8. `factorial(10^5)` → digits + "Truncated — showing 8,192 of 456,574
   characters" note.
9. `plot sin(x), x=-pi..pi` (friendly) → plot card chrome (placeholder
   image + caption — real PNG is V1.7).
10. Chevron expands a card: Input / Generated Sage / Plain sections appear
    under the still-visible rendered result; chevron rotates; collapse
    restores; expanded state survives scrolling away and back.
11. Copy: hover a row → copy button fades in, click → `pbpaste` matches
    plain; context menu Copy Input / Generated Sage / Result / LaTeX each
    verified via `pbpaste`.
12. Dark mode: math re-tints to white (semantic `.labelColor`), all card
    chrome legible.
13. Scroll performance: evaluate ~15+ mixed rows (reuse the inputs above),
    scroll the tape up/down briskly — no visible hitching; hover rows while
    scrolling.
14. Inspector: select the matrix row → Rendered preview above the LaTeX
    source; select the error row → Error type + traceback disclosure.
15. Quit via ⌘Q → `pgrep -fl "Casette|sage -python|worker.py"` clean.



Append-only. Newest entries at the top. One entry per meaningful change:
what changed, what I learned, what surprised me.

---

## 2026-06-11 — V1.4: Input pane v1 — PASS (live gate PASSED across rounds 4+5)

**Live gate (opus verifier, computer-use) — PASS, evidence combined across
two rounds of identical code.** Round 4 verified on screen: digit `2`
selects the y-candidate (`[y == (1/x)]`), Return selects the first
candidate, clicking a candidate works, type-through inserts + dismisses,
Esc passthrough with no panel is safe, history walk (incl. past a multiline
entry, cursor-reset-on-edit), smoke (`factor x^4 - 1`, `1+1`), and clean
exit with zero orphans. Round 5 verified the one remaining item — **Esc
dismisses the panel with the draft kept** — twice, using
`scripts/send-key.swift 53 <pid>` to bypass the harness's Esc-eating event
tap (see fix round 5 + PROBLEMS.md). Round 5 was then interrupted by the
machine's idle screen lock; the regression items it didn't re-reach are
exactly those round 4 had already passed (the only code delta between
rounds was temporary logging, since removed). App quit cleanly via
AppleScript post-lock; `pgrep` clean. Earlier rounds also verified: friendly
compile + preview line, raw-bypass tag, double integral → 1/8, prelude
policy (clean Generated Sage, `t` in Symbols), inline error never submits,
⇧⏎ multiline grow, ⌘⏎ evaluate-without-advancing, dark mode.

### Fix round 5 (2026-06-12, orchestrator) — Esc was NEVER an app bug after round 2: the AUTOMATION HARNESS eats keyCode 53 system-wide

Rounds 3–4 "failed on screen" because the verifier's Esc presses never
reached the app at all. Temporary logging in `EscapeInterceptor` showed the
local monitor logging every keyDown EXCEPT Esc; a session-level CGEvent tap
saw the injected Esc, but a pid-level tap on Casette never did.
`CGGetEventTapList` found the cause: a session-wide **filtering keyDown tap
owned by the computer-use harness itself** (its abort key), which consumes
every Esc — physical, MCP `key`, or AppleScript — before per-app delivery.
Posting Esc directly to the app's pid (`CGEvent.postToPid`, new helper
`scripts/send-key.swift`) proved the round-4 `EscapeInterceptor` correct:
`onEscape -> true`, panel dismissed, draft kept. Full story + rules in
PROBLEMS.md ("THE AUTOMATION ENVIRONMENT EATS Esc"); V1.12 must verify
shortcuts with the helper. 172/172 tests still green after removing the
instrumentation.

### Fix round 4 (2026-06-11) — Esc, finally: NSTextView EATS `cancelOperation:`; only an AppKit local NSEvent monitor can see Esc first

Round 3's `.onExitCommand` fix failed on-screen verification exactly like
rounds 1–2's `.onKeyPress(.escape)`: panel up, Esc pressed, panel stays
(third independent on-screen confirmation; every other path — digits 2–9,
Return-takes-first, click, type-through-dismisses, history — kept working).
**Root cause, completing round 3's half-right diagnosis:** Esc IS translated
to `cancelOperation:` before key-press handlers run (round 3 was right
there), but the `NSTextView` backing `TextEditor` implements
`cancelOperation:` itself (it uses it to dismiss completion sessions) and
CONSUMES it — the action never travels up the responder chain, so SwiftUI's
`.onExitCommand` never hears about it either, no matter where it's attached.
Conclusion: **no SwiftUI-level hook on or above a focused TextEditor can see
Esc.** The fix drops to AppKit at the one interception point that runs
before the window dispatches the key at all: a local NSEvent monitor.

**The fix:**
- New `Sources/Casette/Views/EscapeInterceptor.swift`: an
  `NSViewRepresentable` whose backing `NSView` owns
  `NSEvent.addLocalMonitorForEvents(matching: .keyDown)`. On
  `keyCode == 53` it asks its `onEscape: () -> Bool` closure; `true` →
  return `nil` (event swallowed before the text view sees it), `false` →
  event passed through unchanged. Guards: `event.window === self.window`
  (other windows never affected), weak `self` in the handler (no
  view↔monitor retain cycle), `hitTest → nil` (invisible to the mouse).
  Lifecycle: `viewDidMoveToWindow` installs the monitor exactly once
  (token-nil guard — SwiftUI re-renders can't stack duplicates) and
  removes it on window detach; `deinit` is the backstop
  (`nonisolated(unsafe)` on the token, documented — only ever written on
  the main actor, deinit access is exclusive). The handler hops into
  `MainActor.assumeIsolated` (local monitors dispatch on the main run
  loop; the imported AppKit closure type just isn't annotated).
- `InputPaneView` mounts it: `.background(EscapeInterceptor {
  model.cancelAmbiguity() })`. Behavior scoped by the model, not the
  monitor's lifetime: `cancelAmbiguity()` returns `false` when no panel
  is pending, so plain Esc passes through and keeps its system behavior
  (full-screen exit etc.). The monitor simply lives as long as the pane.
- `InputEditor`: the dead round-3 `.onExitCommand` and rounds-1–3
  `.onKeyPress(.escape)` routes + `handleEscape` are REMOVED (not kept as
  "fallbacks" — they imply they can fire, and they can't; comments now
  point at `EscapeInterceptor`). Return/digits/Up/Down handlers untouched.

No model changes — `cancelAmbiguity()` and its tests are as round 1 left
them. PROBLEMS.md inline-overlay entry rewritten (round-4 symptoms, the
consume-don't-forward cause, rule 4 replaced: Esc over a focused text view
is invisible to SwiftUI; intercept with a local NSEvent monitor, swallow
only when there's something to cancel in your window).

**Gate (fix round 4).** `make check` ✓ · `make test` **172/172** (key
routing stays unfalsifiable by unit tests — PROBLEMS.md rule 2) ·
swiftui-pro sanity on the three touched files (one type per file; no
`import AppKit` needed under SwiftUI; concurrency escape hatches scoped and
documented; closure refreshed in `updateNSView` so it never goes stale) ·
`make build` ✓ · launched `build/Casette.app` via `open`: alive 8s+ with
Sage worker booted, AppleScript quit → `pgrep -fl "Casette.app|sage
-python|worker.py"` clean. **On-screen Esc re-check (checklist step (a))
still needs the verifier pass — but unlike rounds 1–3 this route runs
before the text view can interfere, by construction.**

### Fix round 3 (2026-06-11) — Esc on the inline panel: `cancelOperation:` needs `.onExitCommand`

Round 2's inline overlay verified on every path but ONE: Esc didn't dismiss
the panel (digits/Return/click/type-through all fine; the editor clearly
kept focus, since a typed `z` landed in the field and dismissed it).
**Root cause:** on macOS, Escape never reaches a focused text view as a key
press — the Cocoa key-binding system translates it into the
`cancelOperation:` ACTION first, which walks the responder chain, so the
round-1/2 `.onKeyPress(.escape)` handler on the `TextEditor`
(`InputEditor.swift`) could never fire. Digits and Return arrive as real
key presses, which is why everything else worked.

**The fix (one modifier in `InputEditor.swift`):** SwiftUI surfaces
`cancelOperation:` as the exit command —
`.onExitCommand(perform: model.pendingAmbiguity == nil ? nil : { model.cancelAmbiguity() })`
on the `TextEditor`. The handler is installed only while the picker is up,
so with no picker Esc keeps its default responder-chain behavior (e.g.
exiting full screen). The `.onKeyPress(.escape)` route stays as a harmless
fallback. No model changes; `cancelAmbiguity()` and its tests are untouched.
PROBLEMS.md inline-overlay entry updated with the lesson (new rule 4: Esc on
a focused text view is `cancelOperation:`, not a key press).

**Gate (fix round 3).** `make check` ✓ · `make test` **172/172** (model API
untouched, no new tests needed — this is key routing, unfalsifiable by unit
tests per PROBLEMS.md rule 2) · swiftui-pro sanity on `InputEditor` (review
led to the conditional-`nil` handler instead of an unconditional closure) ·
`make build` ✓ · launched `build/Casette.app` via `open`: alive, AppleScript
quit, no stray Casette/Sage processes. **On-screen Esc re-check (checklist
step (a) below) still needs a human/verifier pass — same caveat as every
key-routing fix.**

### Fix round 2 (2026-06-11) — ambiguity picker re-architected: popover → inline same-window overlay

Round 1's fix FAILED on-screen re-verification — and regressed the mouse
path. With the popover up: Esc/digits/Return all dead, a plain `z` swallowed
(keys reached NEITHER the popover NOR the field), and clicking a candidate
row no longer worked; only ⌘A+Delete (→ draft-didSet dismissal) passed.
**Root cause, deeper than round 1's diagnosis: a macOS SwiftUI `.popover` is
presented as its OWN KEY WINDOW.** The moment it appears the main window's
`TextEditor` loses first-responder status, so the round-1 `onKeyPress`
handlers on the editor never fire — and the popover side has no working key
routing of its own. There is no winning arrangement with `.popover`;
PROBLEMS.md entry rewritten with the full story.

**The round-2 fix changes the presentation architecture, not the model:**
- `.popover` is GONE. `AmbiguityPickerView` is now an inline suggestion
  panel (material, rounded, shadowed) rendered by a conditional
  `.overlay(alignment: .topLeading)` on `InputPaneView`, alignment-guided
  (`panel[.bottom] + gap`) to float directly above the pane, over the tape —
  same window, so the editor keeps keyboard focus the entire time and the
  round-1 key routing (Esc → `cancelAmbiguity`, Return → first candidate,
  digits 2–9 → nth, any edit → dismiss via `draft.didSet`) now actually
  fires. The ShellModel API from round 1 is unchanged.
- Candidate rows are plain `Button`s (`.plain` style, hover tint,
  `.contentShape(.rect)`) with NO `keyboardShortcut`s — the editor owns the
  keys; the panel owns only the mouse. No focusable controls in the panel,
  so it can never steal first responder; `InputPaneView.onChange` asserts
  editor focus on both panel show and dismissal.
- Appear/disappear is a plain structural conditional with no transition —
  instant (the verifier called the popover fade sluggish), and §1.1-safe
  (the rule is about *animated* insert/remove; same precedent as the
  kernel banner).
- Panel hints now read `↩ first   2–9 choose   esc keep editing` — exactly
  the behaviors the editor implements.

**Gate (fix round 2).** `make check` ✓ · `make test` **172/172** (no test
changes needed — the model API is untouched; the popover had no tests of its
own) · swiftui-pro review applied (`InputPaneView` dropped a now-unneeded
`@Bindable` — the popover's binding was its only use) · `make build` ✓ ·
launched `build/Casette.app` via `open`: Sage booted (worker pids visible),
alive 12s+, AppleScript quit → `pgrep -fl "Casette.app|sage -python|worker.py"`
clean.

**Re-verification checklist for the ambiguity panel (replaces step 7):**
type `solve x*y = 1` → Return → an inline panel appears INSTANTLY above the
input pane (not a detached popover) listing `solve(x*y == 1, x)` (hint ↩)
and `solve(x*y == 1, y)` (hint 2), footer `↩ first   2–9 choose   esc keep
editing`. Then, in order: (a) **Esc** → panel gone instantly, draft intact,
typing works immediately; (b) Return → panel; press **2** → evaluates the
y-reading → `[y == (1/x)]`, draft cleared, panel gone; (c) fresh
`solve x*y = 1` → Return → panel; **Return again** → evaluates the
x-reading (first candidate); (d) panel up → **click** the second candidate
row → it evaluates (mouse path restored); (e) panel up → **⌘A then Delete**
(or type any character, e.g. `z`) → the edit reaches the FIELD (text
visibly changes) and the panel dismisses with no stale candidates; a digit
pressed afterwards types normally. History steps (10) from round 1 stand
unchanged.

### Fix round (2026-06-11) — ambiguity-popover keyboard wiring + history-cursor reset

The on-screen verifier failed the gate on the ambiguity popover's keyboard
path (Esc didn't dismiss, digit 2 typed literal text, clearing the field left
stale candidates showing) plus two history caveats. Root cause: **a macOS
SwiftUI `.popover` is a passive overlay — keyboard focus stays in the
`TextEditor`, so the popover's `keyboardShortcut`s (Return/digits) never fire
and Esc goes to the text view.** Mouse clicks worked; every advertised key
was dead. (Full lesson in PROBLEMS.md.)

**The fix — the focused editor IS the picker's keyboard, and one "user
edited the draft" hook drives everything:**
- `ShellModel.draft` gained a `didSet`: any draft change that is NOT a
  history recall (an `@ObservationIgnored isRecallingHistory` flag set only
  by `setRecalledDraft`) dismisses a pending ambiguity (the candidates are
  stale) and ends history navigation (`InputHistory.endNavigation()` — the
  next Up starts at the newest entry, standard shell behavior). This is the
  blocking defect's "dismiss on edit" AND minor #1 in one model-level hook.
- New model API (testable, shared by both keyboard paths):
  `cancelAmbiguity()` (Esc: dismiss, draft kept) and
  `resolveAmbiguity(at:)` (Return = index 0, digits 2–9 = indices 1–8;
  out-of-range = no-op, picker stays).
- `InputEditor` routes the keys while `pendingAmbiguity != nil`: Esc →
  `cancelAmbiguity`, Return → `resolveAmbiguity(at: 0)`, digits 2–9 →
  `resolveAmbiguity(at: digit-1)` (out-of-range digits are swallowed so they
  can't silently edit the draft); with no picker up all three behave exactly
  as before. Focus restoration on dismissal was already wired
  (`InputPaneView.onChange`). The popover buttons keep their shortcuts as
  the backup path should its window ever become key — both paths call the
  same model methods, so hints and behavior can't diverge.
- **Minor #2 (multiline recall stranding) — fixed, semantics refined:**
  while history navigation is in progress, Up/Down KEEP navigating even when
  the recalled entry is multiline (you can't get stuck on `a = 5⏎a * 9`);
  the moment you edit, navigation ends and the arrows hand back to the
  cursor. macOS 14's `TextEditor` has no cursor introspection
  (`TextEditor(text:selection:)` is macOS 15+), so "Down only at the very
  end" wasn't buildable — this rule is the honest, coherent version: arrows
  navigate while you're flipping through history, edit to start editing.
  The nuance: to arrow-around INSIDE a recalled multiline entry you must
  edit (or click) first. The "Up at start of a fresh multiline draft" gap is
  unchanged (still documented, still not a behavior).

**Gate (fix round).** `make check` ✓ · `make test` **172/172** (163 + 9 new:
`InputHistory.endNavigation` reset/no-op; ShellModel esc-keeps-draft,
pick-by-index incl. out-of-range, edit-dismisses-picker,
recall-dismisses-picker, user-edit-resets-cursor-to-newest,
multiline-recall-keeps-navigating, edit-ends-multiline-navigation) ·
swiftui-pro re-review applied (Esc handler extracted to a method like the
other key handlers; logic stays on the model) · `make build` ✓ · launched
`build/Casette.app` via `open`: Sage booted (worker pids visible), alive
12s+, AppleScript quit → `pgrep -fl "sage -python|worker.py"` clean. (No V0
regression rerun — the kernel/worker were untouched this round.)

**The live-gate checklist below stands, with steps 7 and 10 SUPERSEDED by:**
- **7 (ambiguity, replaces the original):** type `solve x*y = 1` → Return →
  popover lists `solve(x*y == 1, x)` (hint ↩) and `solve(x*y == 1, y)`
  (hint 2). Press **Esc** → popover closes, draft intact, focus in the
  field, typing works immediately. Return again → popover; press **2** →
  evaluates the y-reading → `[y == (1/x)]`, draft cleared, popover gone.
  Fresh `solve x*y = 1` → Return → popover; press **Return** again →
  evaluates the x-reading (first candidate). Once more: popover up,
  **⌘A then Delete** (or type any character) → popover dismisses, no stale
  candidates over the field; a digit pressed afterwards types normally.
- **10 (history, replaces the original):** from a single-line draft press
  **Up** repeatedly — `factor x^8 - 1`, `factor x^6 - 1`, the multiline
  `a = 5⏎a * 9` (arrows now CONTINUE past it), … to the oldest; **Down**
  walks forward through everything — including past the multiline entry —
  and finally restores the draft you started from. Then: press Up twice
  (mid-list), **⌘A + Delete** to clear, press Up → it recalls the NEWEST
  entry (the cursor reset). Then: recall the multiline entry, type one
  character into it → Up/Down now move the cursor (editing ended
  navigation), as documented.

---

**The input pane is a calculator now, and the friendly compiler is wired in.**
Typing `factor x^4 - 1` shows the generated Sage live under the field, Return
evaluates it through the real kernel (with the `var('x')` prelude), errors
explain themselves inline without submitting, ambiguity offers its candidates,
Shift-Return makes the field multiline, ⌘-Return evaluates without advancing,
and Up/Down walk the session's submitted inputs with the customary
draft-preservation. Raw Sage still flows through untouched, exactly as V1.3.

**How the compiler was lifted.** `FriendlyCompiler` is now a second SwiftPM
**library target** (`Sources/FriendlyCompiler/`) the app target depends on. The
four library files (CompileResult / FriendlyCompiler / Scanner / Variables) and
the 69-test suite (`Tests/FriendlyCompilerTests/`) are **byte-identical** to
v0/07 (`cmp`-verified at lift time; v0/ untouched). The ONLY app-side addition
is one new file, `FriendlyCompiler+App.swift`, exposing the library's own
free-variable heuristic publicly — needed because a chosen `.ambiguous`
candidate string carries no `requiredVariables` of its own, and the preludes
must come from the same documented heuristic, not a re-implementation. The
lifted suite runs as part of `make test` (69/69).

**The compile boundary (`CompiledInput.compile`).**
- `.success` → `CompiledInput` origin `.friendly`: row records `input` = the
  raw text, `sage` = the generated Sage (the honest input-vs-sage split).
- `.bypass` → origin `.bypass`, raw == sage, untouched.
- `.error` / `.ambiguous` → never become a `CompiledInput`; they surface as
  `Outcome.error/.ambiguous` so the UI can refuse/ask without a row.
- **Multiline input bypasses BEFORE the compiler** — the V0.7 library was
  written for one line and *flattens newlines to spaces*, which would corrupt
  newline-sensitive raw Sage (new PROBLEMS.md entry). Friendly forms are
  single-line by definition, so this loses nothing.

**Prelude policy (FRIENDLY-COMPILER.md, frozen, implemented exactly).** On
submit, each `requiredVariable` is sent as its own `var('V')` eval ahead of the
generated Sage, through the same serial kernel queue (order proven by test).
Prelude results are discarded; the row's envelope is the MAIN eval's, so the
displayed result corresponds exactly to the displayed generated Sage, and
`SessionRow.sage` stays the single clean expression (preludes are session
plumbing — part of what's *sent*, never what's *shown*). Reality check baked
into an integration test: the worker predefines NO variables (not even `x` —
PROBLEMS.md V0.5 was right; FRIENDLY-COMPILER.md's "predefines only x" aside is
slightly optimistic), and the always-declare policy covers that for free:
`integral t^2, t=0..2` → `8/3` with `t` visibly appearing in the live Symbols.

**Keyboard semantics (V1.4 subset of the V1.12 contract).**
- **Return** → evaluate (submit, draft clears).
- **Shift-Return** → newline *at the cursor* (the key handler deliberately
  ignores it so the text view inserts it).
- **⌘-Return** → evaluate WITHOUT advancing — submits the row, keeps the draft
  in place for iteration. Carried discoverably on the Sage menu ("Evaluate
  Without Advancing", ⌘↩, claims the key equivalent app-wide) with an
  in-editor fallback. Ambiguity initiated from ⌘↩ keeps the draft after the
  candidate is chosen (`PendingAmbiguity.advances`).
- **Up/Down** → history in single-line mode (`InputHistory`: the session's
  submitted inputs, consecutive duplicates collapsed, in-progress draft
  stashed on first Up and restored when you come back down past the newest).
  In a multiline draft the arrows keep moving the cursor — cursor-position
  detection isn't available to SwiftUI key handlers, so "Up at start of
  multiline" recall is a documented gap, not a behavior.
- The input field is a `TextEditor` + invisible sizing-mirror `Text` (grows
  with newlines/wrap to a 140pt ceiling, then scrolls). Documented deviation
  from the swiftui-pro preference for `TextField(axis: .vertical)`: the field
  editor can't do Shift-Return-inserts-at-cursor, which is the V1.4 contract.

**Generated-Sage disclosure.** `ShellModel.draftPreview` recompiles the draft
per keystroke (pure, microseconds) into a `DraftPreview`; `DraftPreviewLine`
renders it under the field at a stable reserved height (no pane jitter):
`.generated` → `↳ factor(x^4 - 1)` (callout mono, selectable), `.rawSage` → a
quiet "raw Sage" tag, `.issue` → orange-triangle + message + mono `Try: …`
suggestion (the same line a refused submission points at), `.ambiguous` → "N
possible readings — return offers the choices". Position-aware highlighting
inside the editor is deferred (the messages already quote the offending
fragment, which is the cheap version).

**Ambiguity picker.** `.ambiguous` puts a `PendingAmbiguity` on the model; a
popover anchored to the input pane lists one button per candidate (mono),
keyboard-first: Return = first reading (`.defaultAction`), digits 2–9 = the
rest, Esc cancels (draft kept), and focus returns to the input on dismissal
either way. The chosen candidate evaluates as a friendly submission of the
original raw input (required variables re-derived via the library heuristic).

**Gate.** `make check` ✓ · `make test` **163/163** (= 94 CasetteTests + the 69
lifted FriendlyCompilerTests; new suites: CompiledInput compile boundary ·
InputHistory · ShellModel input semantics incl. prelude wire-order over the
fake transport, ⌘↩, inline-error-no-submit, ambiguity round-trip · **Friendly
compiler integration vs real Sage 9.5**: `factor x^4 - 1` → symbolic with the
right factors; `double integral x*y, x=0..1, y=0..x` → **1/8**; `integral t^2,
t=0..2` → 8/3 with `t` in live symbols (prelude proven); ambiguous solve →
chosen candidate → `[x == (1/y)]`; compile error never reaches Sage and raw
`factorial(5)` → 120 right after) · `make build` ✓ (bundled worker.py
`cmp`-identical) · launched `build/Casette.app` via `open`: Sage booted, alive
30s+, AppleScript quit → `pgrep -fl "sage -python|worker.py"` **clean**.
**Full V0 regression, all green:** V0.1 **18/18** · V0.2 **35/35** · V0.3
**97/97** · V0.5 **88/88** · V0.6 **24/24** · V0.7 **69/69 + e2e 19/19** ·
V0.8 **95/95** · V0.9 **32/32** · V0.10 **21/21**. `pgrep` clean after
everything.

**Skill reviews applied.**
- **swiftui-pro:** logic on the model (`submit/resolveAmbiguity/recall*` are
  plain testable methods; key handlers call them and only translate to
  `KeyPress.Result`); views one-type-per-file (`InputEditor`,
  `DraftPreviewLine`, `AmbiguityPickerView`); button actions as method
  references; no `Binding(get:set:)`; `Text.foregroundStyle` concatenation for
  the mixed-voice error line. Accepted deviation (documented in code):
  `TextEditor` over `TextField(axis:)` for the keyboard contract.
- **macos-design:** popover (not a sheet) for the transient choice, anchored
  to the control it answers; keycap affordances surfaced ("⏎ evaluate ⇧⏎
  newline" fades in with content, "esc to keep editing" in the picker, per-
  candidate ↩/digit hints); ⌘↩ lives on a real menu for discoverability;
  preview/issue states differ by icon + text, never color alone.
- **typography-designer:** the preview line keeps the frozen two-axis system —
  Sage content at callout+mono one step under the title3 input; issue prose at
  caption default-face; `Try: …` suggestions at caption+mono (example input is
  code). New `Theme.Fonts.inputPreviewSage/Issue/Suggestion`; weight untouched
  (emphasis via .secondary/.tertiary + icon).

**Known gaps (deliberate).**
- Up-at-start-of-multiline doesn't recall history (no cursor introspection in
  SwiftUI key handlers); arrows are cursor keys whenever the draft has a
  newline. ~~If a recalled entry is itself multiline, edit it single-line (or
  clear) to resume navigating.~~ *(Superseded by the fix round: while
  navigation is in progress the arrows keep navigating, multiline recalled
  entries included; any edit ends navigation.)*
- Compile-error `position` isn't rendered as an in-editor caret/highlight —
  messages quote the offending fragment instead.
- History is session-scoped and in-memory (persistence is V1.9's business);
  the History sidebar tab still lists rows independently.
- `SessionRow.sage` records the generated expression only (not preludes) —
  honest for display; V1.9's replay should recompile from `input` to
  regenerate preludes (note left for it).
- LaTeX/plots/tracebacks still render as in V1.3 (V1.5/V1.7 territory).

**Live gate (PENDING — on-screen verifier checklist).**
1. Launch `build/Casette.app`; wait for **"Sage ready"**. Focus is in the
   input. The pane shows the placeholder and an empty preview strip.
2. Type `factor x^4 - 1` (don't submit): a mono preview line appears under
   the field reading `↳ factor(x^4 - 1)`; the "⏎ evaluate ⇧⏎ newline" hint
   fades in. Press **Return** → row evaluates to `(x^2 + 1)*(x + 1)*(x - 1)`
   (factor order may differ); the draft clears; the preview line empties.
3. Type `2+2`: preview shows the quiet **"raw Sage"** tag. Return → **4**.
4. Type `double integral x*y, x=0..1, y=0..x`: preview shows
   `integrate(integrate(x*y, (y, 0, x)), (x, 0, 1))`. Return → **1/8**.
5. Type `integral t^2, t=0..2`: Return → **8/3**, and the Symbols tab now
   lists `t` (the `var('t')` prelude is real). Select the row → Inspector's
   Generated Sage shows `integrate(t^2, (t, 0, 2))` (NO `var(` plumbing).
6. **Inline error:** type `integral x^2, x=0..` → orange ⚠ line: "Range
   `x=0..` is incomplete — missing the upper bound after `..`.  Complete it,
   e.g. `x=0..1`." Press Return **repeatedly** → NO row appears, the text
   stays put. Fix it to `x=0..1` → the preview flips to
   `integrate(x^2, (x, 0, 1))`, Return → **1/3**.
7. **Ambiguity:** type `solve x*y = 1`, preview reads "2 possible readings…".
   Return → a popover lists `solve(x*y == 1, x)` (hint ↩) and
   `solve(x*y == 1, y)` (hint 2). Press **Esc** → popover closes, draft
   intact, focus back in the field. Return again, press **2** → evaluates the
   y-reading → `[y == (1/x)]`; draft cleared.
8. **Shift-Return:** type `a = 5`, press **⇧⏎** — a newline appears (the field
   grows; nothing submitted), type `a * 9`, preview tag reads "raw Sage".
   Return → row shows **45** (multiline raw Sage reached Sage intact). Add
   ~8 lines — the field stops growing (~6 lines) and scrolls internally.
9. **⌘-Return:** type `factor x^6 - 1`, press **⌘⏎** → a row evaluates BUT
   the draft text stays in the field. Edit `6`→`8`, ⌘⏎ again → second row,
   draft still there. The Sage menu shows "Evaluate Without Advancing ⌘↩".
10. **History:** from that (single-line) draft press **Up** repeatedly — it
    recalls `factor x^8 - 1`, `factor x^6 - 1`, the multiline `a = 5⏎a * 9`,
    … back through every submitted input; **Down** walks forward and finally
    restores the draft you started from. Type something fresh without
    submitting, press Up then Down — your fresh text comes back. (On a
    recalled MULTILINE entry the arrows move the cursor instead — that's the
    documented single-line rule, not a bug.)
11. Dark mode: preview line, orange issue line, and popover all legible.
12. Quit (⌘Q); `pgrep -fl "sage -python|worker.py"` → empty.

**Next.** V1.5 — result rendering v1 (LaTeX cards on the tape; the expanded
card shows Input + Generated Sage — the `CompiledInput` split feeds it
directly).

---

## 2026-06-11 — V1.3: Kernel integration — PASS (live gate PASSED, all 12 checks)

**Live gate (opus verifier, computer-use) — PASS, all 12 checks.** On screen:
boot → "Sage ready" in ~2–4s (worker pids confirmed via pgrep); `2 + 2`→4 with
full Inspector detail (54 ms duration); `1/3 + 1/5`→`8/15` + `≈ 0.5333333333`;
`x = 5` statement then `x + 1`→6 with Symbols showing `x · integer · 5`; `1/0`
→ readable red ZeroDivisionError and status returns to ready; matrix renders +
Actions lists det/rank/rref/…; **interrupt**: `sleep(30)` spinner → ⌘. →
orange KeyboardInterrupt in ~2s, same worker pids survive, `1 + 1`→2;
**restart** ⌘⇧R: Symbols empties, new pids, `x`→NameError, `2*3`→6;
**crash**: `kill -9` the worker → yellow "Sage stopped unexpectedly" banner →
Restart button recovers, `7*7`→49; dark mode legible across
result/error/interrupted rows; worker log has session headers with matching
pids; ⌘Q → `pgrep -fl "sage -python|worker.py"` EMPTY (no orphans).
**Non-blocking polish:** Actions-tab preview footnote truncates at panel
width (wrap it); first click on a sidebar tab occasionally needs a second
click (possible focus/timing artifact — watch in V1.6).

**The app now actually talks to Sage.** Typing raw Sage and pressing Return
boots, evaluates, persists state across evals, renders real envelopes on the
tape, refreshes the live Symbols sidebar, survives crashes visibly, and
restarts intentionally — all proven by 64 swift-testing tests including three
end-to-end suites against real Sage 9.5, plus a real `.app` launch/quit with
zero orphaned workers. **On-screen verification is still pending** (checklist
at the end of this entry).

**Architecture (what got built).**
- **`SageKernel`** (`Sources/Casette/Kernel/`) — the process wrapper, unifying
  v0/09's proven `WorkerProcess` + `LineReader` into one type. `posix_spawn`
  with `POSIX_SPAWN_SETSID` (own process group → orphan-free `killpg`) **plus
  `POSIX_SPAWN_SETSIGDEF`/`SETSIGMASK`** (see the new PROBLEMS.md entry — the
  one genuine new trap this phase). Banner-pid capture (`noteRealPID`) for
  SIGINT targeting; a dedicated reader thread drains stdout into a
  **`WireQueue`** (the extracted, unit-tested JSONL framing + single-consumer
  queue both the real kernel and the test fake share); child stderr appends to
  `~/Library/Application Support/Casette/logs/sage-worker.log` (session header
  per spawn; `KernelLog`) instead of /dev/null, so "why did Sage die?" has an
  answer. Every kernel registers with **`KernelReaper`**;
  `applicationWillTerminate` group-kills anything left, so quitting Casette
  never leaks a worker (proven live: launch → worker up → quit → `pgrep` clean).
- **`SessionController`** — an **actor** (all kernel I/O off the main actor),
  the Swift port of v0/02's `controller.py`. Eight-state machine surfaced
  through `KernelState`; request/response **routing by ID** over the wire
  queue (strays dropped, the single-consumer rule held by actor
  serialization); eval **timeout with SIGINT → hard-kill escalation** (poll +
  `Task.sleep` loop, never a blocking wait, so `interruptCurrent()`/
  `restart()` land mid-eval); **generation counter** guards every loop and the
  EOF callback (the V0.2 restart-race lesson, in Swift); boot awaits the ready
  banner and **hard-kills before reporting** a hang (the V0.9 lesson). Worker
  death is event-driven (EOF callback → `.crashed` even while idle). State +
  honest issue text stream to the UI over one `AsyncStream<KernelStatus>`.
  Transports come from an injected **factory** (one fresh transport per
  generation); the default factory does V0.9 discovery (stored
  `sage-doctor.json` → Homebrew → /usr/local → `SageMath*.app` glob → conda →
  PATH; `SageDiscovery`/`SageConfigStore` lifted verbatim from v0/09) and
  locates the bundled worker (`WorkerScriptLocator`, with a loud-failing
  `CASETTE_WORKER_PATH` override for tests/dev).
- **State-machine policy decisions:** SIGINT-honored timeout → `.timedOut`
  (worker survived, `canAcceptWork`); escalated hard kill → **`.crashed`**
  with an issue explaining the force-stop (honest: the worker is GONE, and
  the recovery banner offers Restart — V0.2 left this state ambiguous).
  Outcomes the worker never produced (crash, force-stop, kernel-unavailable)
  get **synthetic error envelopes** parent-side so rows stay readable and
  self-describing when persisted (`Evaluation.result` is never nil in
  practice). Refused evals (no kernel) are explicit error rows, not
  forever-pending spinners.
- **UI wiring.** `ShellModel.connectKernel()` attaches the controller, watches
  the status stream (`kernelState` + `kernelIssue`), and submits through a
  **chained task queue** so rapid submissions evaluate strictly in tape order
  against the one namespace (restart/interrupt are deliberately NOT chained —
  they're the escape hatches). Submit → pending row (the legitimate spinner!)
  → `complete(rowID:with:)` via the frozen `EnvelopeMapping` → real
  plain/`≈ approx`/error rendering (V1.2's tape needed zero changes). After
  every eval the **real `symbols` op** refreshes the sidebar (it was cheap —
  ~1ms — so V1.6's data is live early; `SymbolSnapshot(workerResponse:)`).
  Kernel state is visible in a small dot+label **status indicator** in the
  input pane (text differs per state, not color-only; tooltip carries the
  machine state); kernel problems render as a **banner** above the input pane
  with the message + a Restart Sage button; a new **Sage menu** carries
  Interrupt Evaluation (⌘.) and Restart Sage (⌘⇧R), enabled honestly.
  `RootView` starts with an EMPTY session (placeholder seeding removed — the
  tape is real now; `PlaceholderData` survives for previews/tests).
- **worker.py bundling:** `build.sh` copies `v0/01-worker-protocol/worker.py`
  (the canonical worker, untouched) into `Casette.app/Contents/Resources/`
  at assembly — byte-identical by construction (verified with `cmp` at the
  gate), single source of truth, no fork.

**Gate.** `make check` ✓ · `make test` **64/64** (suites: WireQueue framing ·
SessionController state machine/routing/escalation over a scripted
`FakeKernelTransport` · ShellModel kernel wiring incl. strict eval ordering ·
kernel setup (loud override failure, discovery priority) · the V1.2 suites
unchanged · **SageKernel integration vs real Sage 9.5**: full journey
(boot → `2+2` → `1/3+1/5` exact+approx → `x=5`→`x+1`→`6` → `1/0`
ZeroDivisionError → live symbols → interrupt honored → worker survives →
restart → `NameError` → clean shutdown), timeout-honored → `.timedOut`, and
the SIG_IGN runaway hard-kill + recovery) · `make build` ✓ with **bundled
worker.py byte-identical** ✓ · launched `build/Casette.app` via `open`: alive
12s+ with wrapper+worker visible, quit via AppleScript → **zero stray
processes** ✓. **Full V0 regression, all green:** V0.1 **18/18** · V0.2
**35/35** · V0.3 **97/97** · V0.5 **88/88** · V0.6 **24/24** · V0.7 **69/69 +
e2e 19/19** · V0.8 **95/95** · V0.9 **32/32 + live doctor run all-ok** · V0.10
**21/21 + casette-tape 22/22**. `pgrep -fl "sage -python|worker.py"` clean
after everything.

**Learned / surprised (the headline → PROBLEMS.md).**
- **`posix_spawn` children inherit the parent's signal dispositions/mask** —
  under the swift-testing runner the worker started with SIGINT ignored, so
  cysignals never fired and every interrupt escalated to a hard kill, while
  the identical v0/09 code passed from its CLI parent. Fix:
  `POSIX_SPAWN_SETSIGDEF` + `POSIX_SPAWN_SETSIGMASK` at spawn. The v0/09
  proof was right; its *parent context* was an untested variable.
- The blocking `NSCondition` waits in v0/09's `WorkerProcess` could not move
  into an actor (a blocked actor can't receive `interrupt()`/`restart()`).
  The poll + `Task.sleep` slice loop — controller.py's exact shape — is what
  keeps the actor responsive without violating the single-consumer rule.
- `AsyncStream` buffers values yielded before iteration starts (unbounded
  default), so the status stream can be consumed late without losing the
  boot transitions.

**Skill reviews applied.**
- **swiftui-pro:** modern concurrency throughout (actor + `AsyncStream`, no
  GCD, `Task.sleep(for:)`); `@ObservationIgnored` on the model's task
  handles; `[weak self]` + per-iteration strong capture in the status loop;
  logic lives on the model/controller (testable), not in `body`/`task`
  closures; direct `action:` parameters where possible. Accepted, documented
  deviation: `SageKernel`/`WireQueue`/`KernelReaper` are lock-guarded
  `@unchecked Sendable` classes — the proven reader-thread pattern from
  v0/09; an actor cannot own a blocking `read()` loop.
- **macos-design:** ⌘. for interrupt (the system cancel convention) and ⌘⇧R
  in a proper app menu (discoverable, honestly disabled); status indicator
  differs by text, never color alone; the recovery banner is an Xcode-style
  tinted strip with the single relevant action; no new chrome. Banner
  insert/remove is deliberately NOT animated (SWIFTUI-RULES §1.1 trumps the
  every-state-change-animates guidance).
- **typography-designer:** not run — no new type styles; the status/banner
  reuse `Theme.Fonts.meta` per the existing two-axis scale.

**Known gaps (deliberate, per plan).**
- Friendly compiler not wired (V1.4): everything is `CompiledInput.bypass`,
  so `factor x^4 - 1` evaluates as literal (broken) Sage — type raw Sage.
- LaTeX renders as plain text (V1.5); plots show the placeholder box, not the
  PNG (V1.7) — the artifacts ARE saved and the envelope carries them.
- Tracebacks not yet behind a disclosure (V1.5) — Inspector shows error type.
- No ⌘./⌘⇧R *keyboard pass* polish or per-request numeric/precision flags
  (V1.8) — the controller API has room for them (eval request dict).
- Eval timeout is 120s (constant in `SessionController.Configuration`); no
  user-facing setting yet.

**Live gate (PENDING — on-screen verifier checklist).**
1. Launch `build/Casette.app`. Status indicator (bottom-right of input pane)
   reads "Starting Sage…" then **"Sage ready"** (green dot) within ~15s.
   Everything V1.1/V1.2 verified should still hold (layout, ⌘B, focus,
   selection → Inspector/Actions, dark mode).
2. Type `2 + 2` ⏎ → row may flash "Evaluating…" + spinner, then shows **4**.
   Inspector for the row shows Kind integer, Duration, Generated Sage.
3. `1/3 + 1/5` ⏎ → **8/15** with secondary line **≈ 0.5333333333**.
4. `x = 5` ⏎ (statement → input echo only, no result line), then `x + 1` ⏎ →
   **6** (state persists). Symbols tab now lists `x · integer · 5` (live!).
5. `1/0` ⏎ → red **ZeroDivisionError** row, "rational division by zero";
   status indicator back to "Sage ready" (the worker survived).
6. `matrix([[1,2],[3,4]])` ⏎ → multi-line plain matrix text; Actions tab for
   it lists det/rank/rref/… (labels only).
7. **Interrupt:** type `sleep(30)` ⏎ (or `while True: pass`), watch status
   read "Working…", then **Sage ▸ Interrupt Evaluation (⌘.)** → the row turns
   orange "Interrupted" within ~1s and "Sage ready" returns. Then `1 + 1` ⏎ →
   2 (worker survived).
8. **Restart:** **Sage ▸ Restart Sage (⌘⇧R)** → status flicks "Starting
   Sage…" then ready; Symbols tab EMPTIES; `x` ⏎ → red **NameError** (the
   reset is intentional and visible).
9. **Crash visibility:** in Terminal,
   `pgrep -fl worker.py` → `kill -9 <python3 worker pid>` → within ~a second
   the yellow banner appears: "Sage stopped unexpectedly. Restart Sage to
   continue (variables will be reset)." with a **Restart Sage** button; the
   status dot reads "Sage stopped" (red). Click Restart Sage → ready again,
   evals work.
10. Quit (⌘Q). In Terminal: `pgrep -fl "sage -python|worker.py"` → **no
    output** (no orphaned workers — the reaper did its job).
11. Worker log exists and has session headers:
    `cat ~/Library/Application\ Support/Casette/logs/sage-worker.log`.

**Next.** V1.4 — input pane v1: wire the real `FriendlyCompiler` (v0/07) in
front of `CompiledInput`, multiline/history/⌘-Return input behaviors, and the
generated-Sage disclosure.

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
