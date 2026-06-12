# Casette Friendly Input Compiler (V0.7)

The forgiving **command shim** that turns a small set of friendly command forms
into Sage source. Written in **Swift** as a pure library (`FriendlyCompiler`)
because V1.4 must compile input → Sage **synchronously on every keystroke/submit**
to display "Generated Sage" without round-tripping through the Python worker.

Source of truth: `v0/07-friendly-compiler/`. This doc is the frozen reference for
the grammar, bypass rule, variable policy, error model, and V1.4 integration.

> **Policy (from the spec): this is a command shim, not a language.** We do not
> build a general DSL or a full math parser. We tokenize only enough to find the
> command, the expression, and the clauses; expression payloads pass through
> structurally. There is **no implicit multiplication**.

---

## The contract

```swift
enum CompileResult {
  case success(generatedSage: String, requiredVariables: [String])
  case bypass(rawSage: String)
  case error(CompileError)            // { message: String, position: Int?, suggestion: String? }
  case ambiguous(candidates: [String])
}
```

- **`success`** — input matched a friendly form; `generatedSage` is a **single
  Sage expression** to show the user and `eval`, `requiredVariables` are the free
  variables it needs declared.
- **`bypass`** — input is raw Sage, returned **untouched**.
- **`error`** — malformed friendly input; structured, position-bearing, with a
  suggestion.
- **`ambiguous`** — genuinely ambiguous; candidate Sage strings to offer.

The library is **pure** (no I/O, no globals): `String in → CompileResult out`.

---

## Grammar of accepted forms

