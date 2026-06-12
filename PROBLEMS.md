# Problems & Hard-Won Lessons

One entry per pattern lesson that cost real debugging. Newest at top.

---

## Restart re-init must CHAIN on the serial kernel queue — only the kill/boot itself may run un-chained, or the next submission races the fresh worker's preludes

**The symptom (V1.8 gate).** The pre-existing real-Sage test "x, y, z, t are
predefined at boot and after restart" — green at every prior gate — failed
during the V1.8 run: after `restartKernel()`, `expand((x+1)^2)` came back
`NameError: name 'x' is not defined`. The fresh worker existed, but the eval
beat the boot prelude to it. V1.8 didn't introduce the race; it widened the
window's *visibility* (a third parallel real-Sage suite raised machine load,
and V1.8 added a second post-restart re-init step — the session-precision
`config` op — to lose).

**The mechanism.** `restartKernel()` ran the WHOLE pipeline in one un-chained
`Task { restart(); evaluate(prelude); refreshSymbols() }` — un-chained
deliberately, because restart must preempt a stuck eval (chaining `restart()`
behind the kernel queue would deadlock behind the very eval it kills). But
user submissions enqueue on the serial `kernelQueue`, which knows nothing of
that Task: a submission typed right after ⌘⇧R could evaluate between the
fresh worker's boot and its prelude. Any "session state the worker holds"
(predefined variables, the V0.8 `precision_digits`) was silently absent for
that one eval — the kind of bug that looks like a flake forever.

**The fix — split the pipeline at the preemption boundary:**

```swift
let restart = Task { await controller.restart() }   // un-chained: preempts
enqueueKernelWork {                                  // chained: orders
    await restart.value
    _ = await controller.evaluate(Self.bootPrelude)
    if let digits = precisionNeedingReapply { _ = await controller.configure(...) }
    await refreshSymbols()
}
```

Only the kill/boot runs outside the queue (it signals; it never consumes the
wire). The RE-INIT rides the queue and awaits the restart first, so the next
submission deterministically evaluates after the fresh worker has its
calculator variables and session precision.

**Rules.**
1. Anything that must PREEMPT in-flight work runs un-chained; anything that
   must ORDER against future work runs on the queue. A restart pipeline is
   both — split it, don't pick one.
2. Worker-held session state (predefined vars, precision) must be re-applied
   on a path subsequent submissions are ordered BEHIND, or the first
   post-restart eval sees a half-initialized session.
3. A test for "after restart, X works" must first prove the restart pipeline
   COMPLETED via an observable that only the pipeline's LAST step changes
   (e.g. a sentinel symbol vanishing from the refreshed symbol table) —
   waiting on `kernelState` alone races, because the state was already
   `completed` before the restart began.

---

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

## A wrapping `fixedSize` Text OUTSIDE scroll content + `.windowResizability(.contentMinSize)` = the window's MIN HEIGHT balloons to ~1600pt the moment the view appears

**The symptom (V1.6 live gate).** Selecting a result row (which populates the
Actions sidebar tab) made the whole window instantly GROW to 1100×1598 — and
1598pt became a hard MINIMUM: AppleScript `set size`, macOS zoom-to-fit, and
manual resize all refused to shrink it. On a 967pt-tall display the bottom
~660pt of the window (input pane, sidebar footer) were permanently off-screen
and unreachable. Two verification rounds burned before the repro was pinned:
click a result row with the Actions tab visible → balloon.

**The mechanism.** The Actions tab pinned a hint under its List:
`VStack { List {...}; Text(hint).fixedSize(horizontal: false, vertical: true) }`.
With `.windowResizability(.contentMinSize)`, AppKit asks SwiftUI for the
content's minimum size, and that measurement proposes ~ZERO width. At zero
width the wrapping Text lays out one character per line — ~100 lines — and
`fixedSize(vertical: true)` makes that height a REQUIREMENT, not an ideal.
The window's min height becomes input-pane + tape-min + ~1500pt of
one-character-per-line hint text. Bisected by removing the Text (balloon
gone) and confirmed by the arithmetic.

**The fix + the rule.** Put wrapping helper text INSIDE the scrollable
content (a plain final List row, `.listRowSeparator(.hidden)`): scroll
content never participates in window min-size measurement, and a list row's
width proposal is always the real column width, so the text wraps correctly
at any sidebar width. General rules:
1. Under `.windowResizability(.contentMinSize)`, every NON-scrolling view in
   the window participates in the window's minimum size. A
   `fixedSize(horizontal: false, vertical: true)` Text is a min-height bomb
   there — its min height is its height at min width, which for wrapping
   text is absurd.
2. macOS `List` Section footers single-line-truncate at narrow widths (the
   original V1.6 defect), so the footer idiom isn't the answer either — an
   ordinary in-list row is.
3. When a window won't shrink, suspect content min size, and bisect the
   newest non-scrolling view. `set size of front window` via System Events
   is the cheap probe (it silently clamps to the real minimum).

---

## Parallel swift-testing + `setenv`: tests that pass config through process-global env race every test that reads it

**The symptom (V1.6 gate).** The frozen v0/10 suite — green at every prior
gate — failed once during the V1.6 regression:
`defaultDirectoryUsesApplicationSupportWhenNoOverride` saw a
`/tmp/casette-cfg-<UUID>/sessions` path where it expected the Application
Support default. Rerun: 21/21. `--no-parallel`: 21/21.

**The cause.** swift-testing runs a target's tests **in parallel inside one
process**, and environment variables are process-global. One test does
`setenv("CASETTE_CONFIG_DIR", override, 1)` (with a deferred `unsetenv`)
while the no-override test calls `unsetenv` and then reads the default — the
two interleave, and the no-override test observes its sibling's override.
The hermetic override that makes each test clean in isolation is exactly
what makes the suite racy in parallel.

