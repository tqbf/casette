## 2026-06-11 — V0.7: Friendly input compiler (command shim → Sage) — PASS

**Did.** Built a standalone SwiftPM package `v0/07-friendly-compiler/` with three
targets: **`FriendlyCompiler`** (the surviving artifact — a **pure** library,
`String → CompileResult`, no I/O, written to migrate into the app), a
**`sagecalc-compile`** CLI (`--json`), and a **swift-testing** suite. Plus a
Python **`e2e.py`** that pipes every generated Sage string through the **real
canonical worker** (`../01-worker-protocol/worker.py`). Written in **Swift, not
Python**, per the orchestrator decision: V1.4 compiles input → Sage
*synchronously on every keystroke/submit* to show "Generated Sage" without
round-tripping through the worker. **Three layers all green: `swift test` 69/69 ·
CLI smoke · e2e 19/19.** `pgrep -fl "sage -python"` clean.

**The contract.** `enum CompileResult`:
`success(generatedSage, requiredVariables)` / `bypass(rawSage)` /
`error(CompileError{message, position?, suggestion?})` / `ambiguous(candidates)`.
A command shim, **not a language**: we tokenize only enough to find the command,
the expression, and the clauses (ranges `x=0..1`, `wrt x`, `->`, `order=7`,
`for x`); expression payloads pass through **structurally**. We DO validate
balanced parens/brackets.

**Exit criteria — all PASS:**
- **Compiler emits Sage, not direct eval** — every form returns a Sage *string*;
  the library never touches a worker. All 16 spec forms map to the exact
  reference Sage (verified by CLI + unit tests).
- **Generated Sage can be shown to the user** — it's a returned `String`; `--json`
  exposes it + `requiredVariables` for tooling.
- **Raw Sage bypass works** — `factor(x^4-1)`, `factorial(5)`, `2+2`, `sin(pi/3)`,
  `A = matrix(...)`, `x.diff()`, `foobar x^2`, `""` all bypass **untouched**. Rule:
  *known command word that is the whole input OR immediately followed by
  whitespace* → friendly; else bypass.
- **Ambiguous → candidates** — `solve x*y = 1` → `[solve(x*y == 1, x),
  solve(x*y == 1, y)]`; same for `derivative x*y`, `integral x*y`. `for x`/`wrt y`
  collapses it to `.success`.
- **Parse errors are useful** — `integral x^2, x=0..` → "Range `x=0..` is
  incomplete — missing the upper bound after `..`." + a fix; unbalanced brackets
  carry a UTF-8 `position` ("Unbalanced `(` — it is never closed."); mismatched /
  orphan-close / missing-`=` / missing-`order=` / bad-order / missing-`->` /
  bare-command / non-bracketed-matrix each get a specific message + `Try: …`.
- **No implicit multiplication** — `factor 2x` → `factor(2x)` (payload verbatim;
  Sage's preparser decides, not us).

**The double-integral nesting (load-bearing, got it right).**
`double integral x*y, x=0..1, y=0..x` →
`integrate(integrate(x*y, (y, 0, x)), (x, 0, 1))`: the **inner** integral binds
the **last** range (`y`), the **outer** the **first** (`x`); the inner bound may
reference the outer var (`y=0..x`). The e2e driver confirms it **evaluates to
`1/8`**.

**Variable policy (decided + documented + proven).** The compiler **reports** free
variables in `requiredVariables` and **never injects** declarations — the
generated Sage is a single clean expression. Inference: bare identifiers not
followed by `(`, not reserved (`pi e I i oo …`, common builtins), plus the
command-bound variable; ordered command-bound-first then body order.
**Decision for V1.4: emit a `var('V')` prelude per required variable before
evaluating** (the worker's `from sage.all import *` predefines only `x`, per
PROBLEMS.md V0.5). `e2e.py` does exactly this and it works for every form.

**End-to-end (layer 3).** For each form: compile via the CLI (`--json`), declare
each required var with `var('V')`, eval the generated Sage in the real worker,
assert `ok:true` + sensible kind. **19/19**: solve→list, eigenvalues→list,
plot→plot **with 2 artifacts**, matrix→matrix, rref→matrix; definite
integrals/limits come back as Sage **symbolic**-ring elements whose `plain` is the
exact value. Bonus checks: bypass `2+2`→`4`, double integral→`1/8`, wire intact
(`1+1`→`2`) after all evals.

**Learned / surprised.**
- **A definite integral is `kind:"symbolic"`, not `rational`/`real`.**
  `integrate(x^2,(x,0,1))` returns `1/3` and `limit(sin(x)/x, x=0)` returns `1` —
  but as elements of the **symbolic ring** (`plain` is the exact value), so V0.3's
  `_classify` lands them in `symbolic`. My first e2e expectations assumed
  `rational`/`real` and "failed" 3 cases — the *compiler* was right, the *test*
  was wrong. Worth knowing for V0.8 (exact/numeric): the exact value is in
  `plain`, the float in `approx` (`0.125`), even though the kind is symbolic.
- **The bypass rule is the whole design.** Making "command word + space →
  friendly, else raw Sage untouched" the single gate means the shim is purely
  additive and progressive disclosure to raw Sage is free — `factor(...)` (a call)
  and `factorial(...)` both correctly fall through with no special-casing beyond
  the space-boundary check.
- **Reporting vars beats injecting them.** Keeping `var(...)` out of
  `generatedSage` keeps "Generated Sage" clean to show the user and lets V1.4 own
  declaration strategy (always-declare vs. skip-if-already-in-`symbols`). The
  proof (`e2e.py`) exercises the always-declare path.

**Next.** V0.8 — exact/numeric display policy. Note for it: a definite
integral/limit is symbolic with the exact value in `plain` and the float in
`approx` — don't coerce it to a float by default.

---
