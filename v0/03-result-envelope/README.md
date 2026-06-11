# V0.3 — Sage Result Envelope & Type Classification

**Status: PASS (97/97 checks, 2026-06-11).** Proves Casette can turn an arbitrary
Sage/Python result into a small, **stable result envelope** the app renders
against — a fixed `kind`, human text, LaTeX, an unambiguous `repr` fallback, a
numeric `approx` where it's meaningful, and a per-kind `actions` menu that drives
the UI. Unknown objects degrade to `repr` rather than failing; huge outputs are
capped with an explicit truncation flag.

The classifier lives in the **canonical worker**
(`../01-worker-protocol/worker.py`) — extended in place, not copied. This folder
holds only the test harness.

## Files

| File | Role | Survives into app? |
| --- | --- | --- |
| `../01-worker-protocol/worker.py` | The worker. V0.3 replaced its rough `_classify` with a full envelope builder (`_build_envelope`). | **Yes** — real app code. |
| `harness.py` | Parent-side test driver. Boots one worker, runs every spec case + plot/text/error/unknown + huge-output cases, asserts kind stability and envelope sanity. | No (test scaffold). |

## Run it

```bash
cd v0/03-result-envelope
python3 harness.py            # boots the canonical worker, runs all checks
python3 harness.py --json     # also dumps each full envelope
python3 harness.py --sage /path/to/sage
```

Exit status is 0 iff every exit criterion passes. Verified against **SageMath
9.5** at `/usr/local/bin/sage`.

## The result envelope

Every value-bearing response carries the same fields (the contract V0.4+/V1 build
against; full reference in [`plans/WORKER-PROTOCOL.md`](../../plans/WORKER-PROTOCOL.md)):

| Field | Type | Meaning |
| --- | --- | --- |
| `kind` | string | One of the fixed kind set (below). |
| `plain` | string | `str(value)`, capped. The human-readable form. |
| `latex` | string \| null | Sage LaTeX where it renders, else null. |
| `repr` | string | `repr(value)`, capped. The unambiguous fallback — the degrade target for unknowns. |
| `approx` | string \| null | Numeric approximation where meaningful, else null. Feeds V0.8. |
| `actions` | string[] | Result-kind-aware op names the UI can offer. |
| `artifacts` | array | Always `[]` here; V0.5 fills it (plot files). |
| `truncated` | bool | Was `plain`/`repr` capped? |
| `truncation` | object | Present only when truncated: `{plain_len, repr_len, plain_cap, repr_cap}`. |

Plus the framing fields from V0.1/V0.2: `id`, `ok`, `stdout`, `stderr`, `value`,
and `error{type,message,traceback}` on failure.

### The fixed kind set

```
integer  rational  real  complex  symbolic  relation
list     matrix    plot  text     boolean   none    error  unknown
```

`boolean`, `none`, `error`, `unknown` are the framing kinds beyond the spec's
"minimum result kinds"; the spec's `equation / relation` is `relation`,
`list / tuple` is `list`, `symbolic expression` is `symbolic`.

## Classification — the load-bearing decisions

1. **Keyed off type module, not value.** Sage has many concrete classes per
   mathematical kind. We match `type(v).__module__`: `sage.rings.integer` →
   integer, `sage.rings.rational` → rational, `sage.rings.real*` → real,
   `sage.rings.complex*` → complex, `sage.matrix` → matrix,
   `sage.symbolic.expression` → symbolic (or **relation** if
   `v.is_relational()`), `sage.plot` → plot.

2. **Gaussian gotcha.** `3 + 4*I` is **not** a `sage.rings.complex` object — it's
   a `NumberFieldElement_gaussian` (an element of `QQ[i]`). We catch
   number-field Gaussian/cyclotomic elements as `complex` explicitly.

3. **`bool` before `int`.** `bool` is an `int` subclass, so `True` is checked
   first → `boolean`, not `integer`.

4. **`solve(...)` is a Sequence, but list-like.** It returns a
   `sage.structure.sequence.Sequence_generic`, which subclasses `list`, so the
   `isinstance(value, (list, tuple))` branch catches it → `list`. No special case
   needed.

5. **Unknown degrades, never fails.** Anything unrecognised → `kind:"unknown"`
   with `plain`/`repr`/`latex` (latex when Sage can render it). A
   `Permutation([2,1,3])` proves it: classified `unknown`, still carries
   `repr:"[2, 1, 3]"` and even LaTeX.

