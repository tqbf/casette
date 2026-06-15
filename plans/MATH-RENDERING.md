# Math Rendering — Engine Choice, the `MathRenderer` Abstraction, and the V1.5 Recommendation

The V0.4 deliverable: prove the macOS UI can render the worker envelope's `latex`
field beautifully and reliably. Proof app: `v0/04-latex-rendering/` (standalone
SwiftPM, executable `CasetteLatexProof`). This doc records what we chose, why, the
abstraction that survives into V1, and the traps found (the loud ones also live in
PROBLEMS.md).

---

## TL;DR

- **Textual verdict: NOT viable.** The product decision named "Textual." After
  genuine research there are two packages by that name; neither fits. The IRC
  client (`Codeux-Software/Textual`) is irrelevant. The SwiftUI rich-text engine
  (`gonzalezreal/textual`, the one almost certainly meant) is **disqualified**:
  its platform floor is **macOS 15** (we need 14), and its math is markdown-only
  (`$…$` inside `StructuredText`) via an immature 26-star engine
  (`gonzalezreal/swiftui-math`, v0.1.0) with no standalone LaTeX-string API and no
  `array` support. We did **not** silently substitute — we kept the
  `MathRenderer` abstraction the spec asked for and documented this gap.
- **First fallback chosen: LaTeXSwiftUI (MathJax). Also fell short here.** On
  screen, in this environment, MathJaxSwift 3.5.0 (the JavaScriptCore-bundled
  MathJax under LaTeXSwiftUI 2.0.0) **failed every braced sub/superscript** —
  `\sum_{n=0}^{\infty}`, `\int_{0}^{1}`, `x^{8}` — with "Extra open brace or
  missing close brace". It rendered single-char scripts (`\int_0^1`) and Sage's
  `array` matrices fine, but braced scripts are unavoidable in real worker output
  (Sage emits `x^{8}`, `_{n=0}`), so it could not carry the spec.
- **Engine shipped: SwiftMath (native Core Text, offline).** It renders **every**
  spec case and every real worker case correctly and beautifully — integrals,
  braced-limit sums, partial-derivative fractions, bmatrix, set-builder with
  `\mathbb` and `\left\{…\right\}`, the long polynomial, the relation, the complex
  literal, the 50-digit real. Its one gap is the `array` environment, which Sage
  uses for matrices; we rewrite `\left(\begin{array}{…}…\right)` → `\begin{pmatrix}`
  at the normalization boundary. No JS bridge, fast, fully offline.
- The swap from LaTeXSwiftUI to SwiftMath was **one line** (`activeMathRenderer`)
  plus a renderer file — **zero app-code changes**. That is the abstraction
  earning its keep, exactly the scenario the spec anticipated.

---

## The `MathRenderer` abstraction (the surviving artifact)

File: `v0/04-latex-rendering/Sources/CasetteLatexProof/MathRenderer.swift`. It
migrates into the real app at V1.5.

```swift
@MainActor protocol MathRenderer {
    associatedtype Body: View
    nonisolated var engineName: String { get }
    @ViewBuilder func render(_ latex: String, displayStyle: MathDisplayStyle) -> Body
}
```

- The app **never** imports a math library directly. Views place a `MathView`,
  which calls `activeMathRenderer.render(...)`. Swap the engine by changing the one
  `let activeMathRenderer = …` line.
- Two concrete renderers ship in the file: `SwiftMathRenderer` (**active**) and
  `LaTeXSwiftUIRenderer` (a documented, working-but-not-default alternative that
  proves the seam is real and keeps the MathJax path on record).
- **Graceful degradation is the renderer's responsibility**, per the contract.
  SwiftMath pre-validates with `MTMathListBuilder.build(fromString:error:)`; on a
  parse error it renders the raw LaTeX as red plain text (no crash, no vanish) —
  the spec's required degraded output.
