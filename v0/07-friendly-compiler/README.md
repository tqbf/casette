# V0.7 — Friendly Input Compiler

A **command shim, not a language.** A pure Swift library (`FriendlyCompiler`) that
turns a small set of forgiving command forms into Sage source, plus a CLI
(`sagecalc-compile`) and a swift-testing suite. Written in Swift (not Python)
because V1.4 must compile friendly input → Sage **synchronously on every
keystroke/submit** to show "Generated Sage" *before/without* evaluating —
round-tripping through the Python worker for that would be absurd.

The library is **pure**: `String in → CompileResult out`, no I/O, no globals. It
is the surviving artifact, written to migrate into the app.

## Build & run

```bash
swift build
swift run sagecalc-compile "double integral x*y, x=0..1, y=0..x"
#   integrate(integrate(x*y, (y, 0, x)), (x, 0, 1))

swift run sagecalc-compile --json "integral x^2, x=0..1"
#   {"input":"...","requiredVariables":["x"],"sage":"integrate(x^2, (x, 0, 1))","status":"success"}
```

## Three test layers (all executed)

1. **`swift test`** — 69 unit tests, 9 suites: every spec'd form, every error
   case, bypass cases, the double-integral nesting, weird spacing/casing,
   synonyms, required-variable inference, no-implicit-multiplication.
2. **CLI smoke** — `sagecalc-compile "<input>"` prints the Sage; `--json` for
   tooling.
3. **End-to-end** — `python3 e2e.py` pipes **every** generated Sage string through
   the **real canonical worker** (`../01-worker-protocol/worker.py`), applying the
   variable policy exactly as V1.4 will (declare `var('x')` preludes from
   `requiredVariables`), and asserts `ok:true` + sensible kinds (solve → list,
   eigenvalues → list, plot → plot + artifacts, …). **19/19 checks**, incl. the
   double integral evaluating to `1/8` and the wire staying intact.

## The compile result (the contract V1.4 consumes)

```swift
enum CompileResult {
  case success(generatedSage: String, requiredVariables: [String])
  case bypass(rawSage: String)                 // raw Sage passes through untouched
  case error(CompileError)                     // {message, position?, suggestion?}
  case ambiguous(candidates: [String])         // genuinely ambiguous → offer choices
}
```

## Accepted forms (the whole grammar)

| Friendly input | Generated Sage |
| --- | --- |
| `factor x^4 - 1` | `factor(x^4 - 1)` |
| `expand (x + 1)^5` | `expand((x + 1)^5)` |
| `simplify sin(x)^2 + cos(x)^2` | `(sin(x)^2 + cos(x)^2).simplify_full()` |
| `solve x^2 + 5*x + 6 = 0` | `solve(x^2 + 5*x + 6 == 0, x)` |
| `solve … = 0 for x` | `solve(… == 0, x)` |
| `derivative sin(x^2)` | `derivative(sin(x^2), x)` |
| `derivative sin(x^2) wrt x` | `derivative(sin(x^2), x)` |
| `integral x^2` | `integrate(x^2, x)` |
| `integral x^2, x=0..1` | `integrate(x^2, (x, 0, 1))` |
| `double integral x*y, x=0..1, y=0..x` | `integrate(integrate(x*y, (y, 0, x)), (x, 0, 1))` |
| `limit sin(x)/x, x->0` | `limit(sin(x)/x, x=0)` |
| `taylor sin(x), x=0, order=7` | `taylor(sin(x), x, 0, 7)` |
| `plot sin(x), x=-pi..pi` | `plot(sin(x), (x, -pi, pi))` |
| `matrix [[1,2],[3,4]]` | `matrix([[1,2],[3,4]])` |
| `eigenvalues [[1,2],[3,4]]` | `matrix([[1,2],[3,4]]).eigenvalues()` |
| `rref [[1,2],[3,4]]` | `matrix([[1,2],[3,4]]).rref()` |

