## SwiftMath in a LIVE tape: memoize normalize+parse, and guard every `MTMathUILabel` property write — `sizeThatFits` runs each layout pass and the `latex` setter re-typesets

**The trap (V1.5).** Dropping the proven V0.4 renderer into the real session
tape changes the workload: v0/04 rendered a static list once; the app's
`LazyVStack` recycles rows while scrolling, and EVERY hover/selection change
re-evaluates row bodies. Two costs that were invisible in the proof app
multiply:

1. **The per-string work re-runs per body evaluation.** `SageLatexNormalizer`
   (four `NSRegularExpression` passes) + the `MTMathListBuilder` parse-check
   ran inside `render(...)` — so hovering a row re-normalized and re-parsed
   every visible LaTeX string on the main thread. Fix: `MathRenderCache`, a
   `@MainActor` memo keyed by the raw envelope `latex` holding
   `(normalized, parses)`. Bounded (1024, whole-cache reset on overflow — a
   self-patching cache is its own bug class, SWIFTUI-RULES §3.2).
2. **`NSViewRepresentable.sizeThatFits` + `updateNSView` run every layout
   pass, and `MTMathUILabel.latex`'s setter re-parses + re-typesets
   unconditionally** (so do `fontSize`/`labelMode`). Configure must be
   write-guarded (`if label.latex != latex { label.latex = latex }`), or
   scrolling typesets the same math over and over.

Typesetting itself stays main-thread — `MTMathUILabel` is an NSView and
SwiftMath's native Core Text typeset is fast; what hitches a tape is the
*repeated* work, not the first render. (If a future giant expression is ever
slow, render once to an image off the label — don't move the NSView off main.)

**Corollary — the card-level fallback should be `plain`, not the raw LaTeX.**
The V0.4 renderer contract degrades malformed LaTeX to its raw source (right
for a rendering proof). In a result card the user wants the VALUE: the worker
always provides `plain`, which is strictly more readable than broken LaTeX
source. So cards pre-check with `MathContent.choose(latex:)` (same memoized
parse) and fall back to monospaced `plain`; the renderer's raw-source fallback
remains only as the backstop for direct `MathView` callers.

---