**Rules.**
1. **Don't pass test configuration through `setenv`** — inject the path/value
   as a parameter (the SUT should take its config dir as an argument, with
   the env var consulted only at the production call site). If env mutation
   is unavoidable, mark the suite `.serialized`.
2. A test failure that names a SIBLING test's fixture (here: the other
   test's `/tmp/casette-cfg-` pattern) is a parallelism leak, not a logic
   bug — rerun serialized before touching code.
3. v0/ is frozen evidence, so the race stays documented rather than fixed
   there; V1.9's app-side persistence tests must follow rule 1.

---

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

## A macOS SwiftUI `.popover` is its OWN KEY WINDOW — keys reach neither it nor your editor; transient pickers over a focused text field must be INLINE same-window overlays

**The symptoms, across three fix rounds (V1.4).** The ambiguity picker as a
`.popover(item:)` anchored to the input pane:
- **Round 1** (buttons carried `keyboardShortcut`s): Esc did nothing,
  pressing `2` typed a literal "2" into the field, clearing the field left
  stale candidates showing. Mouse clicks worked.
- **Round 2** (keys moved to `onKeyPress` handlers on the focused
  `TextEditor`): with the popover up, Esc/Return/digits did nothing, a plain
  `z` was swallowed — ordinary key input reached NEITHER the popover NOR the
  text field — and clicking a candidate row stopped working too. Only
  ⌘A+Delete still reached the field.
- **Round 3** (inline overlay in place): everything worked EXCEPT Esc —
  digits/Return/click/type-through all fine, but Esc "never fired" on
  screen, through `.onKeyPress(.escape)`, `.onExitCommand`, AND a local
  NSEvent monitor across two more rounds. **That part was NOT an app bug —
  see "the environment eats Esc" below.** The local-monitor shape was then
  PROVEN correct by posting Esc directly to the app's pid.

Every unit test passed every round (172/172) — the model was fine. This is
window/focus plumbing, invisible to any test that doesn't put real key
events through real windows.

