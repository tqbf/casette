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
