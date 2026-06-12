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
