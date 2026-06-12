## LaTeX rendering: MathJax-via-JavaScriptCore (LaTeXSwiftUI) fails BRACED sub/superscripts here

**The trap (V0.4).** LaTeXSwiftUI 2.0.0 → MathJaxSwift 3.5.0 (bundled MathJax in
JavaScriptCore, offline) renders single-character scripts but **fails every
*braced* sub/superscript** in this environment. Measured on screen:

- `\int_0^1 x^2\,dx` → ✅ renders. `\int_{0}^{1} x^2 dx` → ❌ raw text.
- `\sum n` → ✅. `\sum_{n=0}^{10} n` → ❌. `\sum_{n=0}^{\infty}\frac{x^n}{n!}` → ❌.
- `x^2` → ✅. `x^{8}` (which Sage emits for `expand((x+1)^8)`) → ❌.
- `\begin{bmatrix}` → ❌ "Unknown environment". `\mathbb{R}` → ✅. Sage's
  `\begin{array}{rr}` → ✅.

MathJax's own error (caught via a throwaway probe) is **"Extra open brace or
missing close brace"** — i.e. the `{` of `_{…}`/`^{…}` reaches MathJax unbalanced.
The defect is in the MathJaxSwift JSContext bridge / argument marshaling, not in
the LaTeX: the same strings render fine in a browser MathJax. It is **not** a
package issue — `loadPackages: .all` vs `[base]` made no difference, and
LaTeXSwiftUI hardcodes `TeXInputProcessorOptions(processEscapes:errorMode:)`
(base packages only, no way to add AMS) anyway. It is **not** a parser/delimiter
issue — `\[…\]`, `$$…$$`, and `parsingMode(.all)` (which bypasses LaTeXSwiftUI's
parser entirely) **all** failed identically. Braced scripts are unavoidable in
real Sage output, so this is fatal for the worker's `latex` field.

**The fix:** don't fight it — swap the engine. **SwiftMath** (native Core Text,
no JS) renders every one of these correctly. We did this behind the `MathRenderer`
abstraction with zero app-code change. See plans/MATH-RENDERING.md.

**Corollary lessons that cost time:**
- **A blocking `DispatchSemaphore.wait()` on the main thread deadlocks
  MathJaxSwift's `tex2svg`** (it hops back to the main queue). A standalone probe
  hung forever at the first conversion until rewritten to drive an async `Task`
  and `exit(0)` from inside it with `RunLoop.main.run()` on the main thread.
- **A bare SwiftPM executable can't be granted to computer-use and may not load a
  dependency's `Bundle.module` resources reliably.** Wrap the proof in a minimal
  `.app` (Info.plist + ad-hoc codesign, see `bundle.sh`) so it gets a Dock
  identity, a frontable window, an allowlist-matchable name, and correct resource
  bundle resolution.

---
