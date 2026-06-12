## 2026-06-11 — V0.8: Exact/numeric display policy — PASS

**Did.** Hardened V0.3's per-kind `approx` into a complete, configurable
exact/numeric **product policy** in the **one canonical worker**
(`v0/01-worker-protocol/worker.py`, extended in place). New harness
(`v0/08-exact-numeric/`, **95/95**) drives every spec case + the exactness traps
through a live worker. No regression: V0.1 18/18 · V0.2 35/35 · V0.3 97/97 ·
V0.5 88/88 · V0.6 24/24 · V0.7 e2e 19/19. `pgrep -fl "sage -python"` clean.

**The policy (envelope gains 4 fields + `exact_value`).**
- **`exact: true|false|null`** — is the *primary* result exact? `true` for
  integer/rational/exact-symbolic; `false` for an inherently approximate
  real/complex/inexact-symbolic; `null` where exactness isn't a scalar property
  (matrix/list/relation/plot/…).
- **`primary_is_approx: bool`** — does the `≈` belong on the *primary* value (it
  already is a float, or force-numeric) vs the secondary line?
- **`approx_digits: int|null`** — the precision `approx` carries.
- **`exact_value: string`** — only in `numeric:true` evals: the original exact
  form, preserved while `plain` shows the decimal.

**API (frozen in WORKER-PROTOCOL.md).**
- **Configurable precision, two levers:** a session default via a new
  `{"op":"config","precision_digits":N}` op (default **10**, matching the spec's
  `0.5333333333`; omit the field to read it; rejects non-positive); and a
  **per-request** `precision_digits` eval field that overrides the session *for
  that request only*.
- **Force-numeric per request:** `{"code":..,"numeric":true}` makes the primary
  the numeric value WITHOUT polluting the session (it's a display
  re-presentation: eval runs normally, then `N()` is applied to the echoed
  value). Honors `precision_digits` too.

**Exit criteria — all PASS (executed evidence in README):**
- **Exact primary by default** — `plain` is the exact form (`8/15`, `sqrt(2)`,
  `pi`, `2^100`); `exact:true`, `primary_is_approx:false`.
- **Approx available for exact results** — `8/15`→`0.5333333333`,
  `sqrt(2)`→`1.414213562`, etc.
- **Precision configurable** — `config` to 20 → `8/15` shows 20 digits;
  per-request `precision_digits=6` → `0.533333` without changing the session;
  invalid rejected.
- **User can force numeric** — `numeric:true` on `y` → primary `0.333…`,
  `exact_value:"1/3"`; the **next** normal `y` is exactly `1/3`, `parent(y)` is
  `Rational Field` (namespace untouched).
- **No global float coercion** — exact-in→exact-out across integer/rational/
  symbolic/matrix; a stored `N(sqrt(2),digits=50)` keeps its **170-bit** RealField
  precision after a low-precision numeric request.
- **Spec display derivable, no round-trip** — a pure renderer over the
  `1/3+1/5` envelope produces exactly `8/15` + `≈ 0.5333333333`.

**Learned / surprised.**
- **`parent().is_exact()` is useless for the Symbolic Ring** — it's uniformly
  `False`, so `sqrt(2)`, `pi`, `sin(1)` would all read "inexact." Exactness must
  be decided **per kind**, and for symbolic by a recursive `operands()`
  tree-walk that flags a leaf as inexact iff `is_numeric()` and its
  `pyobject().parent().is_exact()` is False. That cleanly separates `sqrt(2)+pi`
  (exact) from `2.5+sqrt(2)` and `1.5*x` (inexact). → PROBLEMS.md.
- **`sin(1)` is the headline trap** — Sage keeps it **symbolic and exact** (it is
  NOT evaluated to `0.841…`). The handoff from V0.7 (a definite integral/limit is
  `kind:"symbolic"` yet exact) is the same shape: don't key "is exact?" off the
  kind being `rational`/`real`.
- **Precision must be clamped to the value's own `prec()`** — `.n(bits)` raises
  ("cannot approximate to N bits, use at most M") if you ask a 53-bit object for
  more. Clamping (vs the V0.3 `str(value)`-for-reals approach) lets a single
  code path serve "fewer digits than the value holds" (e.g. show
  `N(sqrt(2),digits=50)` at 10 digits) AND "more than it holds" (clamp), without
  ever raising or downcasting the stored object.
- **Force-numeric is free if it's display-only.** Because the worker already
  evaluates normally and only *then* re-presents the echoed value, namespace
  isolation needs no special machinery — `y` stays a `Rational`. The temptation
  to `N()` the assignment itself (which would pollute storage) is the wrong path.

**Next.** V0.9 — Sage Doctor / environment discovery. For V1.8 (the in-app
exact/numeric UI): render `plain` as primary; if `primary_is_approx` put `≈` on
it, else show `approx` as a secondary `≈ …` line; offer a "force numeric" toggle
(`numeric:true`) and a precision control wired to per-request `precision_digits`
(and/or the session `config` op). The UI needs **no** Sage round-trip to render
the default exact+approx display — one envelope carries everything.

---