- **Normalization lives behind the abstraction** (`SageLatexNormalizer`), so app
  code never sees engine quirks. The load-bearing transform is Sage `array` →
  `pmatrix`/`bmatrix`/`vmatrix` (SwiftMath has no `array`). There's also a
  per-engine entry point (`normalizeForSwiftMath` vs `normalizeForLaTeXSwiftUI`).

`MathDisplayStyle` is `.block` (hero, centered, full size) or `.inline` (woven
into a sentence). The renderer maps it to the engine's display/text mode.

---

## Engine comparison (measured on screen, macOS 14 floor, Sage 9.5 output)

| Capability | SwiftMath 1.7.3 (shipped) | LaTeXSwiftUI 2.0.0 / MathJaxSwift 3.5.0 | Textual (`gonzalezreal/textual`) |
| --- | --- | --- | --- |
| macOS 14 floor | ✅ (floor 12) | ✅ (floor 12) | ❌ floor **15** |
| Fully offline | ✅ native Core Text | ✅ MathJax in JavaScriptCore (no net/WebView) | n/a |
| Standalone LaTeX-string API | ✅ `MTMathUILabel.latex` | ✅ `LaTeX("…")` | ❌ markdown `$…$` only |
| Braced scripts `_{n=0}^{\infty}`, `x^{8}` | ✅ | ❌ **fails here** ("Extra open brace") | n/a |
| `\int`, `\frac`, `\partial`, `\sum` (w/ limits) | ✅ | ✅ command, ❌ braced limits | n/a |
| `\begin{bmatrix}` | ✅ | ❌ "Unknown environment" (needs AMS it can't load) | n/a |
| Sage's `\begin{array}{rr}` matrix | ❌ → rewrite to `pmatrix` | ✅ native | n/a |
| `\mathbb`, `\left\{…\right\}` set-builder | ✅ | ✅ (when not blocked by braced scripts) | n/a |
| SwiftUI integration | NSViewRepresentable wrapper (we wrote it) | native `LaTeX` view | n/a |
| Engine maturity | mature, 1.7.x | mature lib, but the JSC-bridge brace bug bit us | v0.1.0 math, immature |

Net: **SwiftMath covers the spec; LaTeXSwiftUI does not** (braced scripts are
fatal), **Textual is out** (macOS 15 + markdown-only). The `array` gap is the only
thing SwiftMath needed help with, and a boundary rewrite handles it cleanly.

---

## How SwiftMath is wired (V1.5 will reuse this)

- `SwiftMathRenderer.render` → pre-validate with `MTMathListBuilder` → either a
  `SwiftMathLabel` (NSViewRepresentable wrapping `MTMathUILabel`) or a red `Text`
  fallback.
- `SwiftMathLabel` reports the math's size to SwiftUI via the `sizeThatFits`
  representable API reading `MTMathUILabel.intrinsicContentSize` (+ a small margin)
  — **required**, or the NSView collapses to zero height and the math overlaps the
  row's caption/footer.
- **Dark mode is free**: set `label.textColor = .labelColor` (a dynamic semantic
  `NSColor`); it re-tints to white in dark mode automatically. Verified on screen.
- `.display` mode for block, `.text` for inline. Font sizes 22 (block) / 15
  (inline).
- SwiftMath ships `mathFonts.bundle`; `bundle.sh` copies `*.bundle` into the app's
  `Contents/Resources` so the fonts are present at runtime.

### The Sage `array` → matrix transform

Sage emits `\left(\begin{array}{rr}\n1 & 2 \\\n3 & 4\n\end{array}\right)`.
`SageLatexNormalizer.rewriteSageArrayMatrices` maps the wrapping delimiter to the
matching SwiftMath matrix env and drops the `{rr}` column spec and `\left…\right`:

- `\left(…\right)` → `pmatrix`  · `\left[…\right]` → `bmatrix`
- `\left|…\right|` → `vmatrix`  · `\left\{…\right\}` → `Bmatrix`
- bare `\begin{array}{…}` (no delimiters) → `matrix`

The cell body (`&`, `\\`) is unchanged. (Right-column alignment from `{rr}` is
dropped; SwiftMath matrices center by default. If alignment ever matters, use the
starred env `pmatrix*[r]`.)

---

## Recommendation for V1.5

1. **Adopt SwiftMath as the primary renderer**, behind this exact `MathRenderer`
   abstraction. Move `MathRenderer.swift` (the protocol, `SwiftMathRenderer`,
   `SageLatexNormalizer`, the NSViewRepresentable) into the app target close to
   the result-card views.
2. **Keep the Sage `array`→matrix rewrite** in the worker-output normalization
   path. It's small, well-tested, and the only thing standing between SwiftMath
   and Sage's real matrices.
3. **Keep `LaTeXSwiftUIRenderer` as a fallback option behind the seam.** If a
   future result needs something SwiftMath lacks (e.g. genuinely arbitrary
   `array` layouts, or constructs in SwiftMath's MISSING_FEATURES), the engine can
   be swapped per-call or globally without touching card code.
4. **Polish item (not a blocker):** inline math baseline alignment. Mixing an
   `MTMathUILabel` NSView into a SwiftUI `Text` run does not share a baseline, so
   inline math currently sits slightly below the sentence rather than on it. For
   V1.5 result cards this is mostly moot (the hero is block math); if inline
   matters, options are (a) render inline math to an `NSImage`/`Image` with a
   baseline offset, or (b) accept the small drop. Block, the 99% case, is perfect.
5. **Caching:** SwiftMath is fast (native), but for very long tapes consider
   caching `MTMathList`/rendered sizes keyed by the normalized LaTeX string.
6. **Do not ship LaTeXSwiftUI/MathJax as primary** unless the MathJaxSwift braced-
   brace defect is fixed upstream and re-verified on screen. The whole point of
   V0.4 was to find this before V1.5 built result cards on a broken engine.

---

## V1.5 — how the recommendation landed in the app (additive notes)

V1.5 adopted everything above. The lifted code lives in
`Sources/Casette/Rendering/` (the one v0/04 file split one-type-per-file, the
app convention): `MathRenderer.swift` (protocol), `SwiftMathRenderer.swift`
(active engine + the `MTMathUILabel` representable), `SageLatexNormalizer.swift`
(the `array`→matrix rewrite, unchanged), `MathView.swift` (the one
`activeMathRenderer` line + the view cards place). Decisions that EXTEND the
V0.4 record:

1. **`LaTeXSwiftUIRenderer` was NOT lifted into the app.** It stays on record in
   the frozen v0/04 proof. Shipping it would add the multi-megabyte
   MathJax/JavaScriptCore bundles for an engine V0.4 measured as broken here
   (braced scripts). The *seam* is what survives — swapping engines is still the
   one `activeMathRenderer` line plus a renderer file.
2. **Caching (recommendation 5) became `MathRenderCache`** — a `@MainActor`
   memo keyed by the RAW latex string, holding `(normalized, parses)`. Tape
   rows re-render on hover/selection and `LazyVStack` recycles rows while
   scrolling, so without it the regex rewrite + `MTMathListBuilder` parse re-run
   per body evaluation. Bounded (1024 entries, reset-on-overflow — simple beats
   clever, SWIFTUI-RULES §3.2). Typesetting itself stays on the main thread:
   `MTMathUILabel` is an NSView (main-bound by construction) and SwiftMath's
   native Core Text typeset is fast; the cache removes the *repeated* work,
   which is what actually threatened scroll performance.
3. **A second, guarded write barrier in the representable:** SwiftUI calls
   `sizeThatFits` + `updateNSView` every layout pass, and assigning
   `MTMathUILabel.latex` re-parses and re-typesets unconditionally — so
   `configure()` only assigns `latex`/`fontSize`/`labelMode` when the value
   actually changed.
4. **The card-level fallback is `plain`, not raw LaTeX** (`MathContent.choose`):
   when `latex` is missing or fails the (cached) parse check, result cards show
   the envelope's `plain` text monospaced — more useful than the renderer's
   raw-source fallback, which remains as the backstop for direct `MathView`
   callers (e.g. the Inspector preview only renders when `choose` says `.math`).
5. **Sizes:** block hero 19pt / inline 13pt (`Theme.mathBlockPointSize`/
   `mathInlinePointSize`) — the one documented hardcoded-point-size deviation
   (`MTMathUILabel` takes raw points, not semantic styles). Block is set above
   the title3 (15pt) text hero because typeset math reads optically smaller
   than mono text at equal point size.
6. **Bundling:** `build.sh` copies every SwiftPM resource bundle from the build
   products dir into `Contents/Resources` (today that's
   `SwiftMath_SwiftMath.bundle/mathFonts.bundle`) and verifies the generated
   SwiftMath `Bundle.module` accessor was patched to search that location.
   Without these fonts, SwiftMath traps in `Bundle.module` the first time an
   `MTMathUILabel` initializes after the app is copied away from the developer
   `.build` fallback (the V0.4 `bundle.sh` lesson, now in the real build).
7. **Accessibility:** the typeset math NSView is silent to VoiceOver, so the
   hero wraps it in `.accessibilityElement(children: .ignore)` +
   `.accessibilityLabel(plain)` — the envelope's `plain` text is the spoken
   value. Wide math scrolls horizontally inside the card instead of overflowing.

---

## V1.5 fix round — sizing correction + hero policy (additive)

The live gate caught one real engine trap and froze two policies:

1. **macOS sizing comes from `fittingSize`, NOT `intrinsicContentSize`.**
   SwiftMath overrides `intrinsicContentSize` on iOS only; on macOS it
   returns NSView's no-intrinsic sentinel (-1, -1), which sized every math
   view 0pt wide × (fontSize+6)pt tall. Unclipped layouts masked it (the
   NSView draws outside its frame); the tape's horizontally scrolling hero
   exposed it as a squeezed fraction, a clipped matrix bottom row, and an
   overflowing Inspector preview. The representable's `sizeThatFits` now
   reads `label.fittingSize`. Full story: PROBLEMS.md (V0.4 sizing trap,
   corrected). Guarded by `SwiftMathSizingTests`.
2. **Hero = display mode is policy, not just a mapping.** `.block` →
   `MTMathUILabelMode.display` matters specifically for fractions: text-mode
   fractions typeset their digits at SCRIPT size (~70%), inverting the
   visual hierarchy against the input echo line. Display-mode `\frac{8}{15}`
   at the 19pt hero size measures ~19×39 vs ~13×23 in text mode. `.inline`
   (Inspector preview) stays text-mode at 13pt — chrome, not hero.
3. **A new (narrow) normalizer rule: redundant relation parens.** Sage's
   `latex()` of a solve list wraps bare numeric right-hand sides:
   `\left[x = \left(-3\right)\right]`. `stripRedundantRelationParens`
   rewrites `= \left(-3\right)` → `= -3` for DISPLAY only — only after a
   relation sign, only a bare signed integer / `a/b` / `\frac{a}{b}`, never
   when the group carries a script. Copy LaTeX still yields Sage's own
   unmodified string.
4. **Inspector preview layout:** leading-aligned, fills the value column,
   horizontal `ScrollView` for wide matrices (scroll preserves typeset size
   where scale-to-fit would shrink math unreadably in a 240–400pt column);
   hidden from VoiceOver — the adjacent Plain/LaTeX fields are the spoken
   value.

---

## Evidence

All seven exit criteria were verified **on screen** via the computer-use MCP
(screenshots + zoom), then the app was confirmed alive and quit cleanly. Copy was
verified by `pbpaste` **and** `read_clipboard`. See `v0/04-latex-rendering/README.md`
for the criteria table and PROGRESS.md (2026-06-11) for the run narrative.
