# V0.4 — LaTeX Rendering in SwiftUI

A standalone SwiftPM app (its own `Package.swift`, executable target
`CasetteLatexProof`) proving the macOS UI can render the worker envelope's
`latex` field beautifully and reliably. Deliberately **not** entangled with the
main Casette app — that integration is V1.5.

## Run

```bash
# from this directory
swift run                       # builds + launches the window
# or, as a real .app bundle (Dock identity, frontable window):
./bundle.sh debug && open build/CasetteLatexProof.app
```

`bundle.sh` wraps the SwiftPM binary in a minimal `.app` (Info.plist, ad-hoc
codesign) and copies the engines' resource bundles (SwiftMath's math fonts,
etc.) into `Contents/Resources`.

## What it shows

A scrolling list (59 rows) of math results, each a card with: the source
(input), a kind chip, the rendered math (the hero), and a plain-text fallback.

- **All five spec test snippets** (`\int_0^1 x^2\,dx`, `\begin{bmatrix}…`,
  `\frac{\partial^2 f}{\partial x \partial y}`, `\sum_{n=0}^{\infty}…`,
  `\left\{x \in \mathbb{R} : x^2 < 2\right\}`).
- **Real worker LaTeX** captured live from the canonical V0.1 worker (Sage 9.5):
  `\frac{8}{15}`, Sage's `\left(\begin{array}{rr}…\right)` matrices, a long
  symbolic `expand((x+1)^8)`, the solve list, complex `4i+3`, the 50-digit √2,
  and more.
- **Inline** and **block** math.
- A deliberately **invalid LaTeX** row → graceful red plain-text fallback (no
  crash).
- 40 **bulk** rows for scrolling.
- An in-app **System / Light / Dark** appearance toggle.
- Per-row **Copy LaTeX** (hover button + right-click context menu) and Copy plain.

## Engine

**SwiftMath** (native Core Text, fully offline) behind a `MathRenderer`
abstraction. The product decision named **Textual**, and the first fallback was
**LaTeXSwiftUI** (MathJax) — both fell short. The full story, the verdict, the
abstraction, and the V1.5 recommendation are in
[`plans/MATH-RENDERING.md`](../../plans/MATH-RENDERING.md). The hard-won
rendering traps are in [`PROBLEMS.md`](../../PROBLEMS.md).

## Exit criteria — all verified ON SCREEN (computer-use)

| Criterion | Result |
| --- | --- |
| Inline math | PASS — rendered within a sentence (baseline alignment is the one polish item) |
| Block math | PASS — all five spec snippets render crisply |
| Matrices | PASS — bmatrix + Sage's `array` form (rewritten to `pmatrix`) |
| Dark mode | PASS — math re-tints white via semantic `NSColor.labelColor`, fully legible |
| Scrolling | PASS — 59 lazy rows scroll smoothly |
| Failed LaTeX → fallback | PASS — raw source shown in red, no crash |
| Copy LaTeX | PASS — verified via `pbpaste` and `read_clipboard` |
