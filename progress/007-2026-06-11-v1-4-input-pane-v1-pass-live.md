## 2026-06-11 — V1.4: Input pane v1 — PASS (live gate PASSED across rounds 4+5)

**Live gate (opus verifier, computer-use) — PASS, evidence combined across
two rounds of identical code.** Round 4 verified on screen: digit `2`
selects the y-candidate (`[y == (1/x)]`), Return selects the first
candidate, clicking a candidate works, type-through inserts + dismisses,
Esc passthrough with no panel is safe, history walk (incl. past a multiline
entry, cursor-reset-on-edit), smoke (`factor x^4 - 1`, `1+1`), and clean
exit with zero orphans. Round 5 verified the one remaining item — **Esc
dismisses the panel with the draft kept** — twice, using
`scripts/send-key.swift 53 <pid>` to bypass the harness's Esc-eating event
tap (see fix round 5 + PROBLEMS.md). Round 5 was then interrupted by the
machine's idle screen lock; the regression items it didn't re-reach are
exactly those round 4 had already passed (the only code delta between
rounds was temporary logging, since removed). App quit cleanly via
AppleScript post-lock; `pgrep` clean. Earlier rounds also verified: friendly
compile + preview line, raw-bypass tag, double integral → 1/8, prelude
policy (clean Generated Sage, `t` in Symbols), inline error never submits,
⇧⏎ multiline grow, ⌘⏎ evaluate-without-advancing, dark mode.

### Fix round 5 (2026-06-12, orchestrator) — Esc was NEVER an app bug after round 2: the AUTOMATION HARNESS eats keyCode 53 system-wide

Rounds 3–4 "failed on screen" because the verifier's Esc presses never
reached the app at all. Temporary logging in `EscapeInterceptor` showed the
local monitor logging every keyDown EXCEPT Esc; a session-level CGEvent tap
saw the injected Esc, but a pid-level tap on Casette never did.
`CGGetEventTapList` found the cause: a session-wide **filtering keyDown tap
owned by the computer-use harness itself** (its abort key), which consumes
every Esc — physical, MCP `key`, or AppleScript — before per-app delivery.
Posting Esc directly to the app's pid (`CGEvent.postToPid`, new helper
`scripts/send-key.swift`) proved the round-4 `EscapeInterceptor` correct:
`onEscape -> true`, panel dismissed, draft kept. Full story + rules in
PROBLEMS.md ("THE AUTOMATION ENVIRONMENT EATS Esc"); V1.12 must verify
shortcuts with the helper. 172/172 tests still green after removing the
instrumentation.

### Fix round 4 (2026-06-11) — Esc, finally: NSTextView EATS `cancelOperation:`; only an AppKit local NSEvent monitor can see Esc first

Round 3's `.onExitCommand` fix failed on-screen verification exactly like
rounds 1–2's `.onKeyPress(.escape)`: panel up, Esc pressed, panel stays
(third independent on-screen confirmation; every other path — digits 2–9,
Return-takes-first, click, type-through-dismisses, history — kept working).
**Root cause, completing round 3's half-right diagnosis:** Esc IS translated
to `cancelOperation:` before key-press handlers run (round 3 was right
there), but the `NSTextView` backing `TextEditor` implements
`cancelOperation:` itself (it uses it to dismiss completion sessions) and
CONSUMES it — the action never travels up the responder chain, so SwiftUI's
`.onExitCommand` never hears about it either, no matter where it's attached.
Conclusion: **no SwiftUI-level hook on or above a focused TextEditor can see
Esc.** The fix drops to AppKit at the one interception point that runs
before the window dispatches the key at all: a local NSEvent monitor.