One input line. Case-insensitive command words. The payload after the command is
passed through structurally (we never reflow the user's math).

| Form | Friendly | Generated Sage |
| --- | --- | --- |
| factor | `factor EXPR` | `factor(EXPR)` |
| expand | `expand EXPR` | `expand(EXPR)` |
| simplify | `simplify EXPR` | `(EXPR).simplify_full()` |
| solve | `solve LHS = RHS [for V]` | `solve(LHS == RHS, V)` |
| derivative | `derivative EXPR [wrt V]` | `derivative(EXPR, V)` |
| integral (indefinite) | `integral EXPR` | `integrate(EXPR, V)` |
| integral (definite) | `integral EXPR, V=A..B` | `integrate(EXPR, (V, A, B))` |
| double integral | `double integral EXPR, V1=A..B, V2=C..D` | `integrate(integrate(EXPR, (V2, C, D)), (V1, A, B))` |
| limit | `limit EXPR, V->P` | `limit(EXPR, V=P)` |
| taylor | `taylor EXPR, V=P, order=N` | `taylor(EXPR, V, P, N)` |
| plot | `plot EXPR, V=A..B` | `plot(EXPR, (V, A, B))` |
| matrix | `matrix [[…]]` | `matrix([[…]])` |
| eigenvalues | `eigenvalues [[…]]` | `matrix([[…]]).eigenvalues()` |
| rref | `rref [[…]]` | `matrix([[…]]).rref()` |

**Synonyms:** `diff`→derivative, `integrate`→integral, `double integrate`→double
integral, `eigenvalue`→eigenvalues.

**Double-integral nesting (load-bearing).** The **inner** `integrate` binds the
**last** range, the **outer** binds the **first**:
`double integral x*y, x=0..1, y=0..x` →
`integrate(integrate(x*y, (y, 0, x)), (x, 0, 1))`. The inner upper bound may
reference the outer variable (`y=0..x`); bound expressions are never reordered or
rewritten. **Verified end-to-end to evaluate to `1/8`.**

**Clause forms** (parsed, not the math):
- **range** `V=A..B` — `V` a plausible variable, `..` separating two non-empty
  bounds; bounds are passed through verbatim (so `-pi`, `x`, `0` all work).
- **`for V` / `wrt V`** — a trailing keyword clause naming the variable.
- **`V->P`** (limit) — split on `->`.
- **`order=N`** (taylor) — `N` a whole number.

Top-level commas split clauses (commas inside `()[]{}` don't split), so a matrix
or a function with multiple args inside the integrand survives.

---

## Bypass rule

> **A line is friendly iff it begins with a known command word that is either the
> entire input or immediately followed by whitespace. Everything else bypasses as
> raw Sage, returned untouched.**

| Input | Result | Why |
| --- | --- | --- |
| `factor x^4 - 1` | friendly | command word + space |
| `factor(x^4-1)` | **bypass** | already function-call syntax (`(` not space) |
| `factorial(5)` | **bypass** | starts with `factor` but no space boundary |
| `2+2`, `sin(pi/3)` | **bypass** | no leading command word |
| `A = matrix([[1,2],[3,4]])` | **bypass** | starts with `A`, not a command |
| `x.diff()` | **bypass** | starts with `x` |
| `foobar x^2` | **bypass** | unknown leading word |
| `""` (empty) | **bypass** (`""`) | nothing to do |

This makes the shim **purely additive**: anything unrecognized is the user's own
Sage. Progressive disclosure from friendly commands to raw Sage costs nothing — a
user can paste arbitrary Sage and it flows straight through.

---

## Variable policy

**The compiler reports required variables; it never injects declarations.** The
`generatedSage` is always a single clean expression suitable for "Generated Sage"
display.

`requiredVariables` is inferred by scanning the expression for **bare identifiers
not followed by `(`** (excludes function calls), **not reserved** (constants
`pi e I i oo infinity …`, common builtins `sqrt sin cos …`), plus any
**command-bound** variable (the integration / plot / solve / limit variable).
Order: command-bound first (for a double integral: outer then inner), then
left-to-right body order, de-duplicated. It's a documented **heuristic** — good
enough to drive declarations, not a semantic analysis.

**Decision for V1.4 — emit `var('V')` preludes.** Before evaluating the generated
Sage in the session, declare each `requiredVariable` with `var('V')`. This is
exactly what `e2e.py` does and what proves the pipeline end-to-end. Rationale:

- The worker's `from sage.all import *` predefines only `x`, not arbitrary
  variables (see PROBLEMS.md, V0.5: a bare `plot(sin(x), …)` `NameError`s in the
  worker until `x = var('x')`). So a prelude is the safe, general path.
  *(Correction, V1.5 fix round: the star-import predefines NOTHING — not even
  `x`; only the interactive REPL injects it. Since V1.5 the app matches the
  REPL by sending a `var('x')` boot prelude after every boot/restart
  (`ShellModel.bootPrelude`), so this aside is effectively true again at the
  session level. The always-declare `var('V')` policy below is unchanged and
  still load-bearing for every other variable.)*
  *(Extension, V1.7 fix round — a DELIBERATE deviation from strict REPL
  fidelity, approved product call: the boot prelude is now
  `var('x, y, z, t')`. The real REPL predefines only `x`, but the V1.7 live
  gate showed `implicit_plot(x^2+y^2==1, (x,-2,2), (y,-2,2))` — written
  exactly as the upstream Sage docs write it — NameError'ing on `y` out of
  the box, because raw-Sage input bypasses the friendly compiler and so gets
  no `var('V')` preludes. Casette is a calculator, not a REPL clone: the
  conventional calculator variables `x y z t` cover implicit/parametric/3D
  doc examples verbatim, all four show honestly in the Symbols sidebar from
  boot, and declaring is idempotent so the friendly preludes on top remain
  harmless. Anything beyond those four is still the friendly compiler's
  `var('V')` prelude or the user's own `var(...)` — the always-declare
  policy below is unchanged.)*
- Declaring is idempotent and cheap; re-`var('x')` over an existing `x` is
  harmless. V1.4 may optimize by skipping vars the live `symbols` op (V0.6)
  already shows declared, but the simple "always declare required" path is proven.
- Keeping `var(...)` **out** of `generatedSage` means the user sees the *math*,
  not session plumbing — and lets V1.4 own the declaration strategy.

---

## Error model

`CompileError { message, position?, suggestion? }` — `position` is a 0-based UTF-8
offset into the input where known.

- **Balanced brackets validated first.** `expand (x+1` → "Unbalanced `(` — it is
  never closed." (+ position, + "Add a matching `)`."). Mismatch `(…]` and orphan
  close `…)` are distinct messages.
- **Incomplete range points at the gap.** `integral x^2, x=0..` → "Range `x=0..`
  is incomplete — missing the upper bound after `..`." + "Complete it, e.g.
  `x=0..1`." A range missing `..` entirely gets its own message.
- **Per-form preconditions** each get a specific message + a `Try: …` example:
  solve without `=`, derivative/integral with no variable to bind, taylor missing
  `order=`, taylor non-numeric order, limit missing `->`, a bare command word, a
  non-bracketed matrix, too many ranges for a single integral.

Errors are **useful**, not generic: the message says what's wrong, the position
(for brackets) says where, the suggestion shows the fix.

---

## Ambiguity

When a form needs exactly one variable but the expression has several and no
`for`/`wrt` clause disambiguates, the result is `.ambiguous(candidates:)` — one
Sage string per reading:

- `solve x*y = 1` → `[solve(x*y == 1, x), solve(x*y == 1, y)]`
- `derivative x*y`, `integral x*y` → both single-variable readings.

An explicit clause collapses it: `solve x*y = 1 for x` → `.success`.

---

## How V1.4 integrates this

1. **On every keystroke/submit, call `FriendlyCompiler.compile(input)`** (pure,
   synchronous, microsecond-fast — no worker round-trip).
2. **Show the result by case:**
   - `.success` → display `generatedSage` in the "Generated Sage" affordance;
     enable submit.
   - `.bypass` → the input *is* the Sage; show it as-is (or hide the panel).
   - `.error` → surface `message` inline, highlight at `position`, show
     `suggestion`. Don't submit.
   - `.ambiguous` → present `candidates` as a picker; the chosen string becomes
     the Sage to run.
3. **On submit (success/bypass):** for each `requiredVariable`, send the worker a
   `var('V')` eval (prelude), then send the `generatedSage` eval. Render the
   result envelope as usual (V0.3/V0.4/V0.5).
4. The library is written to **migrate into the app target verbatim** — no I/O, no
   dependencies, pure Swift. Move `Sources/FriendlyCompiler/` in and add a test
   target; the CLI and `e2e.py` stay in `v0/` as the proof.

---

## Test evidence

- **Unit:** `swift test` — **69 tests / 9 suites** (every form, every error,
  bypass, double-integral nesting, spacing/casing, synonyms, required-vars,
  no-implicit-mult).
- **CLI:** `swift run sagecalc-compile "<input>"` (+ `--json`).
- **End-to-end:** `python3 e2e.py` — **19/19** checks: every friendly form's
  generated Sage piped through the **real canonical worker** with the var-prelude
  policy applied; asserts `ok:true` + sensible kind (solve→list, eigenvalues→list,
  plot→plot+artifacts, …), plus the double integral == `1/8`, a bypass `2+2`==`4`,
  and the wire intact afterward. No leaked Sage workers (`pgrep -fl "sage -python"`
  clean).
