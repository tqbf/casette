# V0.8 — Exact / Numeric Display Policy

**Goal.** Prove how exact and approximate results are represented as a *product
policy*: an **exact** result is the primary value; its approximation is
secondary (shown with `≈`, or on demand). The spec's desired display for
`1/3 + 1/5`:

```text
8/15
≈ 0.5333333333
```

This builds on V0.3's per-kind `approx` field and hardens it into a complete,
configurable policy. All work is in the **one canonical worker**
(`../01-worker-protocol/worker.py`, extended in place) — single source of truth.

## Run

```sh
python3 harness.py                 # 95/95 checks, exit 0 iff all pass
python3 harness.py --json          # also dump every spec-case envelope
python3 harness.py --sage /path/to/sage
```

`harness.py` boots the canonical worker once and drives every spec case + the
exactness traps through one persistent session.

---

## The policy (the design I own)

The value envelope gains four V0.8 fields on top of V0.3's `approx`:

| Field | Type | Meaning |
| --- | --- | --- |
| `exact` | `true \| false \| null` | Is the **primary** result an exact value? |
| `primary_is_approx` | `bool` | Should the UI put `≈` on the **primary** value (vs the secondary)? |
| `approx` | `string \| null` | The decimal approximation (unchanged meaning from V0.3). |
| `approx_digits` | `int \| null` | The precision (decimal digits) `approx` carries. |
| `exact_value` | `string` | *Only in force-numeric mode:* the original exact form, preserved while the primary shows the decimal. |

### `exact` semantics (the load-bearing part)

You **cannot** read exactness off `parent().is_exact()`: the entire **Symbolic
Ring reports `is_exact() == False`**, so `sqrt(2)`, `pi`, `sin(1)` would all be
mislabeled "inexact." Exactness is decided per kind:

| Kind | `exact` | Why |
| --- | --- | --- |
| `integer`, `rational` | `true` | Exact rings (`8/15` is exact). |
| `real`, `complex` | `false` | A float-backed `RealLiteral`/`RealNumber`/mpc is inherently approximate. |
| `symbolic` | `true` *unless* it contains an inexact numeric atom | `sqrt(2)`, `pi`, `sin(1)`, `sin(pi/3)`, `sqrt(2)+pi` → exact; `2.5+sqrt(2)`, `1.5*x` → false. |
| matrix, list, relation, plot, text, boolean, none, error, unknown | `null` | Exactness isn't a scalar property here. |

For symbolic, the discriminator is a **recursive tree-walk** (`operands()`) that
flags a leaf as inexact iff it `is_numeric()` and its `pyobject().parent()` is
`is_exact() == False`. That cleanly separates `sqrt(2)+pi` (exact) from
`2.5+sqrt(2)` (inexact).

### `primary_is_approx` — where the `≈` goes

- **`false`** for an exact result → the exact form is the primary line; `approx`
  is the secondary `≈` line. (`8/15` then `≈ 0.5333333333`.)
- **`true`** when the primary already *is* a float (an `N(...)` real, a `2.5`
  literal, an inexact symbolic) — there's nothing more exact to show, so the
  `≈` goes on the primary itself; the secondary `approx` is null.
- **`true`** in force-numeric mode (we *replace* the primary with `N()`).

A renderer derives the whole display from one envelope, **no round-trip**:

```python
def render(e):
    if e["primary_is_approx"]:
        return "≈ " + e["plain"]              # primary IS the approximation
    out = e["plain"]                          # exact primary
    if e["approx"] is not None:
        out += "\n≈ " + e["approx"]           # secondary
    return out
```

From the `1/3 + 1/5` envelope this produces exactly `8/15\n≈ 0.5333333333`
(asserted in PART 2).

---

## API design (frozen in plans/WORKER-PROTOCOL.md)

**Configurable precision — two levers:**

```json
{"op": "config", "precision_digits": 20}     // session default (getter if omitted)
{"id": "r1", "code": "1/3 + 1/5", "precision_digits": 6}   // per-request override
```

