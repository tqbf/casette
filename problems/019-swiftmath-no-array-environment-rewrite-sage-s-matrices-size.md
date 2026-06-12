## SwiftMath: no `array` environment; rewrite Sage's matrices; size the NSView or it overlaps

**Trap 1 — `array`.** SwiftMath (`MTMathListBuilder`) supports `matrix`, `pmatrix`,
`bmatrix`, `Bmatrix`, `vmatrix`, `Vmatrix`, `smallmatrix`, `cases`, `aligned`, … —
but **NOT `array`**. Sage emits *every* matrix as
`\left(\begin{array}{rr}…\end{array}\right)`, which SwiftMath rejects ("Unknown
environment array"). Fix at the normalization boundary: map the wrapping delimiter
to the matching matrix env and drop the `{rr}` column spec and the `\left…\right`
wrapper — `\left(…array…\right)` → `\begin{pmatrix}…\end{pmatrix}`, `[`→bmatrix,
`|`→vmatrix. Cell body (`&`, `\\`) is unchanged. (Verified on screen: Sage's
`(1 2 / 3 4)` renders with parentheses after the rewrite.)

**Trap 2 — sizing (CORRECTED in the V1.5 fix round; the V0.4 advice was wrong
on macOS).** `MTMathUILabel` is an `NSView`. Dropped into a SwiftUI layout
naively, it reports no useful size and **collapses**, so tall glyphs
(∫, ∑, matrices, fractions) overlap or clip. Fix: in the
`NSViewRepresentable`, implement `sizeThatFits(_:nsView:context:)` and return
**`MTMathUILabel.fittingSize`** plus a few points of vertical margin.

**Do NOT use `intrinsicContentSize` (the original V0.4 advice): SwiftMath
overrides it on iOS ONLY.** On macOS the property falls through to NSView's
no-intrinsic sentinel **(-1, -1)**, so the V0.4/V1.5 wrapper silently sized
every math view **0pt wide × (fontSize+6)pt tall**. The v0/04 proof — and
single-line math in the app — *looked* right anyway because the NSView drew
outside its zero-size frame unclipped; the live gate exposed it the moment a
hero sat inside a clipping `ScrollView`: `8/15` squeezed below the input
echo, a matrix's bottom row cut off, the Inspector preview showing one paren.
The macOS accessor for "the rendered math size" is `fittingSize` (both call
the same internal `_sizeThatFits`). Locked in by `SwiftMathSizingTests`,
which will fail loudly if a SwiftMath bump moves these overrides. **Rule: an
NSView "working" in a non-clipping layout proves nothing about its reported
size — assert the representable's returned size, not the pixels.**

**Win — dark mode is free.** Set `label.textColor = .labelColor` (a *dynamic*
semantic `NSColor`). It re-tints the math to white in dark mode automatically; no
`colorScheme` plumbing needed. Verified on screen.

**Graceful fallback.** Pre-validate with
`MTMathListBuilder.build(fromString:error:)`; if `error != nil`, render the raw
LaTeX as plain text instead of a broken/empty label. (Set
`displayErrorInline = false` so SwiftMath doesn't draw its own red error string.)

---