**The cause — deeper than round 1's diagnosis.** Presenting a macOS SwiftUI
`.popover` creates a SEPARATE window that becomes (or contends to become)
the KEY window. The moment it's up, the main window's `TextEditor` loses
first-responder status, so:
- `onKeyPress` handlers on the editor never fire (they live in the main
  window's responder chain, which no longer receives keys), and
- the popover side has no text field and no reliable shortcut routing of
  its own, so the keys die in between. Plain typing is swallowed whole.
Round 1's reading ("the popover is a passive overlay; focus stays in the
editor") was wrong — it explained the round-1 symptoms but predicted the
round-2 fix would work, and it didn't. There is no winning key-routing
arrangement with `.popover` here: whichever side you put the handlers on,
the other side's window has the focus story you needed.

**The robust shape — don't present a second window at all.** Render the
picker as an **inline overlay in the SAME window**: a conditional
`.overlay(alignment: .topLeading)` on the input pane, alignment-guided to
float just above it like an autocomplete/suggestion panel (material
background, rounded, shadow). Because it's the same window:
- the `TextEditor` keeps keyboard focus the entire time, so its
  `onKeyPress` routing (Return → first candidate, digits 2–9 → nth, any
  edit → dismiss via the model's `draft.didSet`) fires reliably;
- **except Esc — which is handled below the SwiftUI layer; the robust hook
  is an AppKit local NSEvent monitor.** Digits and Return arrive at the
  focused text view as ordinary key presses, but Escape is translated by
  the Cocoa key-binding system into the `cancelOperation:` ACTION before
  any `onKeyPress` can see it — so `.onKeyPress(.escape)` never fires; and
  the `NSTextView` backing `TextEditor` implements `cancelOperation:`
  itself, so `.onExitCommand` is unreliable over a focused editor. The
  proven shape (`EscapeInterceptor.swift`, verified by posting a real Esc
  keyDown to the app's pid and watching `cancelAmbiguity()` fire):
  `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` — fires BEFORE
  the window dispatches the key to the text view. On `keyCode == 53`
  (Esc), in the right window (`event.window === view.window`), with
  something actually pending, act and return `nil` (swallow the event);
  otherwise return the event unchanged so plain Esc keeps every default
  behavior (exiting full screen, etc.). Own the monitor with a tiny
  `NSViewRepresentable`-backed `NSView` — `viewDidMoveToWindow` installs
  it exactly once (guard on the stored token, so re-renders can't stack
  duplicates) and removes it on window detach, deinit as the backstop —
  and capture `self` weakly in the handler so the monitor never retains
  the view;
- plain `Button`s in the panel handle the mouse (no `keyboardShortcut`s on
  them — the editor owns the keys; macOS buttons don't grab key focus);
- appear/disappear is a plain structural conditional with NO transition —
  instant, and §1.1-safe (that rule is about *animated* insert/remove).
The model half of the round-1 fix was right and survives unchanged:
`cancelAmbiguity()` / `resolveAmbiguity(at:)` as plain testable methods,
and dismiss-on-edit via `draft.didSet` (so ⌘A+Delete, paste, and
programmatic inserts all dismiss — observe the data, not the keystrokes).

**Rules.**
1. **A transient picker over a focused text field (autocomplete,
   ambiguity, mention/emoji panels) must be an inline same-window overlay,
   never a `.popover`/sheet/window.** The whole interaction contract —
   "keep typing, Esc to keep editing, Return to take the suggestion" —
   depends on the field never losing first responder, and a second window
   guarantees it does.
2. Never advertise a key on ANY surface without proving the event reaches
   it on screen; key routing is unfalsifiable by unit tests.
3. "Dismiss the transient UI when its subject changes" belongs on the
   model (a `didSet` on the subject), or paste/⌘A-Delete paths leak stale UI.
4. **Esc over a focused text view is invisible to SwiftUI — intercept it
   with a local NSEvent monitor.** The key-binding system turns Esc into
   `cancelOperation:` before `.onKeyPress(.escape)` can fire, and the
   NSTextView consumes that action without forwarding it, so
   `.onExitCommand` is unreliable too.
   `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` sees the key
   first. Scope the behavior, not the monitor: swallow the event (return
   `nil`) only when there is actually something to cancel AND it's your
   window; pass everything else through untouched.

---

## THE AUTOMATION ENVIRONMENT EATS Esc — a session-wide filtering event tap consumes keyCode 53 before ANY app sees it; verify Esc via `CGEvent.postToPid`

**The symptom that burned two full fix/verify rounds (V1.4).** The inline
ambiguity panel's Esc-to-dismiss "failed on screen" through three different
implementations (`.onKeyPress(.escape)`, `.onExitCommand`, a local NSEvent
monitor) while every OTHER key worked. Instrumenting the local monitor
showed the truth: it logged every keyDown (letters, Return, digits) but a
pressed/injected **Esc produced NO keyDown event at all** — not in the app,
and not even in a `CGEventTapCreateForPid` tap on the app's process. Yet a
session-level head-insert tap DID see the Esc. Conclusion: something
between the session stream and per-app delivery consumes Esc system-wide.

**The culprit.** `CGGetEventTapList` showed an enabled session-wide
**FILTERING** tap on `keyDown` owned by the **computer-use automation
harness itself** (the `claude` process). The harness uses Esc as its abort
key and swallows every one — physical or injected, MCP `key` tool or
AppleScript `key code 53`. (A lurking
`com.apple.accessibility.universalAccessAuthWarn` panel was a red herring;
killing it changed nothing.) So **on this machine, no app can ever receive
Esc through normal injection — "Esc didn't work" in a computer-use
verification is evidence of NOTHING about the app.**

**The proof + the workaround.** `CGEvent(keyboardEventSource:…,
virtualKey: 53, keyDown:…).postToPid(appPid)` delivers straight to the
app's event queue, BELOW the session tap. With that, the app's
`EscapeInterceptor` fired immediately (`onEscape -> true`, panel
dismissed) — the round-4 code had been correct all along.
`scripts/send-key.swift <keycode> <pid>` is the reusable helper.

**Rules.**
1. When a key "doesn't work" under computer-use verification, FIRST prove
   the event reaches the process (temporary NSEvent-monitor logging, or a
   pid-level CGEvent tap) before touching app code. Key delivery has more
   layers than the responder chain: session filtering taps run before
   per-app routing.
2. On-screen verification of Esc-driven UI (and any key an automation
   harness might claim) must inject via `scripts/send-key.swift`
   (`CGEvent.postToPid`), not the MCP `key` tool or System Events.
3. V1.12 (keyboard pass) must use this for every shortcut it certifies —
   and treat any "key didn't fire" verdict as unproven until delivery is
   confirmed at the process boundary.

---

## The V0.7 friendly compiler FLATTENS NEWLINES — route multiline input around it, or raw Sage gets corrupted

**The trap (V1.4).** `FriendlyCompiler.compile` was written for one line of
input and begins by normalizing: `rawInput.replacingOccurrences(of: "\n",
with: " ")`. That's correct for its domain (friendly commands are single-line
forms), but V1.4 adds a multiline input field — and a multiline *raw Sage*
submission piped through the compiler comes back from `.bypass` with its
newlines flattened to spaces. Python/Sage is newline-sensitive, so
`a = 5⏎a * 9` silently becomes the syntax error `a = 5 a * 9`. The bypass
contract ("returned untouched") is broken by the normalizer before the bypass
decision is even made — and nothing fails loudly; the user just gets a
confusing SyntaxError row.

**The fix — decide multiline BEFORE the compiler.** In the app's compile
boundary (`CompiledInput.compile`): input containing a newline is raw Sage by
definition and bypasses without ever entering the library. No friendly form
is multiline, so nothing is lost; the frozen library stays byte-identical to
the v0/07 proof. **Rule: when lifting a single-line parser into a multiline
input surface, gate on the line count at the boundary — don't widen the
frozen parser's domain.** (Also reconfirmed while testing this: the worker's
star-import predefines NO symbolic variables — not even `x`, despite a stray
aside in FRIENDLY-COMPILER.md — so the always-declare `var('V')` prelude
policy is load-bearing for every friendly form, x included.)

---

## `posix_spawn` children INHERIT the parent's signal dispositions — spawn the worker with `POSIX_SPAWN_SETSIGDEF` + `SETSIGMASK` or interrupts silently die

**The symptom (V1.3).** The app's `SageKernel` — a faithful unification of
v0/09's proven `WorkerProcess`/`LineReader` — failed the integration tests:
SIGINT to the worker's real banner pid did **nothing**, every interrupt and
timeout escalated to the hard process-group kill, and `while True: pass` was
never answered with an `interrupted` envelope. Yet the *identical* spawn code
in `sage-doctor` (v0/09) interrupted fine on the same machine, and a Python
control (`os.kill(pid, SIGINT)` from a plain `python3` parent) interrupted in
0.00s. Same worker, same signal, same pid discipline — different parent.

**The cause.** A `posix_spawn`/`exec` child **inherits the parent's signal
mask and its ignored-signal dispositions** (`SIG_IGN` survives exec; handlers
reset to default). The swift-testing runner runs tests with SIGINT
ignored/masked, so the worker's Python started life with SIGINT ignored —
and **CPython does not install its `KeyboardInterrupt` handler (and cysignals
does not take ownership of SIGINT) when the signal arrives ignored from the
parent.** The SIGINT was delivered and discarded. v0/09 never saw this
because its parent was a plain CLI with default dispositions — the proof was
correct but the *parent context* was an untested variable. A GUI app parent
can have its own non-default dispositions too, so this is not just a
test-runner quirk.

**The fix — reset the child's signal world at spawn,** alongside
`POSIX_SPAWN_SETSID`:

```swift
var defaultSignals = sigset_t(); sigfillset(&defaultSignals)
posix_spawnattr_setsigdefault(&attributes, &defaultSignals)   // un-ignore all
var emptyMask = sigset_t(); sigemptyset(&emptyMask)
posix_spawnattr_setsigmask(&attributes, &emptyMask)           // unblock all
posix_spawnattr_setflags(&attributes,
    Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
```

With that, the full interrupt story works from inside the test runner AND the
app: SIGINT honored promptly (`interrupted` envelope), escalation still in
place for genuinely hostile code (`SIG_IGN` installed *by user code* is still
hard-killed). **Rule: any process-spawning code whose child must receive
signals resets dispositions and mask at spawn — never assume the parent's
signal state is default.** (Python's `start_new_session=True` path never hit
this because the harnesses' parents were vanilla `python3`.)

---

## Session persistence: a missing artifact is the NORMAL case, paths aren't identity, and peek the schema before decoding

**Three traps from V0.10 (session tape persistence-lite).**

**1. A restored plot artifact is essentially ALWAYS missing — model it as
expected, not as an error.** The worker saves plots into a session-scoped
`/tmp/sagecalc/session-<pid>-<rand>/` dir that **dies with the worker** (clean
shutdown rmtrees it; a crash leaves it for OS reaping — PROBLEMS.md V0.5). So on
the next app launch the worker that made the plot is gone and its dir with it: a
persisted artifact path almost never still exists. If restore treats a gone file
as a failure, **every** restored session with a plot looks broken. The fix is to
make `missing` a first-class liveness status resolved at load time: the row still
restores with its `plain` text and `kind:"plot"`, and an optional **replay
regenerates** fresh artifacts. Don't persist bytes; persist `{path, format, bytes,
status}` and re-resolve `status` against the filesystem on every load.

**2. Artifact PATHS are not result identity — a fresh worker writes new paths
every run.** To decide "did a replayed result differ from the cached one?" (the
supersede policy), the obvious move is to compare the two persisted envelopes for
equality. **Wrong for any plot:** replay spawns a fresh worker whose
`/tmp/sagecalc/session-<newpid>-<newrand>/` dir gives **every** artifact a new
path, so a path-sensitive `==` flags every plot row as "superseded" on every
replay. The difference check must compare what's *semantically* the result —
`kind` / `plain` / `latex` / `approx` and the artifact **format set** — and
explicitly **ignore paths**. Then a deterministic tape (`1/3+1/5`→`8/15`) shows
zero spurious supersession; only the provenance flips `cached → replayed`.

**3. Peek `schemaVersion` BEFORE the strict `Codable` decode, or a future file
gets mis-quarantined as "corrupt."** Robust load has three failure modes: corrupt
JSON (quarantine + start fresh), unknown/newer schema (refuse politely, leave the
file intact for a newer app), empty/missing (fresh). But a forward-incompatible
*future* shape would **also fail strict decoding** — so if you decide
corrupt-vs-version-mismatch by "did `JSONDecoder` throw?", a newer file is wrongly
quarantined and lost. Fix: read just the top-level `schemaVersion` with
`JSONSerialization` *first*; if it isn't the supported version, return
`.refusedSchema` (file untouched) and never reach the strict decode. Only a file
that parses as JSON-with-a-known-version but then fails `Codable` is truly
corrupt. (Also: don't quarantine an **empty** file — an empty isn't corrupt, it's
"no session yet" → fresh.)

**Corollary — `FileManager` is not `Sendable` (Swift 6).** A `struct` that stores
a `FileManager` can't conform to `Sendable` under strict concurrency. The
`SessionStore` doesn't need `Sendable`, so drop the conformance rather than fight
it. And a top-level CLI `let` is `@MainActor`-isolated, so free helper functions
that touch it must take it as a parameter, not reference it as a global.

## Swift process control: `Foundation.Process` can't `setsid` — drop to `posix_spawn`, and an explicit override must fail loud

**The context (V0.9).** Sage Doctor is the first time the **parent side** is
written in Swift (the V1.3 `SageKernel` dry run), so every PROBLEMS.md process
lesson learned in Python (`controller.py`) had to be re-proven in Swift. Three
Swift-specific traps.

**1. `Foundation.Process` has no `start_new_session` equivalent — use
`posix_spawn` with `POSIX_SPAWN_SETSID`.** The whole orphan-avoidance strategy
(kill the *group*, because `sage` is a bash wrapper that fork-execs the real
worker) depends on putting the child in its **own session / process group** so
`killpg` reaps the wrapper AND the worker together. Python does this with
`subprocess.Popen(..., start_new_session=True)`. Swift's `Process` **exposes no
such knob** (no `setsid`, no pre-exec hook). The fix is to skip `Process`
entirely and call `posix_spawn` directly:

```swift
var attributes = posix_spawnattr_t(nil as OpaquePointer?)
posix_spawnattr_init(&attributes)
posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))  // == start_new_session
// ... posix_spawn_file_actions_adddup2 for stdin/stdout, addopen /dev/null for stderr ...
posix_spawn(&pid, sagePath, &fileActions, &attributes, argv, environ)
```

Then hard-kill is `killpg(getpgid(pid), SIGKILL)` and interrupt is
`kill(realPID, SIGINT)` to the banner pid — identical semantics to the Python
controller. **Proven:** after the full doctor run (incl. interrupt + restart) and
after a deliberate hang-at-boot fixture (`hang-sage.sh` that `sleep`s instead of
emitting the ready banner, *and* forks a child to mirror the wrapper→worker tree),
`pgrep -fl "sage -python|worker.py|sleep 100000"` is **clean**. Killing only the
spawned (wrapper) pid would have orphaned the worker — the V0.1 trap, now also
closed in Swift.

**2. Boot-failure must hard-kill before returning, or a hung wrapper leaks.** The
`start()` path waits for the ready banner with a timeout. On timeout (hang at
boot) the natural thing is to `throw` — but the wrapper + its children are still
alive. The fix: `hardKill()` (process-group SIGKILL) in the failure branch
*before* throwing. This is what makes the hang-at-boot case orphan-clean.

**3. SIGINT delivery + pipe draining: one reader thread, single consumer.** A
dedicated reader thread (`LineReader`) drains the worker's stdout fd with raw
`read()` into a lock-guarded queue, splitting on `\n` and parsing JSONL; the
control thread is the **sole consumer** via an `NSCondition` wait-with-deadline.
This mirrors `controller.py`'s "evaluate is the sole queue consumer; cancel only
signals" rule — so a SIGINT/await never races the response off the queue. Each
`WorkerProcess` owns exactly one `LineReader`, so a killed generation's reader
can't trip a fresh worker's state (the restart-race lesson). The interrupt is
prompt because we **never reinstall a SIGINT handler** in the worker — cysignals
stays in charge (the V0.2 lesson) — and Swift just `kill(realPID, SIGINT)`s the
banner pid. Verified: `while True: pass` interrupted → `interrupted` envelope;
escalation-to-killpg path is in place for a swallowed SIGINT.

**4. An explicit `--sage PATH` that doesn't exist must fail LOUDLY.** First cut:
discovery records the non-existent override as a candidate and falls through to
the next existing one — so `--sage /no/such/sage` *silently ran the real Sage*,
masking the user's typo. Wrong: an explicit override is the user asking for *that*
binary. The fix is a guard in `SageDoctor.run`: if an override is given and it
doesn't exist, return a `Discovery: FAIL` with an actionable message, never fall
through. (Auto-discovery with *no* override still falls through normally.)

---

## Exactness: the Symbolic Ring is uniformly `is_exact()==False` — decide per-kind, and tree-walk symbolic

**The trap (V0.8).** To put an `exact: true|false|null` flag on a result, the
obvious move is `value.parent().is_exact()`. **It is wrong for the most important
case.** The **entire Sage Symbolic Ring reports `parent().is_exact() == False`**:

```
sqrt(2).parent().is_exact()   -> False
pi.parent().is_exact()        -> False
sin(1).parent().is_exact()    -> False
```

So a `parent().is_exact()`-based flag labels `sqrt(2)`, `pi`, and `sin(1)` —
all **mathematically exact** symbolic values — as *inexact*. That's exactly
backwards for the spec, whose whole point is "exact primary, approximation
secondary."

**The fix — decide exactness PER KIND, and walk symbolic expressions:**

- `integer` / `rational` → **`true`** (exact rings).
- `real` / `complex` → **`false`** (a float-backed `RealLiteral` from `2.5`, a
  `RealNumber` from `N(...)`, an mpc — approximate by nature).
- `symbolic` → **`true` unless the expression tree contains an inexact numeric
  atom.** Walk via `.operands()`; a leaf is inexact iff `leaf.is_numeric()` and
  `leaf.pyobject().parent().is_exact()` is False. This cleanly separates
  `sqrt(2)+pi` (exact) from `2.5+sqrt(2)` and `1.5*x` (inexact, contain a float
  literal). `is_numeric()` alone is not enough — `SR(2.5)` is numeric *and*
  inexact, while `integrate(x^2,(x,0,1))` is numeric (it's `1/3`) *and* exact.
- matrix / list / relation / plot / text / boolean / none / error / unknown →
  **`null`** (exactness isn't a scalar property of these).

**`sin(1)` is the headline trap and it generalizes.** Sage keeps `sin(1)`
**symbolic and exact** — it does NOT evaluate to `0.841…`. This is the same
shape as the V0.7 handoff (a definite integral / limit is `kind:"symbolic"` yet
exact, with the exact value in `plain` and the float in `approx`). **Rule for
any exact/numeric logic: never key "is this exact?" off the kind being
`rational`/`real`. A `symbolic` result can be a fully exact number.**

---

## Numeric precision: clamp the request to the value's own `prec()` or `.n(bits)` raises

**The trap (V0.8, extends the V0.3 `digits=` lesson).** To approximate a value to
N decimal digits you convert to bits (`ceil(N*log2(10))`) and call `.n(bits)`.
But a **concrete** real/complex has a *fixed native precision*, and asking for
MORE bits than it holds raises:

```
CC(3,4).n(digits=15)  -> TypeError: cannot approximate to a precision of 54 bits,
                          use at most 53 bits
