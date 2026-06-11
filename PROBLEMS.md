# Problems & Hard-Won Lessons

One entry per pattern lesson that cost real debugging. Newest at top.

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

**Trap 2 — sizing.** `MTMathUILabel` is an `NSView`. Dropped into a SwiftUI layout
naively, it reports no useful size and **collapses to zero height**, so tall glyphs
(∫, ∑, matrices, fractions) overlap the row's caption above and plain line below.
Fix: in the `NSViewRepresentable`, implement `sizeThatFits(_:nsView:context:)` and
return `MTMathUILabel.intrinsicContentSize` (which SwiftMath overrides to the
rendered math size) plus a few points of vertical margin. (`MTMathUILabel` has no
`sizeThatFits` method on macOS — use `intrinsicContentSize`.)

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
