# V0.6 — Live Symbol Table Introspection

Proves Casette can show **live user-created Sage variables** in a sidebar: a new
`symbols` worker op that snapshots the pristine namespace, diffs the live one
against it, and returns a bounded, classified list of only the symbols the user
made — fast and safe even when those symbols are enormous.

The op is implemented in the **one canonical worker**
(`../01-worker-protocol/worker.py`, extended in place — single source of truth),
not a copy. This dir holds only the test harness + this evidence.

## Run

```sh
python3 harness.py                 # 24/24 checks
python3 harness.py --json          # also dump each symbols response
python3 harness.py --sage /path/to/sage
```

Exit status is 0 iff every exit criterion passes. The harness boots one worker,
runs the spec sequence through a single persistent session, and asserts the
results. No stray Sage processes are left (`pgrep -fl "sage -python"` clean).

## The op

Request:

```json
{"id": "s-1", "op": "symbols"}
```

Response (live, from the spec sequence
`x = var("x")` · `A = matrix([[1,2],[3,4]])` · `f(x) = sin(x)/x` · `n = 104729`):

```json
{"id": "s-1", "ok": true, "op": "symbols",
 "symbols": [
   {"name": "A", "kind": "matrix",            "summary": "2×2 over Integer Ring"},
   {"name": "f", "kind": "symbolic function", "summary": "x |--> sin(x)/x"},
   {"name": "n", "kind": "integer",           "summary": "104729"},
   {"name": "x", "kind": "symbolic variable", "summary": "x"}
 ]}
```

Each entry is `{name, kind, summary}`. The list is sorted by `name` for a stable
sidebar. (Full request/response/kind-vocabulary/policy spec is frozen in
[../../plans/WORKER-PROTOCOL.md](../../plans/WORKER-PROTOCOL.md).)

## Exit criteria — all PASS (24/24, executed evidence)

| Criterion | Evidence |
| --- | --- |
| **User-created symbols appear** | After the spec sequence, `symbols` returns exactly `x, A, f, n` with the kinds/summaries above. `x` → `symbolic variable "x"`; `A` → `matrix "2×2 over Integer Ring"` (Sage's `parent()` dims + base ring); `f(x)=sin(x)/x` → `symbolic function "x \|--> sin(x)/x"` (Sage preparses it to a callable symbolic-expression assignment, so it lands as a normal binding and surfaces); `n` → `integer "104729"`. |
| **Internal Sage junk is filtered** | Before any user code the op returns `[]`. A probe of 23 specific Sage names (`var matrix factor SR ZZ QQ sqrt sin pi x i e I __builtins__ NS preparse latex …`) confirms **none leak**. |
| **Deleted symbols disappear** | After `del n`, the op returns `x, A, f` — `n` is gone. |
| **Reassigned symbols update** | `n = 5` → `integer "5"`; then `n = "hello"` → `text "hello"` — kind **and** summary re-derived from the current value each call (the worker reads `NS` live). |
| **Summaries are bounded** | `M = matrix(ZZ, 200, 200, range(40000))` → `"200×200 over Integer Ring"` (25 chars, structural — never stringifies 40 000 entries). `big_list = list(range(10**6))` → `"list of 1000000 items"` (21 chars, **not** the 7.9 MB stringification). Longest summary in the whole huge-object response: **25 chars**. Hard cap `_MAX_SUMMARY = 200`. |
| **Inspection does not trigger huge computation** | The `symbols` op over a namespace holding the 200×200 matrix **and** the million-item list returns in **~0.6–0.9 ms** (timed in-harness). Measured separately: the cheap structural summary is ~1e-5 s; `str()` of the same objects is ~0.05 s and produces megabytes. The op never calls `str()` on a matrix or a big container. |

### Extra robustness proven

- **Raising `__repr__`/`__str__` degrades gracefully.** A user `class Boom`
  whose `__repr__` *and* `__str__` raise → its instance summarizes as
  `"<unprintable: RuntimeError(...)>"`; the op does not crash, the response keeps
  its shape, and every other symbol is unaffected. (`Boom` the class itself also
  appears, as kind `unknown`.)
- **User `import` / `def` surface distinctly.** `import numpy` → `module
  "numpy"`; `def g(y): …` → `function "g()"`. The spec wants user-created symbols;
  a user's own module/function bindings are user-created, so they show (with
  their own kinds) rather than being hidden.
- **Wire intact afterward.** `1 + 1` → `2` after all the symbols ops.

## Why the baseline diff is by **object identity**, not just name

A name-only diff (`name not in baseline`) wrongly hides the spec's own `n =
104729`: Sage's `from sage.all import *` exports **`n`** (it's
`numerical_approx`), **`N`** (also `numerical_approx`), and **`i`** (the Gaussian
unit) — all extremely common variable names. So the baseline snapshots the
pristine **objects**, and a name surfaces iff it is *new* OR *rebound to a
different object* (`live is not baseline_obj`). We retain the baseline objects
(not just `id()`s) so a freed baseline object can't have its `id` recycled and
make the identity check lie. See PROBLEMS.md.

## Files

- `harness.py` — the 24-check harness (this dir).
- `../01-worker-protocol/worker.py` — the canonical worker; the `symbols` op
  lives in its **V0.6** section (`_handle_symbols`, `_symbol_kind`,
  `_symbol_summary`, `_SYMBOL_BASELINE`).
- `../../plans/WORKER-PROTOCOL.md` — the frozen op spec.