```

A configurable-precision feature WILL ask for arbitrary digit counts, so this
fires in normal use (e.g. "show this 53-bit result to 40 digits"). The V0.3
work-around was "use `str(value)` for concrete reals" — but that can't honor a
request for *fewer* digits (show `N(sqrt(2),digits=50)` at 10).

**The fix — one path that clamps:** if the value has a `prec()`, request
`min(bits_wanted, value.prec())` bits; otherwise (rational / symbolic-constant)
pass the full requested `digits=`. So:

- `N(sqrt(2),digits=50)` (170 bits) asked for 10 digits → 10 digits, no raise,
  and the **stored** object is never downcast.
- `CC(3,4)` (53 bits) asked for 40 digits → clamped to 53, no raise.
- `8/15` (exact rational) asked for 20 digits → full 20 digits.

**Force-numeric must be display-only, or it pollutes the namespace.** The
temptation is to `N()` the assignment. Don't: evaluate normally (so `y = 1/3`
stores an exact `Rational`), then apply `N()` only to the *echoed* value for
display. Namespace isolation then needs zero extra machinery — the next normal
eval of `y` is exactly `1/3` and `parent(y)` is still `Rational Field`.

---

## Friendly compiler: the bypass rule is a SPACE boundary, and a definite integral is `symbolic`

**Two traps from V0.7 (the friendly input compiler).**

**1. "Command word + space → friendly" must check the space boundary, or
`factorial(5)` compiles as a `factor` command.** The bypass rule is the whole
design: a line is friendly iff it begins with a known command word that is *either
the entire input OR immediately followed by whitespace*; everything else is raw
Sage, returned untouched. The boundary check is load-bearing — without it,
`factorial(...)`, `expandable`, `plotting_helper(...)`, and `factor(x^4-1)` (an
already-valid Sage call) would all be mis-claimed by a `hasPrefix` match and
mangled. With it, they all correctly **bypass**:
- `factor x^4 - 1` → friendly (space after `factor`).
- `factor(x^4-1)` → bypass (`(`, not a space — already a call).
- `factorial(5)` → bypass (no boundary after `factor`).
This makes the shim **purely additive**: anything unrecognized is the user's own
Sage, so progressive disclosure to raw Sage costs nothing. Implement command
matching as "longest phrase wins" too, so `double integral` beats `integral`.

**2. A definite integral / limit is `kind:"symbolic"`, NOT `rational`/`real`.**
`integrate(x^2, (x, 0, 1))` returns `1/3` and `limit(sin(x)/x, x=0)` returns `1` —
but as **symbolic-ring** elements (`sage.symbolic.expression`), so V0.3's
`_classify` lands them in `symbolic`, not `rational`/`real`. The exact value is in
`plain` (`1/8`, `1`), the float in `approx` (`0.125`). The first V0.7 e2e run
"failed" three cases because the *test* assumed `rational`/`real` — the compiler
and worker were both right. **Lesson for V0.8 (exact/numeric):** don't key
"is this exact?" off the kind being `rational`/`real`; a `symbolic` result can be
a fully exact number, with its exact form in `plain` and the approximation in
`approx`. Don't coerce it to a float by default.

**Corollary — report required variables, don't inject `var(...)`.** The worker's
`from sage.all import *` predefines only `x` (see the V0.5 plot lesson below), so
`integrate(x^2, x)` over an undeclared `x`... actually works for `x`, but
`plot(sin(t), …)` over `t` does not. The compiler therefore *reports*
`requiredVariables` and leaves declaration to the caller (V1.4 emits `var('V')`
preludes). Keeping `var(...)` out of the generated Sage also keeps the "Generated
Sage" string clean to show the user.

---

## Symbol table: diff the baseline by OBJECT IDENTITY, not name — Sage exports `n`/`N`/`i`

**The trap (V0.6).** The `symbols` op shows only user-created bindings, so it
diffs the live namespace against a baseline snapshotted before any user code
(everything `from sage.all import *` injects). The obvious diff is by **name**:
"surface a name that isn't in the baseline." That's **wrong**, and it fails on a
spec test case.

`from sage.all import *` exports a bunch of **very common single-letter variable
names** as builtins:

- **`n`** is `numerical_approx` (a function).
- **`N`** is also `numerical_approx`.
- **`i`** is the Gaussian unit (a `NumberFieldElement_gaussian`).

So when the spec does `n = 104729`, the name `n` was *already in the baseline* —
a name-only diff hides it. The first harness run was **20/24** for exactly this:
`n` never appeared, and its reassignments couldn't be tested. (Other names a user
will reach for — `N`, `i`, and depending on imports more — hit the same wall.)

**The fix.** Snapshot the baseline **objects** (`_SYMBOL_BASELINE = dict(NS)`)
and surface a name iff it is **absent** from the baseline OR **rebound to a
different object** (`live_value is not baseline_obj`). The identity check catches
"user reassigned a name Sage already used" while still hiding the untouched
builtins. Brand-new names (the common case) surface trivially.

**Two corollaries that matter:**
1. **Retain the objects, not their `id()`s.** If the baseline stored only
   `id()` integers, a freed baseline object's id could be **recycled** by a later
   user object bound to that same name, and an id-equality check would wrongly
   *hide* the user's symbol. Holding the actual objects and using `is` is exact
   and immune to id reuse.
2. **`del n` then re-check works for free.** `del n` removes the user binding
   entirely (it does *not* restore Sage's `numerical_approx`), so the name is
   simply gone from `NS` and the op omits it — no special-casing.

**Bounded summaries are also CHEAP summaries — by being structural.** The other
half of the op's safety is never stringifying a large object. The lever is to
summarize from **metadata**: a matrix → `"<r>×<c> over <base ring>"` from
`nrows/ncols/base_ring` (microseconds), a container → `"list of N items"` from
`len` (microseconds) — *not* `str(value)`. Measured: a 200×200 matrix and a
million-item list summarize in ~1e-5 s each, vs `str()` at ~0.05 s and megabytes;
the whole `symbols` op over both returns in ~0.6 ms. So "don't put 7.9 MB on the
wire" and "don't take 50 ms" are the **same fix**. (And wrap every summary in a
`try/except` → `"<unprintable: ExcType>"`, because a user object's `__repr__`
can raise.)

---

## Plot artifacts: macOS `NSImage` loads matplotlib SVG but renders it as a black blob — use PNG

**The trap (V0.5).** Sage 9.5 saves a 2D plot to **SVG, PNG, and PDF** cleanly
(all three verified: SVG ~20 KB, PNG ~19 KB, PDF ~7 KB, valid headers). The
worker saves SVG+PNG. On the macOS render side, the obvious win is SVG (vector,
crisp at any zoom) — and `NSImage(contentsOf:)` **does** load these SVGs: it
returns a non-nil image with a sane size (`453×337`) via the system
`_NSSVGImageRep`. Looks like SVG "just works."

**It does not.** On screen, the SVG renders the **curve correctly** but paints a
**large opaque black blob** (shaped like the digits of the axis labels) over the
plot. Cause: matplotlib emits text (tick labels, axis numbers) as `<use>`
references to glyph `<path>`s defined in `<defs>`. The system `_NSSVGImageRep`
mishandles that pattern and fills the whole glyph-def region black instead of
placing individual glyphs. Verified on screen and at zoom — the blob is
unmistakable, and identical across rows. **Not a crash** (the app renders what
NSImage hands back), just wrong.

**PNG is flawless.** `NSBitmapImageRep` decodes the matplotlib PNG perfectly —
clean antialiased curve, readable axis labels, crisp at row size and zoomed.

**Rules.**
1. **Render PNG, not SVG, on this stack.** The worker saves both; the UI should
   default to PNG. Keep the SVG file for later (export, vector zoom) but only
   render it through a *real* SVG engine (a third-party SwiftUI SVG renderer, or
   rasterize via WebKit / `librsvg`), never bare `NSImage`.
2. **`NSImage` loading an SVG without returning nil is NOT proof it renders
   right.** It silently produces a wrong raster. The only check that catches this
   is the on-screen one (SWIFTUI-RULES §9 again: a passing load is not a passing
   render). Build the proof viewer with a per-row SVG/PNG toggle so the
   corruption is visible side-by-side.
3. **Saved-but-wrong vs failed-to-save are different.** Our save path treats a
   `.save()` exception as a structured per-format artifact error; but a format
   that *saves fine and renders wrong* (SVG here) passes every file-level
   assertion (exists, nonempty, parses as SVG) — only the eyeball test fails it.

**Headless `.show()`.** In a worker there is no display. `Graphics.show()` under
Sage's TkAgg backend didn't pop a window here, but relying on that is fragile —
wrap `Graphics.show` / `GraphicsArray.show` to **capture the plot as an
artifact** instead. Bonus: it's the clean way to get *multiple* plots out of one
eval (`p.show(); q.show()`), since the REPL echo only returns the last
expression.

**`from sage.all import *` does NOT predefine `x`.** The interactive Sage REPL
injects `x` (and friends) as a symbolic var; a bare star-import into the worker's
namespace does not. `plot(sin(x), …)` in the worker raises
`NameError: name 'x' is not defined` unless the caller did `x = var('x')` first.
(Already noted in WORKER-PROTOCOL; it bit the V0.5 harness until it declared
`x, y, t = var('x y t')`.)

---

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

## Classifying Sage results: type module lies in three specific ways

Building the V0.3 result classifier (`worker._classify`), three Sage types refused
to land where their math suggested. Key off `type(value).__module__`, but special-case:

1. **`3 + 4*I` is not a complex — it's a number-field element.** Its type is
   `NumberFieldElement_gaussian` in `sage.rings.number_field.number_field_element_quadratic`
   — it's an element of `QQ[i]`, *not* under `sage.rings.complex*`. A naive
   `"sage.rings.complex" in mod` check misses every Gaussian literal. Fix: add an
   explicit branch for `number_field` modules whose type name is Gaussian/Cyclotomic.

2. **`solve(...)` returns a `Sequence_generic`, not a list.** Type is
   `sage.structure.sequence.Sequence_generic`. It *subclasses* `list`, though, so an
   `isinstance(value, (list, tuple))` branch catches it (lands as `list`) — but only
   if that branch exists *and* runs after the Sage-module checks. Don't assume
   `type(...).__module__ == 'builtins'` for list-likes.

3. **`bool` is an `int` subclass.** `isinstance(True, int)` is `True`, so you must
   test `boolean` *before* `integer` or `True`/`False` classify as integers.

Corollary: **unknowns still render LaTeX.** A `Permutation` is `kind:"unknown"` yet
`latex(value)` happily returns `[2, 1, 3]`. So compute `latex` best-effort for every
kind, not just the math ones; it just returns `None` when Sage can't.

---

## Numeric approximation: respect the value's native precision; `digits=` can raise

For the envelope's `approx` field, the obvious `value.n(digits=15)` has two traps:

- **It downcasts high-precision reals.** `N(sqrt(2), digits=50)` is a 50-digit
  `RealNumber`; `.n(digits=15)` quietly truncates it back to 53-bit, throwing away
  the precision the user explicitly asked for. For a value that's *already* a
  concrete real/complex, use `str(value)` (its native decimal); only call `.n()` for
  things that need approximating (rationals, symbolic constants).
- **`digits=` can raise on an already-low-precision object.** `CC(3,4).n(digits=15)`
  raises `TypeError: cannot approximate to a precision of 54 bits, use at most 53
  bits` — 15 decimal digits ⇒ 54 bits > the object's 53. Use **no `digits=` arg**
  (native precision) and the call succeeds.

Also: `approx` must be **per-kind**, not blind. `value.n()` on a matrix returns a
*matrix of floats* (not a scalar), and on a symbolic expr with free variables
(`x^2+5*x+6`) raises `TypeError`. Gate it: only rational/real/complex/symbolic, and
for symbolic only when `value.variables()` is empty.

---

## Interrupting Sage: cysignals owns SIGINT and makes C code abortable — don't clobber it

**The question (V0.2 spec): does SIGINT reach mid-computation Sage? Does it abort
C-level loops?** Answer, measured: **yes, promptly — but only because of
cysignals, and only if you don't overwrite its handler.**

**What's actually installed.** After `from sage.all import *`, the process's
SIGINT handler is **`cysignals.python_check_interrupt`** (a cyfunction), *not*
whatever Python handler you set. cysignals wraps Sage C/Cython in
`sig_on()`/`sig_off()` and, on SIGINT, longjmps out of the C frame at the next
interrupt check, raising `KeyboardInterrupt`. So `factorial(10^8)` — which runs
**>60s** uninterrupted — is **aborted at +3.00s** when SIGINT arrives. Verified in
the real worker.

**The trap that produced a 23-second deferral.** If you install your own
`signal.signal(signal.SIGINT, handler)` *after* the Sage import, you **clobber
cysignals' handler** and revert to plain-Python signal semantics: the handler only
runs between bytecode instructions, and a long GMP/C call never yields, so the
`KeyboardInterrupt` is deferred until the C call *returns* — measured at **+23s**
for `factorial(10^8)`. Same computation, same SIGINT, prompt vs 23s, decided
purely by *whose* SIGINT handler is in place.

**Rules.**
1. Let cysignals own SIGINT. Your worker's handler is a harmless fallback it
   supersedes (and it still raises `KeyboardInterrupt`, which your eval loop
   catches → `interrupted` envelope).
2. **Never assume SIGINT lands.** Sage code not wrapped in `sig_on/sig_off`, user
   code that does `signal.signal(SIGINT, SIG_IGN)`, or a tight pure-C loop with no
   check will swallow it. The parent must **escalate SIGINT → hard
   process-group kill** after a grace window. (Spec policy: brutal restart is OK.)
3. Send SIGINT to the worker's **real pid** (from the ready banner); hard-kill the
   whole **process group** (`os.killpg`) — see the wrapper lesson below.

---

## Restart race: give each worker generation its own reader queue + EOF event

**Symptom.** Right after a hard-kill + `restart()`, the *fresh* worker raised
"worker never became ready" in ~0.2s — far too fast to be a real boot failure. A
clean standalone boot took ~3s and worked.

**Cause.** The controller shared one `self._eof` event and reader thread across
worker generations. On restart, the **old** reader thread (still draining the dead
worker's pipe) hit EOF and ran `self._eof.set()` — tripping the flag the **new**
worker's startup was watching. The new worker looked like it crashed on boot.

**Fix.** Make the reader thread a `@staticmethod` that takes *its* queue and *its*
EOF event as arguments, created fresh in `start()` for each generation. A stale
reader can then only set its own (now-ignored) event.

```python
self._q = queue.Queue(); self._eof = threading.Event()
threading.Thread(target=self._read_loop,
                 args=(self.proc.stdout, self._q, self._eof), daemon=True).start()
```

**Related:** never let two threads drain the one response queue. First cut had
`interrupt()` and `evaluate()` both calling the queue reader, so the interrupt
response got consumed by the wrong waiter and `interrupt()` spuriously "timed out."
Make `evaluate` the **sole** queue consumer; cancel/timeout only *signal* (set a
`threading.Event` the eval loop watches), never read.

---

## `sage -python` is a bash wrapper — kill the process *group*, not the PID

**Symptom.** Sent `SIGKILL` to the `subprocess.Popen` PID of
`sage -python worker.py`, then the "worker is dead" check kept failing: the
worker still returned a valid response to the next request.

**Cause.** `/usr/local/bin/sage` is a **bash script**. `sage -python …`
fork-execs the real Python worker as a *child* of that bash wrapper. The
Popen PID is the wrapper; the worker is its child and **inherited the same
stdin/stdout pipe fds**. Killing the wrapper orphans the worker (reparented to
launchd/init) and it keeps reading/writing the pipe, so the parent sees no EOF.

Observed tree:

```
51932  bash /usr/local/bin/sage -python …/worker.py   <- Popen PID
51933    python3 …/worker.py                            <- real worker (child)
```

**Fix.** Launch the worker in its own session/process group and signal the
whole group:

```python
proc = subprocess.Popen([...], start_new_session=True, ...)
os.killpg(os.getpgid(proc.pid), signal.SIGKILL)   # wrapper + worker together
```

The real app's `SageKernel` (V1.3) and the lifecycle work (V0.2) **must** do
this; killing only the PID will leak orphaned Sage workers.

---

## Protocol stdout must use a *private dup'd fd*, and capture must redirect fd 1/2 (not just `sys.stdout`)

**Hazard (called out in the V0.1 spec).** If the worker writes protocol JSON to
the same stdout that user code prints to, `print("hello")` — or worse, a
Cython/C library writing straight to fd 1 — corrupts the JSONL stream and
desyncs the parser.

**Fix that works (`worker.py`).**
1. At startup, **before** importing Sage or running anything, dup the real
   stdout/stderr to private fds (`os.dup(1)`, `os.dup(2)`) and write *all*
   protocol output there. Nothing user code does can reach those fds by name.
2. During each eval, redirect **both** layers into capture buffers:
   - Python level: `contextlib.redirect_stdout/redirect_stderr` (catches
     `print`).
   - **OS level: `os.dup2(pipe_w, 1)` / `os.dup2(pipe_w, 2)`** (catches raw
     `os.write(1, …)` and Cython/C writes). Drain the pipes non-blocking after
     restoring the fds and fold the text into `stdout`/`stderr`.

`contextlib.redirect_stdout` alone is **not** enough — it only swaps the
Python `sys.stdout` object; C-level writes to fd 1 sail right past it. Verified
with `os.write(1, b"RAW1\n")`: captured into the envelope, framing intact.

---

## Sage value-echo: parse the *preparsed* code with `ast`, and suppress `None`

To mimic the REPL ("last expression prints its value"), parse the **preparsed**
source (not the raw source) with `ast`, exec all leading statements, and `eval`
the final node only if it's an `ast.Expr`. Suppress a `None` result so a bare
`print(...)` or an assignment echoes nothing (`kind:"none"`, `value:false`) —
otherwise `print("hello")` wrongly reports `plain:"None"`.

Note: in Sage 9.5, `factor(x^4 - 1)` returns `(x^2 + 1)*(x + 1)*(x - 1)`
(ordering differs from the spec's illustrative `(x - 1)*(x + 1)*(x^2 + 1)` —
mathematically identical; don't hard-code string equality on factor output).
