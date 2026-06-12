## 2026-06-11 — V1.5: Result rendering v1 — PASS (live gate PASSED after one fix round)

**Final live gate (opus verifier, computer-use) — PASS, all 8 re-checks.**
On screen: `expand((x+1)^8)` typesets the full polynomial with braced
superscripts, no NameError, `x` predefined from boot AND after ⌘⇧R restart;
the `8/15` fraction hero is now visibly larger than its input echo (hierarchy
correct); matrix rows fully visible at default window size; Inspector
"Rendered" leading-aligned and whole; pasted curly-quoted `print("hello")`
normalizes and prints; solve list shows `[x = -3, x = -2]` with no redundant
parens while Copy LaTeX preserves Sage's original; dark mode re-tints all
typeset math correctly; quit clean, `pgrep` clean. **Verifier's aesthetic
verdict: "a polished, native-feeling macOS calculator tape."**

> **This phase spans three agent runs.** The implementation agent built the
> feature and was killed (quota) before running the gate or writing docs; a
> completion agent audited the work against the INITIAL.md V1.5 spec (all
> items found genuinely implemented), applied the skill findings, ran the FULL
> gate below, and wrote these docs. The live on-screen verifier then returned
> **PASS with caveats**; a fix agent resolved all six flagged items (next
> section) — the caveats need one focused on-screen re-check.

**The tape renders math.** The V0.4-proven SwiftMath engine is in the app
behind the lifted `MathRenderer` abstraction, and every row is now a V1.5
result card.

### Fix round (2026-06-11) — the verifier's caveats, all six resolved

1. **`expand((x+1)^8)` NameError'd** — raw-Sage bypasses hit the worker
   namespace where `x` is NOT predefined (PROBLEMS.md V0.5), unlike the real
   Sage REPL. **Decision implemented: match the REPL.** `ShellModel` now
   sends a `var('x')` boot prelude (`ShellModel.bootPrelude`) after every
   boot AND every restart, app-side (worker.py stays byte-frozen, `cmp`
   verified), then refreshes symbols — `x` honestly shows in the sidebar
   from boot, exactly like the REPL predefining it. The friendly compiler's
   own `var('x')` preludes on top are idempotent and harmless. Tests:
   fake-transport boot/restart prelude wire order, two updated order
   assertions, and a real-Sage integration test (`expand((x+1)^8)` →
   symbolic envelope with `x^{8}` straight after boot; after restart,
   symbols == `[x]` and `expand((x+1)^2)` still works).
2. **Fraction hero undersized (the headline beauty flaw) — root cause was
   NOT labelMode** (the hero already used `.display`): the representable's
   `sizeThatFits` read `MTMathUILabel.intrinsicContentSize`, **which
   SwiftMath overrides on iOS only** — on macOS it returns NSView's
   no-intrinsic sentinel (-1, -1), so EVERY math hero was laid out 0pt wide
   × (fontSize+6 = 25)pt tall. Single-line math drew outside its frame
   unclipped and *looked* right (which is how v0/04 passed); the hero's
   clipping `ScrollView` squeezed fractions (39pt tall at 19pt display
   mode) and matrices. Fixed: read `fittingSize` (the macOS accessor for
   the typeset size). Display-mode `\frac{8}{15}` measures 19×39 vs
   text-mode 13×23 — both the engine fact and the hero=display policy are
   locked in by the new `SwiftMathSizingTests`. PROBLEMS.md V0.4 sizing
   entry CORRECTED; MATH-RENDERING.md extended (fix-round section).
3. **Matrix bottom row clipped at default window size** — largely the same
   0×25 sizing bug (the matrix overdrew its frame downward, past the scroll
   viewport); additionally the tape now has a real bottom inset:
   `.contentMargins(.bottom, Theme.tapeBottomMargin, for: .scrollContent)`
   (a scroll-content margin, NOT a spacer), so the bottom rest position and
   `scrollTo(anchor: .bottom)` always leave the last row's full height
   clear of the input pane.
