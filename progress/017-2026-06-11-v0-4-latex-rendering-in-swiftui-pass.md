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
