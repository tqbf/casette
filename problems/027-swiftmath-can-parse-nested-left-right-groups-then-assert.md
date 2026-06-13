## SwiftMath can parse nested `\left...\right` groups, then assert during layout

`MTMathListBuilder.build(fromString:error:)` is not a sufficient safety check.
Some LaTeX shapes parse successfully but crash later when `MTMathUILabel` asks
`MTTypesetter` for spacing during `fittingSize`.

Crash signature:

- main-thread `EXC_BREAKPOINT`
- `MTTypesetter.getInterElementSpace(_:right:)`
- `MTTypesetter.makeLeftRight(_:)` appears more than once in the stack
- SwiftUI is measuring an `NSViewRepresentable`

The known bad family is nested delimiter groups such as:

```text
\left[\left(1,\,-2,\,1\right)\right]
\left\{\left(x + 1\right),\,2\right\}
```

SwiftMath may accept these at parse time, then assert on an invalid spacing
pair while laying out the nested `inner` atoms. Swift assertions are not
recoverable with `do`/`catch`, so the app must not hand these strings to
`MTMathUILabel` at all.

Fix at the renderer preflight boundary: normalize Sage LaTeX first, then detect
a `\left` token before its containing `\right` has closed. Mark that entry as
not renderable so result cards use the existing plain-text fallback. Sequential
groups such as `\left(x\right) + \left(y\right)` remain allowed, and Sage
matrices are safe because normalization rewrites their outer `\left...\right`
array form into `pmatrix`/`bmatrix` before the nested-group scan.

Do not try to solve this inside `SwiftMathLabel.sizeThatFits`: by then the
assertion has already crossed into SwiftMath layout code.

---