## `approx` policy (feeds V0.8 exact/numeric)

`approx` is computed **per kind**, never blindly:

- **integer / boolean / none / text / list / matrix / relation / plot / error →
  `null`.** An integer already *is* its exact value (nothing to approximate); a
  matrix/list approx isn't a scalar; a relation/plot has no single number.
- **rational / real / complex / symbolic → a decimal string**, but only if the
  result is a **constant**: a symbolic expression carrying free variables
  (`x^2 + 5*x + 6`, `variables() == (x,)`) gets `null`. `sin(pi/3)` (no free
  vars) gets `0.866025403784439`.
- **High-precision reals keep their own precision.** `N(sqrt(2), digits=50)` is
  approximated via `str(value)` (its native 50-digit decimal), *not* `.n()` —
  `.n()` would silently downcast it back to 53-bit.

## Truncation policy

`str()`/`repr()` of `list(range(10^6))` is ~7.9 MB; `factorial(10^5)` is a
~456 KB decimal. We never put an unbounded string on the wire. `plain` and `repr`
are capped at **8192 chars** each (latex at 16384), an `…` ellipsis is appended,
`truncated:true` is set, and a `truncation` object records the original lengths
and the caps — so the UI can say *"truncated, 8192 of 7,888,890 chars"* honestly.

## Exit criteria — evidence

All from one worker process driven by `harness.py` (97/97):

| Criterion | Result | Evidence |
| --- | --- | --- |
| Each common result has a **stable kind** | PASS | All 13 cases match their expected kind exactly (ZZ→integer, 1/3+1/5→rational, N(…)→real, sqrt(2)/sin(pi/3)/x²+5x+6→symbolic, `==`→relation, solve→list, matrix/rref→matrix, 3+4I→complex, plot→plot, Permutation→unknown). |
| Each result has **plain output** | PASS | Every value-bearing envelope has a non-empty `plain`. |
| Symbolic/math results have **LaTeX** where possible | PASS | rational `\frac{8}{15}`, matrix `\left(\begin{array}{rr}…`, relation `x^{2}+5\,x+6 = 0`, even unknown Permutation `[2, 1, 3]`. plot/text → `null` (no LaTeX, by design). |
| Unknown objects **degrade to repr, not failure** | PASS | `Permutation([2,1,3])` → `ok:true`, `kind:"unknown"`, `repr:"[2, 1, 3]"`. |
| Large outputs **capped or summarized** | PASS | `list(range(10^6))` → `truncated:true`, `plain` 8194 chars, `truncation.plain_len=7888890`; `factorial(10^5)` → `truncated:true`, original 456574 chars. |
| Result metadata can **drive UI actions** | PASS | `actions` populated per kind: matrix → `["det","rank","rref","eigenvalues","transpose","inverse"]`; rational → `["numerator","denominator","approx","continued_fraction"]`; relation → `["solve","lhs","rhs","subtract_sides"]`. |

### Representative envelopes (captured live)

```json
{ "kind": "rational", "plain": "8/15", "latex": "\\frac{8}{15}",
  "repr": "8/15", "approx": "0.533333333333333",
  "actions": ["numerator","denominator","approx","continued_fraction"],
  "artifacts": [], "truncated": false }

{ "kind": "matrix", "plain": "[1 2]\n[3 4]",
  "latex": "\\left(\\begin{array}{rr}\n1 & 2 \\\\\n3 & 4\n\\end{array}\\right)",
  "repr": "[1 2]\n[3 4]", "approx": null,
  "actions": ["det","rank","rref","eigenvalues","transpose","inverse"],
  "artifacts": [], "truncated": false }

{ "kind": "unknown", "plain": "[2, 1, 3]", "latex": "[2, 1, 3]",
  "repr": "[2, 1, 3]", "approx": null, "actions": ["repr","type"],
  "artifacts": [], "truncated": false }       // Permutation: degraded, not failed
```

## Regression

The V0.1 and V0.2 harnesses were re-run against this modified worker:
**V0.1 18/18, V0.2 35/35** — no regressions. The envelope changes are additive
(new fields `repr`/`approx`/`actions`/`truncated`); existing fields kept their
meaning. No stray Sage processes left (`pgrep -fl worker.py` clean).
