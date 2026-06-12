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