- Default precision is **10** (matching the spec's `0.5333333333`).
- A per-request `precision_digits` overrides the session default **for that
  request only** — it does not change the session.
- Non-positive / non-int precision is rejected (`ok:false`), session unchanged.

**Force-numeric — per request, no session pollution:**

```json
{"id": "r2", "code": "y", "numeric": true}                  // primary becomes N(y)
{"id": "r3", "code": "y", "numeric": true, "precision_digits": 5}
```

`numeric:true` makes the **primary** result the numeric approximation (the exact
form preserved in `exact_value`). It does **not** mutate the namespace: after
`y = 1/3` then a `numeric:true` eval of `y`, the next normal `y` is exactly
`1/3` (a `Rational`), and `parent(y)` is still `Rational Field`.

**Precision clamping (the PROBLEMS.md trap).** Asking for *more* bits than a
concrete real/complex holds raises (`CC(3,4).n(digits=15)` → "use at most 53
bits"). The worker clamps a precision request to the value's own `prec()`, so a
high-precision request on a 53-bit complex never raises, and a low-precision
request on a 170-bit `N(sqrt(2),digits=50)` doesn't downcast the stored value.

---

## Spec test cases — envelope evidence (precision 10, default)

| Code | kind | exact | primary_is_approx | approx | note |
| --- | --- | --- | --- | --- | --- |
| `1/3 + 1/5` | rational | **true** | false | `0.5333333333` | exact primary `8/15`, `≈` secondary |
| `sqrt(2)` | symbolic | **true** | false | `1.414213562` | exact SYMBOLIC (ring `is_exact()` is False, but it IS exact) |
| `N(sqrt(2), digits=50)` | real | **false** | **true** | `1.414213562` | primary IS the 50-digit number |
| `pi` | symbolic | **true** | false | `3.141592654` | exact constant |
| `sin(1)` | symbolic | **true** | false | `0.8414709848` | **TRAP**: Sage keeps `sin(1)` symbolic & exact — *not* coerced to a float |
| `sin(pi/3)` | symbolic | **true** | false | `0.8660254038` | exact (auto-simplifies to `1/2*sqrt(3)`) |
| `2.5` | real | **false** | **true** | `2.500000000` | input float literal → Real |
| `ZZ(104729)` | integer | **true** | false | `null` | exact integer; no scalar approx (already exact) |
| `3 + 4*I` | complex | **false** | **true** | `3.0… + 4.0…*I` | Gaussian element; complex floats approximate-by-nature |
| `2.5 + sqrt(2)` | symbolic | **false** | **true** | `3.914213562` | inexact symbolic (contains a float atom) |
| `sqrt(2) + pi` | symbolic | **true** | false | `4.555806216` | exact symbolic sum |

Sample envelope (`1/3 + 1/5`):

```json
{
  "ok": true, "value": true, "kind": "rational",
  "plain": "8/15", "latex": "\\frac{8}{15}", "repr": "8/15",
  "approx": "0.5333333333", "approx_digits": 10,
  "exact": true, "primary_is_approx": false,
  "actions": ["numerator","denominator","approx","continued_fraction"],
  "artifacts": [], "truncated": false
}
```

Sample envelope (`N(sqrt(2), digits=50)` — primary IS the approximation):

```json
{
  "ok": true, "value": true, "kind": "real",
  "plain": "1.4142135623730950488016887242096980785696718753769",
  "approx": "1.414213562", "approx_digits": 10,
  "exact": false, "primary_is_approx": true,
  "actions": ["approx_more_digits","round","continued_fraction"]
}
```

---

## Exit criteria — all PASS (95/95)

| Exit criterion | Evidence |
| --- | --- |
| **Exact result is primary by default** | `plain` carries the exact form (`8/15`, `sqrt(2)`, `pi`, `2^100`); `exact:true`; `primary_is_approx:false`. |
| **Approximation available for exact results** | `approx` non-null for every exact rational/symbolic-constant (`8/15`→`0.5333333333`, `sqrt(2)`→`1.414213562`, …). |
| **Precision configurable** | `config precision_digits=20` → `8/15` shows 20 digits; per-request `precision_digits=6` → `0.533333` without changing the session; invalid rejected. |
| **User can force numeric** | `numeric:true` → primary becomes the decimal, `exact_value` preserves the exact form; the **next** normal eval is exact again; `parent(y)` still `Rational Field`. |
| **No accidental float coercion** | exact-in→exact-out across integer/rational/symbolic/matrix; `2^100` stays exact; a stored `N(sqrt(2),digits=50)` keeps its 170-bit precision after a low-precision numeric request. |
| **Spec display derivable, no round-trip** | a pure renderer over the `1/3+1/5` envelope produces exactly `8/15` + `≈ 0.5333333333`. |

## Regression — no breakage (V0.8 is purely additive)

V0.1 **18/18** · V0.2 **35/35** · V0.3 **97/97** · V0.5 **88/88** · V0.6 **24/24**
· V0.7 e2e **19/19**. New envelope fields, the `config` op, and the optional
`numeric`/`precision_digits` request params don't touch any existing path.
`pgrep -fl "sage -python"` clean after the run.

## Lessons (see PROBLEMS.md)

- The Symbolic Ring is uniformly `is_exact() == False`; exactness must be decided
  per-kind, and for symbolic by a tree-walk for inexact numeric atoms.
- `sin(1)` stays symbolic & exact in Sage — don't coerce it to a float by default.
- Clamp a precision request to a concrete value's own `prec()`, or `.n(bits)`
  raises ("use at most N bits").
- Force-numeric is a *display* re-presentation: evaluate normally (namespace
  stays exact), then apply `N()` only to the echoed value.
