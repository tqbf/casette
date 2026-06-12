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
