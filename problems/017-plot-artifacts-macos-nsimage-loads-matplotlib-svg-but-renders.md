## Plot artifacts: macOS `NSImage` loads matplotlib SVG but renders it as a black blob — use PNG

**The trap (V0.5).** Sage 9.5 saves a 2D plot to **SVG, PNG, and PDF** cleanly
(all three verified: SVG ~20 KB, PNG ~19 KB, PDF ~7 KB, valid headers). The
worker saves SVG+PNG. On the macOS render side, the obvious win is SVG (vector,
crisp at any zoom) — and `NSImage(contentsOf:)` **does** load these SVGs: it
returns a non-nil image with a sane size (`453×337`) via the system
`_NSSVGImageRep`. Looks like SVG "just works."

**It does not.** On screen, the SVG renders the **curve correctly** but paints a
**large opaque black blob** (shaped like the digits of the axis labels) over the
plot. Cause: matplotlib emits text (tick labels, axis numbers) as `<use>`
references to glyph `<path>`s defined in `<defs>`. The system `_NSSVGImageRep`
mishandles that pattern and fills the whole glyph-def region black instead of
placing individual glyphs. Verified on screen and at zoom — the blob is
unmistakable, and identical across rows. **Not a crash** (the app renders what
NSImage hands back), just wrong.

**PNG is flawless.** `NSBitmapImageRep` decodes the matplotlib PNG perfectly —
clean antialiased curve, readable axis labels, crisp at row size and zoomed.

**Rules.**
1. **Render PNG, not SVG, on this stack.** The worker saves both; the UI should
   default to PNG. Keep the SVG file for later (export, vector zoom) but only
   render it through a *real* SVG engine (a third-party SwiftUI SVG renderer, or
   rasterize via WebKit / `librsvg`), never bare `NSImage`.
2. **`NSImage` loading an SVG without returning nil is NOT proof it renders
   right.** It silently produces a wrong raster. The only check that catches this
   is the on-screen one (SWIFTUI-RULES §9 again: a passing load is not a passing
   render). Build the proof viewer with a per-row SVG/PNG toggle so the
   corruption is visible side-by-side.
3. **Saved-but-wrong vs failed-to-save are different.** Our save path treats a
   `.save()` exception as a structured per-format artifact error; but a format
   that *saves fine and renders wrong* (SVG here) passes every file-level
   assertion (exists, nonempty, parses as SVG) — only the eyeball test fails it.

**Headless `.show()`.** In a worker there is no display. `Graphics.show()` under
Sage's TkAgg backend didn't pop a window here, but relying on that is fragile —
wrap `Graphics.show` / `GraphicsArray.show` to **capture the plot as an
artifact** instead. Bonus: it's the clean way to get *multiple* plots out of one
eval (`p.show(); q.show()`), since the REPL echo only returns the last
expression.

**`from sage.all import *` does NOT predefine `x`.** The interactive Sage REPL
injects `x` (and friends) as a symbolic var; a bare star-import into the worker's
namespace does not. `plot(sin(x), …)` in the worker raises
`NameError: name 'x' is not defined` unless the caller did `x = var('x')` first.
(Already noted in WORKER-PROTOCOL; it bit the V0.5 harness until it declared
`x, y, t = var('x y t')`.)

---