Synonyms: `diff`→derivative, `integrate`→integral, `double integrate`→double
integral, `eigenvalue`→eigenvalues. Commands are case-insensitive.

**Double-integral nesting** (load-bearing): the **inner** integral binds the
**last** range and the **outer** the **first** — `x=0..1, y=0..x` →
`integrate(integrate(…, (y,0,x)), (x,0,1))`. The inner `y` bound may reference the
outer `x` (`y=0..x`); we never reorder or rewrite the bound expressions.

## Bypass rule

A line is **friendly** iff it begins with a known command word that is *either the
entire input or immediately followed by whitespace*. Otherwise it **bypasses** as
raw Sage, returned untouched. Consequences:

- `factor x^4 - 1` → friendly. `factor(x^4-1)` (already a call) → **bypass**.
  `factorial(5)` (starts with `factor`, no space) → **bypass**.
- `2+2`, `sin(pi/3)`, `A = matrix([[1,2],[3,4]])`, `x.diff()` → **bypass**.
- An unknown leading word (`foobar x^2`) → **bypass**.

This makes the shim purely additive: anything it doesn't recognize is the user's
own Sage, and progressive disclosure to raw Sage is free.

## Variable policy

The compiler **reports** the free variables a form needs but **never injects**
declarations — the generated Sage is a single expression. `requiredVariables` is
inferred by scanning the expression for bare identifiers not followed by `(`
(so not function calls) and not reserved (`pi e I oo …`, common builtins), plus
any command-bound variable (the integration/plot variable). Order is
command-bound-first (outer, then inner for a double integral), then body order.

**The decision for V1.4:** emit a `var('x')` prelude for each required variable
before evaluating the generated Sage in the session — this is exactly what
`e2e.py` does and proves end-to-end. (Alternative: trust the session if the var is
already declared. Reporting them, rather than baking `var(...)` into the
expression, keeps "Generated Sage" clean to show the user and lets V1.4 choose.)
The worker's `from sage.all import *` does **not** predefine arbitrary vars (only
`x`), so a prelude is the safe path (see PROBLEMS.md, V0.5).

## Error model

`CompileError { message, position?, suggestion? }`:

- **Balanced brackets are validated** before clause parsing. `expand (x+1` →
  "Unbalanced `(` — it is never closed." with the bracket's UTF-8 `position` and
  "Add a matching `)`." Mismatched (`(…]`) and orphan-close (`…)`) too.
- **Incomplete ranges** point at the gap: `integral x^2, x=0..` → "Range `x=0..`
  is incomplete — missing the upper bound after `..`." + a fix suggestion.
- Missing `=` in solve, missing `..` in a range, missing `order=`, bad order,
  missing `->` in a limit, a bare command word, a non-bracketed matrix — each
  gets a specific message + a `Try: …` example.

## Ambiguity

When a form needs one variable but the expression has several and no `for`/`wrt`
clause disambiguates, the result is `.ambiguous(candidates:)` — one Sage string
per reading: `solve x*y = 1` → `[solve(x*y == 1, x), solve(x*y == 1, y)]`. An
explicit `for x` / `wrt y` collapses it to `.success`.

## No implicit multiplication

Expression payloads pass through **verbatim** — we never insert `*`. `factor 2x`
→ `factor(2x)` (Sage's preparser, not us, decides what `2x` means). Per spec.

## Files

- `Sources/FriendlyCompiler/` — the surviving library:
  - `CompileResult.swift` — public result + error types.
  - `FriendlyCompiler.swift` — the compiler (command match, per-form rewrite,
    clause/range/equation parsing, error construction).
  - `Scanner.swift` — bracket-balance validation + top-level comma split (no math
    parser).
  - `Variables.swift` — free-variable inference for `requiredVariables`.
- `Sources/sagecalc-compile/main.swift` — the CLI (`--json`).
- `Tests/FriendlyCompilerTests/` — the 69-test swift-testing suite.
- `e2e.py` — the layer-3 driver (friendly → Sage → real worker).
