## AttributeGraph spin: an NSView write that self-invalidates DURING a SwiftUI graph update = an infinite update loop — 100% CPU, frozen app, no crash

**The symptom (V1.7 live gate, three occurrences).** The main thread wedged
at a sustained 100% CPU with the UI completely frozen — during plot-image
context-menu tracking (twice: after Copy Image, and after a failed Save
panel) and when a SELECTED plot row updated/scrolled. No crash, no log —
the app just stops responding while one core burns. The kind of bug only
live use finds: 231/231 unit tests green before and after.

**Diagnosis is `sample(1)`, nothing else.** `sample <pid> 5 1` (traces kept
at `/tmp/casette-*-hang.sample.txt`) showed ~100% of samples inside ONE
runloop observer callout: `NSHostingView.beginTransaction` →
`ViewGraphRootValueUpdater.updateGraph` → … → representable
`updateNSView` → AppKit invalidation (`NSCell setFont` →
`_invalidateEffectiveFont` → `invalidateIntrinsicContentSize` →
`_invalidateIntrinsicContentSizeDirtyingConstraints`) — over and over, the
graph update never converging. During context-menu tracking the wedge is
inescapable: the menu's own nested event loop runs the same runloop
observer, so the spin continues with the menu up and no event can ever
dismiss it.

**The mechanism.** SwiftUI flushes view-graph updates from a runloop
observer. If, INSIDE that flush, anything invalidates an AppKit-hosted
view's layout metrics (intrinsic content size, constraints, font), AppKit
marks layout dirty, which enqueues ANOTHER graph update on the same
observer — and if the next pass performs the same write, the loop closes
and never converges. Two co-conspirators produced it here, and BOTH must be
fixed (either alone keeps the loop reachable):

1. **Unguarded NSView property writes in `updateNSView`/`sizeThatFits`.**
   `MTMathUILabel`'s setters (`fontSize`, `labelMode`, `textAlignment`,
   `latex`) unconditionally `invalidateIntrinsicContentSize()` +
   `setNeedsLayout()`, and `textColor` rebuilds attributed strings (the
   `NSCell setFont` frames in the trace). A measurement pass that writes to
   the LIVE label — or an update pass that re-assigns an unchanged value —
   is a self-invalidation inside the graph update. (V1.5 had guarded
   `latex` for *performance*; the remaining unguarded writes were the
   correctness bug.)
2. **Intrinsic-size negotiation on plot images.**
   `Image(nsImage:).resizable().scaledToFit()` + `frame(maxWidth:maxHeight:)`
   makes the displayed size an outcome of per-pass NEGOTIATION between the
   image's intrinsic size and the row's proposal — inside a tape row that
   also hosts AppKit-backed views (the math label, `.textSelection`'s
   NSTextField-backed `SelectionOverlay`, visible in the traces), each
   renegotiation feeds the next pass's proposals and the loop has fuel.

**The structural fixes (`SwiftMathRenderer.swift`, `PlotImageWell.swift`).**
- `sizeThatFits` is PURE: it never touches the hosted label. Measurement
  goes through `MathMeasurementCache`, an offscreen never-hosted
  `MTMathUILabel` (its self-invalidations are inert) behind a bounded memo.
- EVERY property write in `configure` is change-guarded
  (`if label.fontSize != fontSize { … }` etc.) — a no-op update pass must
  perform ZERO writes.
- The plot image's displayed size is COMPUTED ONCE from the decoded
  raster's dimensions (`PlotImageWell.fittedDisplaySize`, pure + unit
  tested: fit into measured-available-width × `Theme.plotMaxHeight`,
  aspect-preserving, never upscale) and applied as an explicit
  `.frame(width:height:)` — the image proposes nothing and renegotiates
  nothing. The available width is measured via `onGeometryChange` off the
  well's full-width container, whose width comes from the PARENT (so the
  feedback can't oscillate).

**The invariant (header-documented in SwiftMathRenderer.swift):** no
`NSViewRepresentable` in a tape row may write to its own NSView during
measurement, and every write during `updateNSView` must be a REAL change —
a view whose size depends on a value it invalidates is an infinite loop.
Corollary for hybrid rows: anything AppKit-backed that sits near
self-sizing SwiftUI content should have its size made explicit, not
negotiated.

**Rules.**
1. When the app freezes at 100% CPU with no crash, `sample` the pid FIRST.
   One repeated runloop-observer stack = an AttributeGraph spin; read the
   deepest `updateNSView`/invalidation frames for the culprit view.
2. In ANY `NSViewRepresentable`: guard every property write in
   `updateNSView` (`if view.x != x`), and never write to the hosted view
   from `sizeThatFits` — measure on an offscreen instance.
3. Don't let images inside complex rows negotiate their size per pass —
   compute the fitted size from the bitmap's dimensions and set an explicit
   frame.
4. A context-menu-tracking hang is still this bug: menu tracking runs a
   nested event loop that services the same runloop observers.

---