4. **Inspector "Rendered" preview clipped/right-aligned** — width-0 sizing
   (same root cause) compounded by `LabeledContent`'s trailing value
   alignment. Now leading-aligned filling the value column, with a
   horizontal ScrollView for wide matrices (scroll keeps the typeset size
   honest where scale-to-fit would shrink it unreadably — macos-design
   reviewed), and `accessibilityHidden` (the NSView is silent to VoiceOver;
   the adjacent Plain/LaTeX fields are the spoken value — swiftui-pro
   finding, applied).
5. **Smart quotes** — `print(“hello”)` SyntaxError'd. `CompiledInput` now
   normalizes U+201C/U+201D → `"` and U+2018/U+2019 → `'` at the compile
   boundary, BEFORE the bypass/friendly decision (and for chosen ambiguity
   candidates and the multiline bypass path), so the row's recorded raw
   input is exactly what was evaluated. Documented trade-off: pasted string
   literals CONTAINING curly quotes are altered too — acceptable for a
   calculator input field. Tests: compile-boundary unit tests + a
   fake-transport test proving the wire and the row both see ASCII.
6. **Solve-list `[x = (−3)]` redundant parens** — done (it turned out
   cheap and safe as a display-only normalizer rule):
   `SageLatexNormalizer.stripRedundantRelationParens` rewrites
   `= \left(-3\right)` → `= -3` only after a relation sign, only for a bare
   signed integer / `a/b` / `\frac{a}{b}`, and never when the group carries
   a script (load-bearing parens). Shapes verified against real Sage 9.5
   latex output; Copy LaTeX still yields Sage's own unmodified string.

**Fix-round gate.** `make check` ✓ · **`make test` 205/205** (30 suites; was
197/197 — +8 new: boot/restart prelude over fakes, wire-level smart quotes,
compile-boundary smart quotes, relation-parens strip ×2, SwiftMath sizing
facts ×2, real-Sage boot-prelude integration) · **v0/07 e2e 19/19** (the
worker and kernel were untouched — quick regression sanity only; bundled
worker.py `cmp` byte-identical) · swiftui-pro (one finding, applied: a11y-
hide the silent NSView preview in the Inspector) + macos-design (clean:
content margin over spacer, scroll over scale-to-fit, hero-dominates-echo
hierarchy) · `make build` ✓ · launched `build/Casette.app` via `open`: alive
14s with exactly ONE worker chain, AppleScript quit →
`pgrep -fl "Casette|sage -python|worker.py"` clean.

**Re-verification checklist (the six caveats, on screen):**
1. `expand((x+1)^8)` → a typeset polynomial card, NO NameError; the Symbols
   tab lists `x` from boot. Then ⌘⇧R and `expand((x+1)^2)` → works; Symbols
   shows exactly `x` again right after the restart.
2. `1/3 + 1/5` → the `8/15` fraction hero typesets LARGER than the input
   echo line (full-size digits, display mode), `≈ 0.5333333333` below it.
3. `matrix([[1,2],[3,4]])` at the default window size → BOTH matrix rows
   fully visible with the tape rested at the bottom — nothing tucked behind
   the input pane; clear breathing room below the last row.
4. Select the matrix row → Inspector "Rendered" preview is leading-aligned
   and fully visible in the column (whole matrix incl. both parens); a wide
   matrix scrolls horizontally inside the preview.
5. Type/paste `print(“hello”)` WITH curly quotes → statement card with
   stdout `hello`, no SyntaxError; the row's input echo shows straight
   quotes (exactly what was evaluated).
6. `solve x^2 + 5*x + 6 = 0` (friendly) → list card reads `[x = -3, x = -2]`
   with no redundant parens; context-menu Copy LaTeX still yields Sage's
   original parenthesized string via `pbpaste`.

### What was built