**The fix:**
- New `Sources/Casette/Views/EscapeInterceptor.swift`: an
  `NSViewRepresentable` whose backing `NSView` owns
  `NSEvent.addLocalMonitorForEvents(matching: .keyDown)`. On
  `keyCode == 53` it asks its `onEscape: () -> Bool` closure; `true` →
  return `nil` (event swallowed before the text view sees it), `false` →
  event passed through unchanged. Guards: `event.window === self.window`
  (other windows never affected), weak `self` in the handler (no
  view↔monitor retain cycle), `hitTest → nil` (invisible to the mouse).
  Lifecycle: `viewDidMoveToWindow` installs the monitor exactly once
  (token-nil guard — SwiftUI re-renders can't stack duplicates) and
  removes it on window detach; `deinit` is the backstop
  (`nonisolated(unsafe)` on the token, documented — only ever written on
  the main actor, deinit access is exclusive). The handler hops into
  `MainActor.assumeIsolated` (local monitors dispatch on the main run
  loop; the imported AppKit closure type just isn't annotated).
- `InputPaneView` mounts it: `.background(EscapeInterceptor {
  model.cancelAmbiguity() })`. Behavior scoped by the model, not the
  monitor's lifetime: `cancelAmbiguity()` returns `false` when no panel
  is pending, so plain Esc passes through and keeps its system behavior
  (full-screen exit etc.). The monitor simply lives as long as the pane.
- `InputEditor`: the dead round-3 `.onExitCommand` and rounds-1–3
  `.onKeyPress(.escape)` routes + `handleEscape` are REMOVED (not kept as
  "fallbacks" — they imply they can fire, and they can't; comments now
  point at `EscapeInterceptor`). Return/digits/Up/Down handlers untouched.

No model changes — `cancelAmbiguity()` and its tests are as round 1 left
them. PROBLEMS.md inline-overlay entry rewritten (round-4 symptoms, the
consume-don't-forward cause, rule 4 replaced: Esc over a focused text view
is invisible to SwiftUI; intercept with a local NSEvent monitor, swallow
only when there's something to cancel in your window).

**Gate (fix round 4).** `make check` ✓ · `make test` **172/172** (key
routing stays unfalsifiable by unit tests — PROBLEMS.md rule 2) ·
swiftui-pro sanity on the three touched files (one type per file; no
`import AppKit` needed under SwiftUI; concurrency escape hatches scoped and
documented; closure refreshed in `updateNSView` so it never goes stale) ·
`make build` ✓ · launched `build/Casette.app` via `open`: alive 8s+ with
Sage worker booted, AppleScript quit → `pgrep -fl "Casette.app|sage
-python|worker.py"` clean. **On-screen Esc re-check (checklist step (a))
still needs the verifier pass — but unlike rounds 1–3 this route runs
before the text view can interfere, by construction.**

### Fix round 3 (2026-06-11) — Esc on the inline panel: `cancelOperation:` needs `.onExitCommand`

Round 2's inline overlay verified on every path but ONE: Esc didn't dismiss
the panel (digits/Return/click/type-through all fine; the editor clearly
kept focus, since a typed `z` landed in the field and dismissed it).
**Root cause:** on macOS, Escape never reaches a focused text view as a key
press — the Cocoa key-binding system translates it into the
`cancelOperation:` ACTION first, which walks the responder chain, so the
round-1/2 `.onKeyPress(.escape)` handler on the `TextEditor`
(`InputEditor.swift`) could never fire. Digits and Return arrive as real
key presses, which is why everything else worked.

**The fix (one modifier in `InputEditor.swift`):** SwiftUI surfaces
`cancelOperation:` as the exit command —
`.onExitCommand(perform: model.pendingAmbiguity == nil ? nil : { model.cancelAmbiguity() })`
on the `TextEditor`. The handler is installed only while the picker is up,
so with no picker Esc keeps its default responder-chain behavior (e.g.
exiting full screen). The `.onKeyPress(.escape)` route stays as a harmless
fallback. No model changes; `cancelAmbiguity()` and its tests are untouched.
PROBLEMS.md inline-overlay entry updated with the lesson (new rule 4: Esc on
a focused text view is `cancelOperation:`, not a key press).

**Gate (fix round 3).** `make check` ✓ · `make test` **172/172** (model API
untouched, no new tests needed — this is key routing, unfalsifiable by unit
tests per PROBLEMS.md rule 2) · swiftui-pro sanity on `InputEditor` (review
led to the conditional-`nil` handler instead of an unconditional closure) ·
`make build` ✓ · launched `build/Casette.app` via `open`: alive, AppleScript
quit, no stray Casette/Sage processes. **On-screen Esc re-check (checklist
step (a) below) still needs a human/verifier pass — same caveat as every
key-routing fix.**

### Fix round 2 (2026-06-11) — ambiguity picker re-architected: popover → inline same-window overlay

Round 1's fix FAILED on-screen re-verification — and regressed the mouse
path. With the popover up: Esc/digits/Return all dead, a plain `z` swallowed
(keys reached NEITHER the popover NOR the field), and clicking a candidate
row no longer worked; only ⌘A+Delete (→ draft-didSet dismissal) passed.
**Root cause, deeper than round 1's diagnosis: a macOS SwiftUI `.popover` is
presented as its OWN KEY WINDOW.** The moment it appears the main window's
`TextEditor` loses first-responder status, so the round-1 `onKeyPress`
handlers on the editor never fire — and the popover side has no working key
routing of its own. There is no winning arrangement with `.popover`;
PROBLEMS.md entry rewritten with the full story.

**The round-2 fix changes the presentation architecture, not the model:**
- `.popover` is GONE. `AmbiguityPickerView` is now an inline suggestion
  panel (material, rounded, shadowed) rendered by a conditional
  `.overlay(alignment: .topLeading)` on `InputPaneView`, alignment-guided
  (`panel[.bottom] + gap`) to float directly above the pane, over the tape —
  same window, so the editor keeps keyboard focus the entire time and the
  round-1 key routing (Esc → `cancelAmbiguity`, Return → first candidate,
  digits 2–9 → nth, any edit → dismiss via `draft.didSet`) now actually
  fires. The ShellModel API from round 1 is unchanged.
- Candidate rows are plain `Button`s (`.plain` style, hover tint,
  `.contentShape(.rect)`) with NO `keyboardShortcut`s — the editor owns the
  keys; the panel owns only the mouse. No focusable controls in the panel,
  so it can never steal first responder; `InputPaneView.onChange` asserts
  editor focus on both panel show and dismissal.
- Appear/disappear is a plain structural conditional with no transition —
  instant (the verifier called the popover fade sluggish), and §1.1-safe
  (the rule is about *animated* insert/remove; same precedent as the
  kernel banner).
- Panel hints now read `↩ first   2–9 choose   esc keep editing` — exactly
  the behaviors the editor implements.

**Gate (fix round 2).** `make check` ✓ · `make test` **172/172** (no test
changes needed — the model API is untouched; the popover had no tests of its
own) · swiftui-pro review applied (`InputPaneView` dropped a now-unneeded
`@Bindable` — the popover's binding was its only use) · `make build` ✓ ·
launched `build/Casette.app` via `open`: Sage booted (worker pids visible),
alive 12s+, AppleScript quit → `pgrep -fl "Casette.app|sage -python|worker.py"`
clean.

**Re-verification checklist for the ambiguity panel (replaces step 7):**
type `solve x*y = 1` → Return → an inline panel appears INSTANTLY above the
input pane (not a detached popover) listing `solve(x*y == 1, x)` (hint ↩)
and `solve(x*y == 1, y)` (hint 2), footer `↩ first   2–9 choose   esc keep
editing`. Then, in order: (a) **Esc** → panel gone instantly, draft intact,
typing works immediately; (b) Return → panel; press **2** → evaluates the
y-reading → `[y == (1/x)]`, draft cleared, panel gone; (c) fresh
`solve x*y = 1` → Return → panel; **Return again** → evaluates the
x-reading (first candidate); (d) panel up → **click** the second candidate
row → it evaluates (mouse path restored); (e) panel up → **⌘A then Delete**
(or type any character, e.g. `z`) → the edit reaches the FIELD (text
visibly changes) and the panel dismisses with no stale candidates; a digit
pressed afterwards types normally. History steps (10) from round 1 stand
unchanged.

### Fix round (2026-06-11) — ambiguity-popover keyboard wiring + history-cursor reset

The on-screen verifier failed the gate on the ambiguity popover's keyboard
path (Esc didn't dismiss, digit 2 typed literal text, clearing the field left
stale candidates showing) plus two history caveats. Root cause: **a macOS
SwiftUI `.popover` is a passive overlay — keyboard focus stays in the
`TextEditor`, so the popover's `keyboardShortcut`s (Return/digits) never fire
and Esc goes to the text view.** Mouse clicks worked; every advertised key
was dead. (Full lesson in PROBLEMS.md.)

**The fix — the focused editor IS the picker's keyboard, and one "user
edited the draft" hook drives everything:**
- `ShellModel.draft` gained a `didSet`: any draft change that is NOT a
  history recall (an `@ObservationIgnored isRecallingHistory` flag set only
  by `setRecalledDraft`) dismisses a pending ambiguity (the candidates are
  stale) and ends history navigation (`InputHistory.endNavigation()` — the
  next Up starts at the newest entry, standard shell behavior). This is the
  blocking defect's "dismiss on edit" AND minor #1 in one model-level hook.
- New model API (testable, shared by both keyboard paths):
  `cancelAmbiguity()` (Esc: dismiss, draft kept) and
  `resolveAmbiguity(at:)` (Return = index 0, digits 2–9 = indices 1–8;
  out-of-range = no-op, picker stays).
- `InputEditor` routes the keys while `pendingAmbiguity != nil`: Esc →
  `cancelAmbiguity`, Return → `resolveAmbiguity(at: 0)`, digits 2–9 →
  `resolveAmbiguity(at: digit-1)` (out-of-range digits are swallowed so they
  can't silently edit the draft); with no picker up all three behave exactly
  as before. Focus restoration on dismissal was already wired
  (`InputPaneView.onChange`). The popover buttons keep their shortcuts as
  the backup path should its window ever become key — both paths call the
  same model methods, so hints and behavior can't diverge.
- **Minor #2 (multiline recall stranding) — fixed, semantics refined:**
  while history navigation is in progress, Up/Down KEEP navigating even when
  the recalled entry is multiline (you can't get stuck on `a = 5⏎a * 9`);
  the moment you edit, navigation ends and the arrows hand back to the
  cursor. macOS 14's `TextEditor` has no cursor introspection
  (`TextEditor(text:selection:)` is macOS 15+), so "Down only at the very
  end" wasn't buildable — this rule is the honest, coherent version: arrows
  navigate while you're flipping through history, edit to start editing.
  The nuance: to arrow-around INSIDE a recalled multiline entry you must
  edit (or click) first. The "Up at start of a fresh multiline draft" gap is
  unchanged (still documented, still not a behavior).

**Gate (fix round).** `make check` ✓ · `make test` **172/172** (163 + 9 new:
`InputHistory.endNavigation` reset/no-op; ShellModel esc-keeps-draft,
pick-by-index incl. out-of-range, edit-dismisses-picker,
recall-dismisses-picker, user-edit-resets-cursor-to-newest,
multiline-recall-keeps-navigating, edit-ends-multiline-navigation) ·
swiftui-pro re-review applied (Esc handler extracted to a method like the
other key handlers; logic stays on the model) · `make build` ✓ · launched
`build/Casette.app` via `open`: Sage booted (worker pids visible), alive
12s+, AppleScript quit → `pgrep -fl "sage -python|worker.py"` clean. (No V0
regression rerun — the kernel/worker were untouched this round.)

**The live-gate checklist below stands, with steps 7 and 10 SUPERSEDED by:**
- **7 (ambiguity, replaces the original):** type `solve x*y = 1` → Return →
  popover lists `solve(x*y == 1, x)` (hint ↩) and `solve(x*y == 1, y)`
  (hint 2). Press **Esc** → popover closes, draft intact, focus in the
  field, typing works immediately. Return again → popover; press **2** →
  evaluates the y-reading → `[y == (1/x)]`, draft cleared, popover gone.
  Fresh `solve x*y = 1` → Return → popover; press **Return** again →
  evaluates the x-reading (first candidate). Once more: popover up,
  **⌘A then Delete** (or type any character) → popover dismisses, no stale
  candidates over the field; a digit pressed afterwards types normally.
- **10 (history, replaces the original):** from a single-line draft press
  **Up** repeatedly — `factor x^8 - 1`, `factor x^6 - 1`, the multiline
  `a = 5⏎a * 9` (arrows now CONTINUE past it), … to the oldest; **Down**
  walks forward through everything — including past the multiline entry —
  and finally restores the draft you started from. Then: press Up twice
  (mid-list), **⌘A + Delete** to clear, press Up → it recalls the NEWEST
  entry (the cursor reset). Then: recall the multiline entry, type one
  character into it → Up/Down now move the cursor (editing ended
  navigation), as documented.

---

**The input pane is a calculator now, and the friendly compiler is wired in.**
Typing `factor x^4 - 1` shows the generated Sage live under the field, Return
evaluates it through the real kernel (with the `var('x')` prelude), errors
explain themselves inline without submitting, ambiguity offers its candidates,
Shift-Return makes the field multiline, ⌘-Return evaluates without advancing,
and Up/Down walk the session's submitted inputs with the customary
draft-preservation. Raw Sage still flows through untouched, exactly as V1.3.

**How the compiler was lifted.** `FriendlyCompiler` is now a second SwiftPM
**library target** (`Sources/FriendlyCompiler/`) the app target depends on. The
four library files (CompileResult / FriendlyCompiler / Scanner / Variables) and
the 69-test suite (`Tests/FriendlyCompilerTests/`) are **byte-identical** to
v0/07 (`cmp`-verified at lift time; v0/ untouched). The ONLY app-side addition
is one new file, `FriendlyCompiler+App.swift`, exposing the library's own
free-variable heuristic publicly — needed because a chosen `.ambiguous`
candidate string carries no `requiredVariables` of its own, and the preludes
must come from the same documented heuristic, not a re-implementation. The
lifted suite runs as part of `make test` (69/69).

**The compile boundary (`CompiledInput.compile`).**
- `.success` → `CompiledInput` origin `.friendly`: row records `input` = the
  raw text, `sage` = the generated Sage (the honest input-vs-sage split).
- `.bypass` → origin `.bypass`, raw == sage, untouched.
- `.error` / `.ambiguous` → never become a `CompiledInput`; they surface as
  `Outcome.error/.ambiguous` so the UI can refuse/ask without a row.
- **Multiline input bypasses BEFORE the compiler** — the V0.7 library was
  written for one line and *flattens newlines to spaces*, which would corrupt
  newline-sensitive raw Sage (new PROBLEMS.md entry). Friendly forms are
  single-line by definition, so this loses nothing.

**Prelude policy (FRIENDLY-COMPILER.md, frozen, implemented exactly).** On
submit, each `requiredVariable` is sent as its own `var('V')` eval ahead of the
generated Sage, through the same serial kernel queue (order proven by test).
Prelude results are discarded; the row's envelope is the MAIN eval's, so the
displayed result corresponds exactly to the displayed generated Sage, and
`SessionRow.sage` stays the single clean expression (preludes are session
plumbing — part of what's *sent*, never what's *shown*). Reality check baked
into an integration test: the worker predefines NO variables (not even `x` —
PROBLEMS.md V0.5 was right; FRIENDLY-COMPILER.md's "predefines only x" aside is
slightly optimistic), and the always-declare policy covers that for free:
`integral t^2, t=0..2` → `8/3` with `t` visibly appearing in the live Symbols.

**Keyboard semantics (V1.4 subset of the V1.12 contract).**
- **Return** → evaluate (submit, draft clears).
- **Shift-Return** → newline *at the cursor* (the key handler deliberately
  ignores it so the text view inserts it).
- **⌘-Return** → evaluate WITHOUT advancing — submits the row, keeps the draft
  in place for iteration. Carried discoverably on the Sage menu ("Evaluate
  Without Advancing", ⌘↩, claims the key equivalent app-wide) with an
  in-editor fallback. Ambiguity initiated from ⌘↩ keeps the draft after the
  candidate is chosen (`PendingAmbiguity.advances`).
- **Up/Down** → history in single-line mode (`InputHistory`: the session's
  submitted inputs, consecutive duplicates collapsed, in-progress draft
  stashed on first Up and restored when you come back down past the newest).
  In a multiline draft the arrows keep moving the cursor — cursor-position
  detection isn't available to SwiftUI key handlers, so "Up at start of
  multiline" recall is a documented gap, not a behavior.
- The input field is a `TextEditor` + invisible sizing-mirror `Text` (grows
  with newlines/wrap to a 140pt ceiling, then scrolls). Documented deviation
  from the swiftui-pro preference for `TextField(axis: .vertical)`: the field
  editor can't do Shift-Return-inserts-at-cursor, which is the V1.4 contract.

**Generated-Sage disclosure.** `ShellModel.draftPreview` recompiles the draft
per keystroke (pure, microseconds) into a `DraftPreview`; `DraftPreviewLine`
renders it under the field at a stable reserved height (no pane jitter):
`.generated` → `↳ factor(x^4 - 1)` (callout mono, selectable), `.rawSage` → a
quiet "raw Sage" tag, `.issue` → orange-triangle + message + mono `Try: …`
suggestion (the same line a refused submission points at), `.ambiguous` → "N
possible readings — return offers the choices". Position-aware highlighting
inside the editor is deferred (the messages already quote the offending
fragment, which is the cheap version).

**Ambiguity picker.** `.ambiguous` puts a `PendingAmbiguity` on the model; a
popover anchored to the input pane lists one button per candidate (mono),
keyboard-first: Return = first reading (`.defaultAction`), digits 2–9 = the
rest, Esc cancels (draft kept), and focus returns to the input on dismissal
either way. The chosen candidate evaluates as a friendly submission of the
original raw input (required variables re-derived via the library heuristic).

**Gate.** `make check` ✓ · `make test` **163/163** (= 94 CasetteTests + the 69
lifted FriendlyCompilerTests; new suites: CompiledInput compile boundary ·
InputHistory · ShellModel input semantics incl. prelude wire-order over the
fake transport, ⌘↩, inline-error-no-submit, ambiguity round-trip · **Friendly
compiler integration vs real Sage 9.5**: `factor x^4 - 1` → symbolic with the
right factors; `double integral x*y, x=0..1, y=0..x` → **1/8**; `integral t^2,
t=0..2` → 8/3 with `t` in live symbols (prelude proven); ambiguous solve →
chosen candidate → `[x == (1/y)]`; compile error never reaches Sage and raw
`factorial(5)` → 120 right after) · `make build` ✓ (bundled worker.py
`cmp`-identical) · launched `build/Casette.app` via `open`: Sage booted, alive
30s+, AppleScript quit → `pgrep -fl "sage -python|worker.py"` **clean**.
**Full V0 regression, all green:** V0.1 **18/18** · V0.2 **35/35** · V0.3
**97/97** · V0.5 **88/88** · V0.6 **24/24** · V0.7 **69/69 + e2e 19/19** ·
V0.8 **95/95** · V0.9 **32/32** · V0.10 **21/21**. `pgrep` clean after
everything.

**Skill reviews applied.**
- **swiftui-pro:** logic on the model (`submit/resolveAmbiguity/recall*` are
  plain testable methods; key handlers call them and only translate to
  `KeyPress.Result`); views one-type-per-file (`InputEditor`,
  `DraftPreviewLine`, `AmbiguityPickerView`); button actions as method
  references; no `Binding(get:set:)`; `Text.foregroundStyle` concatenation for
  the mixed-voice error line. Accepted deviation (documented in code):
  `TextEditor` over `TextField(axis:)` for the keyboard contract.
- **macos-design:** popover (not a sheet) for the transient choice, anchored
  to the control it answers; keycap affordances surfaced ("⏎ evaluate ⇧⏎
  newline" fades in with content, "esc to keep editing" in the picker, per-
  candidate ↩/digit hints); ⌘↩ lives on a real menu for discoverability;
  preview/issue states differ by icon + text, never color alone.
- **typography-designer:** the preview line keeps the frozen two-axis system —
  Sage content at callout+mono one step under the title3 input; issue prose at
  caption default-face; `Try: …` suggestions at caption+mono (example input is
  code). New `Theme.Fonts.inputPreviewSage/Issue/Suggestion`; weight untouched
  (emphasis via .secondary/.tertiary + icon).

**Known gaps (deliberate).**
- Up-at-start-of-multiline doesn't recall history (no cursor introspection in
  SwiftUI key handlers); arrows are cursor keys whenever the draft has a
  newline. ~~If a recalled entry is itself multiline, edit it single-line (or
  clear) to resume navigating.~~ *(Superseded by the fix round: while
  navigation is in progress the arrows keep navigating, multiline recalled
  entries included; any edit ends navigation.)*
- Compile-error `position` isn't rendered as an in-editor caret/highlight —
  messages quote the offending fragment instead.
- History is session-scoped and in-memory (persistence is V1.9's business);
  the History sidebar tab still lists rows independently.
- `SessionRow.sage` records the generated expression only (not preludes) —
  honest for display; V1.9's replay should recompile from `input` to
  regenerate preludes (note left for it).
- LaTeX/plots/tracebacks still render as in V1.3 (V1.5/V1.7 territory).

**Live gate (PENDING — on-screen verifier checklist).**
1. Launch `build/Casette.app`; wait for **"Sage ready"**. Focus is in the
   input. The pane shows the placeholder and an empty preview strip.
2. Type `factor x^4 - 1` (don't submit): a mono preview line appears under
   the field reading `↳ factor(x^4 - 1)`; the "⏎ evaluate ⇧⏎ newline" hint
   fades in. Press **Return** → row evaluates to `(x^2 + 1)*(x + 1)*(x - 1)`
   (factor order may differ); the draft clears; the preview line empties.
3. Type `2+2`: preview shows the quiet **"raw Sage"** tag. Return → **4**.
4. Type `double integral x*y, x=0..1, y=0..x`: preview shows
   `integrate(integrate(x*y, (y, 0, x)), (x, 0, 1))`. Return → **1/8**.
5. Type `integral t^2, t=0..2`: Return → **8/3**, and the Symbols tab now
   lists `t` (the `var('t')` prelude is real). Select the row → Inspector's
   Generated Sage shows `integrate(t^2, (t, 0, 2))` (NO `var(` plumbing).
6. **Inline error:** type `integral x^2, x=0..` → orange ⚠ line: "Range
   `x=0..` is incomplete — missing the upper bound after `..`.  Complete it,
   e.g. `x=0..1`." Press Return **repeatedly** → NO row appears, the text
   stays put. Fix it to `x=0..1` → the preview flips to
   `integrate(x^2, (x, 0, 1))`, Return → **1/3**.
7. **Ambiguity:** type `solve x*y = 1`, preview reads "2 possible readings…".
   Return → a popover lists `solve(x*y == 1, x)` (hint ↩) and
   `solve(x*y == 1, y)` (hint 2). Press **Esc** → popover closes, draft
   intact, focus back in the field. Return again, press **2** → evaluates the
   y-reading → `[y == (1/x)]`; draft cleared.
8. **Shift-Return:** type `a = 5`, press **⇧⏎** — a newline appears (the field
   grows; nothing submitted), type `a * 9`, preview tag reads "raw Sage".
   Return → row shows **45** (multiline raw Sage reached Sage intact). Add
   ~8 lines — the field stops growing (~6 lines) and scrolls internally.
9. **⌘-Return:** type `factor x^6 - 1`, press **⌘⏎** → a row evaluates BUT
   the draft text stays in the field. Edit `6`→`8`, ⌘⏎ again → second row,
   draft still there. The Sage menu shows "Evaluate Without Advancing ⌘↩".
10. **History:** from that (single-line) draft press **Up** repeatedly — it
    recalls `factor x^8 - 1`, `factor x^6 - 1`, the multiline `a = 5⏎a * 9`,
    … back through every submitted input; **Down** walks forward and finally
    restores the draft you started from. Type something fresh without
    submitting, press Up then Down — your fresh text comes back. (On a
    recalled MULTILINE entry the arrows move the cursor instead — that's the
    documented single-line rule, not a bug.)
11. Dark mode: preview line, orange issue line, and popover all legible.
12. Quit (⌘Q); `pgrep -fl "sage -python|worker.py"` → empty.

**Next.** V1.5 — result rendering v1 (LaTeX cards on the tape; the expanded
card shows Input + Generated Sage — the `CompiledInput` split feeds it
directly).

---