- **`Sources/Casette/Rendering/`** — the v0/04 surviving artifact, split
  one-type-per-file: `MathRenderer` (protocol), `SwiftMathRenderer` (active
  engine; `MTMathUILabel` representable with `sizeThatFits` →
  ~~`intrinsicContentSize`~~ *(superseded by the fix round: that override is
  iOS-only — on macOS it's `fittingSize`)* so math never collapses/overlaps,
  `.labelColor` for free dark mode), `SageLatexNormalizer` (the load-bearing Sage
  `array`→`pmatrix`/`bmatrix`/`vmatrix`/`Bmatrix` rewrite, byte-equivalent
  rules), `MathView` (the one `activeMathRenderer` line), plus two V1.5
  additions: **`MathRenderCache`** (bounded `@MainActor` memo of
  normalize+parse keyed by raw latex — hover/selection re-renders and
  LazyVStack recycling stop re-running regexes/parser; typeset stays on main
  because `MTMathUILabel` is an NSView and native typeset is fast) and
  **`MathContent`** (the card-level fallback decision: `.math` only when the
  cached parse succeeds, else `.plain`). `LaTeXSwiftUIRenderer` deliberately
  NOT lifted (multi-MB MathJax bundles for an engine V0.4 measured broken
  here); the seam is what survives. Details: plans/MATH-RENDERING.md §V1.5;
  perf traps: PROBLEMS.md (new entry).
- **`Model/ResultCardKind.swift`** — the spec's card vocabulary as a derived
  (never stored) presentation enum off the frozen envelope: scalar exact /
  scalar approximate (incl. V0.8 force-numeric via `primaryIsApprox`) /
  symbolic (+relation) / matrix / list (incl. tuple + solve's Sequence) /
  plot / text (boolean/unknown degrade here) / error, plus
  pending/statement/interrupted row states.
- **Card anatomy.** Collapsed: chevron + input echo + timestamp +
  hover-revealed Copy button, then the rendered result (`ResultHeroView`:
  block math hero with horizontal scroll for wide results,
  VoiceOver-bridged to `plain`; `≈ approx` secondary line; honest
  truncation note). Expanded (chevron toggles the persisted
  `SessionRow.expanded` via `ShellModel.toggleExpanded`): Input / Generated
  Sage / Plain sections (`CardSectionView`, each with its own copy context
  menu) + the traceback disclosure. Structural conditional, NO transition
  (§1.1). Errors/interrupts: type + message prominent (red/orange),
  traceback hidden behind `TracebackDisclosureView` (hand-rolled, not
  `DisclosureGroup` — it animates insertion), scrolling past 180pt, also in
  the Inspector. `stdout` renders as a labeled mono block ABOVE the result
  (execution order) for every card; statement rows show it alone. Plot rows
  keep the placeholder chrome until V1.7.
- **Truncation honesty.** `PersistedEnvelope` gains the optional
  `truncation` sizes object (`plain_len`/`repr_len`/caps) — the ONE additive
  deviation from the verbatim V0.10 lift, documented in SESSION-FORMAT.md
  (schema v1 unchanged; omitted-when-nil). `factorial(10^5)` now reads
  "Truncated — showing 8,192 of 456,574 characters" instead of a bare flag.
- **Copy affordances:** row context menu (Input / Generated Sage / Result /
  LaTeX / Traceback, each gated on presence), hover button (result, falling
  back to input), per-section menus in the expanded card, traceback menu.
- **Inspector additions:** small rendered LaTeX preview (only when the
  engine parses it), truncation note, traceback disclosure.
- **Theme:** card metrics + four type tokens (`cardSectionLabel`,
  `cardMono`, `tracebackMono`, `truncationNote`) on the existing two-axis
  system; math point sizes 19/13 are the one documented §5.1 deviation
  (`MTMathUILabel` takes raw points; 19 > title3's 15 because typeset math
  reads optically smaller).
- **Build:** Package.swift pins SwiftMath ≥1.7.3 (same as the v0/04 proof);
  `build.sh` copies SwiftPM resource bundles (`SwiftMath_SwiftMath.bundle`
  with `mathFonts.bundle`) into `Contents/Resources` — verified present in
  the assembled app (without it math renders nothing at runtime).

### Gate (completion agent, all PASS)

- `make check` ✓ · **`make test` 197/197** (28 suites) — incl. new
  `MathRenderingTests` (normalizer rules + `MathContent` fallback + cache
  consistency), `ResultCardKindTests` (mapping + presentation-only +
  truncation-note + Codable round-trip), and `ResultRenderingIntegrationTests`
  against REAL Sage (matrix `array`→pmatrix end-to-end, `expand((x+1)^8)`
  braced scripts parse, solve-list latex renders, `1/3+1/5` exact + approx,
  `print("hello")` → statement card with stdout, `factorial(10^5)` truncated
  with sizes).
- **Full V0 regression:** V0.1 **18/18** · V0.2 **35/35** · V0.3 **97/97** ·
  V0.5 **88/88** · V0.6 **24/24** · V0.8 **95/95** · V0.7 swift **69/69** +
  e2e **19/19** · V0.9 swift **32/32** · V0.10 swift **21/21**. `pgrep`
  clean after (see anomaly note below).
- **Skills applied:** swiftui-pro — one finding (chevron disclosure button
  rewritten from icon-only `Image` label to the `Button(_:systemImage:)` +
  `.labelStyle(.iconOnly)` form, matching the Copy button); everything else
  conformed (no deprecated API, `.animation` always has `value:`, semantic
  fonts, a11y bridges on the math NSView and the tap-selection row).
  macos-design — clean (progressive disclosure, hover-reveal via opacity,
  context menus, `.help` tooltips, semantic colors; the no-transition
  expand is the project's own §1.1 rule). typography-designer — clean (new
  tokens land on the existing scale; hierarchy stays monotonic: math hero
  19 > title3 hero > callout mono > caption).
- `make build` ✓ (fonts bundle in Resources) · launched `build/Casette.app`
  via `open`: alive ~13s with exactly ONE Sage worker, AppleScript quit →
  `pgrep -fl "Casette|sage -python|worker.py"` clean.
- **Anomaly noted (not V1.5 code):** a leftover Casette.app from the killed
  implementation run was found holding THREE live workers (boot 21:29 + two
  more sessions at 22:04, per the worker log). V1.5 touched nothing under
  Kernel/, the cause couldn't be reconstructed (the run was killed
  mid-phase), and the quit-time reaper cleanly killed all three generations
  on AppleScript quit. If the verifier ever sees multiple workers under one
  app pid, capture `ps` ancestry + the worker log BEFORE quitting.

### On-screen verifier checklist (V1.5 — pending)

In `build/Casette.app` (real Sage), verify on screen:

1. `1/3 + 1/5` → scalar-exact card: rendered `8/15` fraction hero,
   `≈ 0.5333333333` secondary line below it.
2. `sqrt(2)` → symbolic card: rendered radical, `≈ 1.414213562` line.
3. `expand((x+1)^8)` → long polynomial with braced superscripts (`x^{8}`)
   typeset correctly; wide math scrolls horizontally inside the card.
4. `matrix([[1,2],[3,4]])` → parenthesized 2×2 matrix (the `array`→pmatrix
   rewrite, on screen).
5. `solve x^2 + 5*x + 6 = 0` (friendly) → list card with rendered solutions.
6. `print("hello")` → statement card: labeled `stdout` block, no value hero.
7. `1/0` → error card: `ZeroDivisionError` + message in red, NO traceback
   visible; expand the row → Traceback disclosure → click → traceback text,
   scrolls if long; context menu has Copy Traceback.
8. `factorial(10^5)` → digits + "Truncated — showing 8,192 of 456,574
   characters" note.
9. `plot sin(x), x=-pi..pi` (friendly) → plot card chrome (placeholder
   image + caption — real PNG is V1.7).
10. Chevron expands a card: Input / Generated Sage / Plain sections appear
    under the still-visible rendered result; chevron rotates; collapse
    restores; expanded state survives scrolling away and back.
11. Copy: hover a row → copy button fades in, click → `pbpaste` matches
    plain; context menu Copy Input / Generated Sage / Result / LaTeX each
    verified via `pbpaste`.
12. Dark mode: math re-tints to white (semantic `.labelColor`), all card
    chrome legible.
13. Scroll performance: evaluate ~15+ mixed rows (reuse the inputs above),
    scroll the tape up/down briskly — no visible hitching; hover rows while
    scrolling.
14. Inspector: select the matrix row → Rendered preview above the LaTeX
    source; select the error row → Error type + traceback disclosure.
15. Quit via ⌘Q → `pgrep -fl "Casette|sage -python|worker.py"` clean.



Append-only. Newest entries at the top. One entry per meaningful change:
what changed, what I learned, what surprised me.

---
