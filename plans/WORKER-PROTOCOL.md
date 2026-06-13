# Casette Worker Protocol & Result Envelope

The stable contract between the parent app (`SessionController` / `SageKernel`)
and the Sage worker (`sage -python worker.py`). V0.4+ and V1 build against this.

Source of truth for the implementation: `v0/01-worker-protocol/worker.py` (the
canonical worker). This doc describes its behavior as of **V0.8** (exact/numeric
policy added; symbols op V0.6; artifacts V0.5; everything else unchanged since
V0.3).

> Stability note: the envelope **field set and kind set below are frozen** for
> V1. New facts get new fields (additive); existing fields keep their meaning.
> The `artifacts` array shape was filled out in **V0.5**; the **V0.8**
> exact/numeric fields (`exact`, `primary_is_approx`, `approx_digits`,
> `exact_value`), the `config` op, and the `numeric`/`precision_digits` eval
> request fields are the latest additive additions.

---

## Framing

Line-delimited JSON (JSONL) over the worker's stdin/stdout: **one JSON object per
line in, one per line out**. The worker writes protocol JSON to a **private dup'd
fd** established before Sage imports, so user `print()` / raw `os.write(1, …)` /
Cython C-level writes can never corrupt the wire (they're captured into
`stdout`/`stderr` instead). See PROBLEMS.md.

On startup the worker emits a **ready banner** carrying its *real* pid (the Python
worker, not the `sage` bash-wrapper pid the parent's `Popen` sees):

```json
{"op": "ready", "ok": true, "pid": 51933}
```

The parent targets **SIGINT (interrupt) at this pid**; for a hard kill it signals
the whole **process group** (`os.killpg`). See PROBLEMS.md ("kill the process
*group*").

---

## Requests

```json
{"id": "req-1", "code": "factor(x^4 - 1)"}     // default op = eval
{"id": "n-1",  "code": "sqrt(2)", "numeric": true, "precision_digits": 20}  // V0.8
{"id": "p-1",  "op": "ping"}                    // -> {"ok":true,"op":"ping","pong":true}
{"id": "s-1",  "op": "symbols"}                 // -> live user symbol table (V0.6; see below)
{"id": "c-1",  "op": "config", "precision_digits": 20}  // session precision (V0.8)
{"id": "q-1",  "op": "shutdown"}                // -> {"ok":true,"op":"shutdown"}; worker exits
```

`code` runs in one **persistent** Sage namespace (assignments survive across
evals). It is **preparsed** (`sage.repl.preparse.preparse`, so `^` is power), then
parsed with `ast`: leading statements are `exec`'d and a trailing **expression**
is `eval`'d for a REPL-style value echo. A `None` result is suppressed (a bare
`print(...)` or an assignment echoes no value → `kind:"none"`, `value:false`).

`x` is predefined by Sage 9.5, but callers that rely on it should `x = var("x")`
explicitly.

### Eval request fields (V0.8 — exact/numeric)

| Request field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `numeric` | bool | `false` | **Force-numeric** for this request only: the **primary** result becomes its numeric approximation (`N()` at the effective precision); the exact form is preserved in `exact_value`. **Does not mutate the namespace** — `y = 1/3` then a `numeric:true` eval of `y` leaves `NS['y']` an exact `Rational`. |
| `precision_digits` | int > 0 | session default | **Per-request precision override** (decimal digits) for `approx` (and for the numeric primary when `numeric:true`). Overrides the session default *for this request only*; it does not change the session. |

---

## Responses

### Value envelope (the V0.3 result envelope)

```json
{
  "id": "req-1",
  "ok": true,
  "value": true,                 // did the eval echo a value? (vs a statement)
  "kind": "matrix",              // one of the fixed kind set
  "plain": "[1 2]\n[3 4]",       // str(value), capped — human-readable text
  "latex": "\\left(\\begin{array}{rr}\n1 & 2 \\\\\n3 & 4\n\\end{array}\\right)",
  "repr":  "[1 2]\n[3 4]",       // repr(value), capped — unambiguous fallback
  "approx": null,                // numeric approximation, or null (per policy)
  "approx_digits": null,         // precision of `approx` (decimal digits), or null (V0.8)
  "exact": null,                 // true|false|null — is the primary exact? (V0.8)
  "primary_is_approx": false,    // put "≈" on the primary value? (V0.8)
  "actions": ["det","rank","rref","eigenvalues","transpose","inverse"],
  "artifacts": [],               // V0.5 fills this (plot files etc.)
  "truncated": false,            // was plain/repr capped?
  "stdout": "",                  // user prints / raw fd writes, captured
  "stderr": ""
}
```

### Statement envelope (no echoed value)

```json
{ "id":"a", "ok":true, "value":false, "kind":"none",
  "plain":"", "latex":null, "repr":"", "approx":null, "actions":[],
  "artifacts":[], "truncated":false, "stdout":"hello\n", "stderr":"" }
```

### Error envelope

```json
{ "id":"e", "ok":false, "kind":"error",
  "plain":"rational division by zero", "latex":null,
  "repr":"rational division by zero", "approx":null,
  "actions":["copy_traceback"],
  "error": {"type":"ZeroDivisionError",
            "message":"rational division by zero",
            "traceback":"Traceback (most recent call last): ..."},
  "stdout":"", "stderr":"", "artifacts":[] }
```

### Interrupted envelope (V0.2 — SIGINT honored)

```json
{ "id":"i", "ok":false, "kind":"interrupted",
  "plain":"", "latex":null, "repr":"", "approx":null, "actions":[],
  "error": {"type":"KeyboardInterrupt","message":"eval interrupted","traceback":""},
  "stdout":"", "stderr":"", "artifacts":[] }
```

### Protocol-error envelope (unparseable request line)

```json
{ "id":null, "ok":false, "kind":"error",
  "error": {"type":"ProtocolError","message":"invalid JSON request: ..."},
  "stdout":"", "stderr":"", "artifacts":[] }
```

---

## Envelope fields

| Field | Type | Present when | Meaning |
| --- | --- | --- | --- |
| `id` | string \| null | always | Echoes the request id (null for unattributable protocol errors). |
| `ok` | bool | always | Did the eval succeed? `false` for error/interrupted. |
| `value` | bool | eval responses | Did the eval echo a value (vs a pure statement)? |
| `kind` | string | always | One of the fixed kind set (below). |
| `plain` | string | always | `str(value)`, capped at 8192. Human-readable. |
| `latex` | string \| null | always | Sage LaTeX, capped at 16384; `null` when it doesn't render (plot, text, some unknowns) or for error/interrupted. |
| `repr` | string | value/error/interrupted | `repr(value)`, capped at 8192. Unambiguous fallback; the **degrade target** for unknown kinds. |
| `approx` | string \| null | value/error/interrupted | Numeric approximation string, or `null` (per policy below). |
| `approx_digits` | int \| null | value/error/interrupted | Precision (decimal digits) `approx` carries; `null` when `approx` is null. (V0.8) |
| `exact` | bool \| null | value/error/interrupted | Is the **primary** result exact? `true` (integer/rational/exact-symbolic) · `false` (real/complex/inexact-symbolic) · `null` (kind where exactness isn't a scalar property). (V0.8) |
| `primary_is_approx` | bool | value/error/interrupted | Should the UI render `≈` on the **primary** value (the primary already is a float, or force-numeric) vs on the secondary line? (V0.8) |
| `exact_value` | string | only `numeric:true` evals | The original exact form, preserved while `plain` shows the numeric primary. (V0.8) |
| `actions` | string[] | value/error/interrupted | Result-kind-aware op names the UI can offer. May be empty (e.g. `boolean`). |
| `artifacts` | array | always | `[]` for non-plot results; for plots, one or more `{type,format,path,bytes}` image entries (V0.5; see "Artifacts" below). |
| `truncated` | bool | value/none | Was `plain`/`repr` capped? |
| `truncation` | object | only when `truncated` | `{plain_len, repr_len, plain_cap, repr_cap}` — original sizes + caps, so the UI can say "N of M chars". |
| `stdout` / `stderr` | string | always | Captured user output (incl. raw fd writes). |
| `error` | object | error/interrupted | `{type, message, traceback}`. |
| `op` | string | banner / ping / shutdown | The control op for non-eval responses. |
| `pid` | int | ready banner | The worker's **real** pid (SIGINT target). |

---

## The fixed kind set

```
integer  rational  real  complex  symbolic  relation
list     matrix    plot  text     boolean   none    error  unknown
```

Spec mapping: `equation / relation` → **relation**; `list / tuple` → **list**;
`symbolic expression` → **symbolic**. `boolean / none / error / unknown` are the
framing kinds beyond the spec minimum.

### Classification rules (worker `_classify`)

Keyed off `type(value).__module__` so it survives Sage's many concrete classes:

| Detector | Kind |
| --- | --- |
| `value is None` | `none` |
| `isinstance(value, bool)` *(checked before int)* | `boolean` |
| `sage.rings.integer` in module | `integer` |
| `sage.rings.rational` in module | `rational` |
| `sage.rings.real*` in module | `real` |
| `sage.rings.complex*` in module | `complex` |
| `number_field` + name has `gaussian`/`Cyclotomic` *(e.g. `3+4*I`)* | `complex` |
| `sage.matrix` in module | `matrix` |
| `sage.symbolic.expression` + `is_relational()` | `relation` |
| `sage.symbolic.expression` otherwise | `symbolic` |
| `sage.plot` in module / `Graphics` in name | `plot` |
| `isinstance(value, (list, tuple))` *(catches `solve()`'s Sequence)* | `list` |
| `isinstance(value, int / float / str)` | `integer` / `real` / `text` |
| anything else | `unknown` *(degrades to `repr`, never errors)* |

---

## Artifacts (V0.5 — the plot/image pipeline)

When an eval produces a Sage **plot** (a `Graphics` or `GraphicsArray`), the
worker saves it to image files and reports them in `artifacts`. Each plot yields
**two** entries — an **SVG** and a **PNG** of the same render — the SVG first:

```json
"artifacts": [
  {"type":"image","format":"svg","path":"/tmp/sagecalc/session-2502-d54.../plot-00001.svg","bytes":20587},
  {"type":"image","format":"png","path":"/tmp/sagecalc/session-2502-d54.../plot-00001.png","bytes":18896}
]
```

An entry's fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `type` | string | `"image"` (the only artifact type so far). |
| `format` | string | `"svg"` or `"png"`. |
| `path` | string \| null | Absolute path to the saved file; **`null` if that format failed to save** (then `error` is set). |
| `bytes` | int | File size on disk (present on success). |
| `error` | string | `"<ExcType>: <msg>"` — present only on a save failure for that format. |

A multi-plot eval (several `.show()`n plots, or a `GraphicsArray`) yields several
plots, hence several SVG+PNG pairs, in call order.

### Where plots come from (two capture channels)

1. **The echoed value** — if the eval's trailing expression *is* a plot (e.g.
   `plot(sin(x), (x,-pi,pi))`), it's saved.
2. **`.show()`** — the worker wraps `Graphics.show` / `GraphicsArray.show` so a
   headless `p.show()` **captures** the plot as an artifact instead of trying to
   open a GUI window. This is what makes "several plots in one eval"
   (`p.show(); q.show()`) work. De-duplicated by object identity, so a plot
   that is both shown and echoed is saved once.

A `.show()`-only eval (no echoed value) still returns `kind:"plot"` with the
artifacts attached (and `value:false`).

### Directory layout & lifetime (the policy)

- **Layout.** One session-scoped dir per worker process:
  `/tmp/sagecalc/session-<pid>-<rand>/`, created lazily on the first plot.
  `<pid>` ties it to this worker; the random suffix prevents collision if a pid
  is recycled.
- **Filenames.** A monotonic per-worker counter:
  `plot-00001.svg`, `plot-00002.svg`, … The counter never resets while the
  worker lives, so **no collision** across plots in one eval or across rapid
  successive evals.
- **Lifetime.** The dir lives as long as the worker. On a **clean shutdown**
  (`op:"shutdown"`) the worker `rmtree`s it. A **hard kill** skips cleanup, but
  the dir is `pid`+`rand`-namespaced under `/tmp` (OS-reaped) so it never
  collides with a future worker. The parent app may also delete the whole
  `/tmp/sagecalc/` tree on launch. Per-eval files are **not** deleted while the
  worker lives, so the UI can re-load an older tape entry's plot.

### Format reliability (the V0.5 finding, verified on screen)

Sage 9.5 saves **SVG, PNG, and PDF** cleanly for 2D plots. We save SVG+PNG. On
the rendering side (macOS, SwiftUI/AppKit `NSImage`):

- **PNG renders perfectly and is the reliable path.** `NSBitmapImageRep`
  decodes Sage/matplotlib PNG flawlessly; crisp at the row size and when zoomed.
- **SVG loads but renders WRONG.** `NSImage` *does* load these SVGs (via the
  system `_NSSVGImageRep`) and reports a sane size, but it **mis-rasterizes
  matplotlib's text-as-glyph `<use>`/`<defs>` so axis labels/ticks paint as a
  large opaque black blob** over the (correct) curve. Not a crash — the curve is
  there — but unusable. So **PNG is the default the UI should render**; SVG is
  kept (vector, future-proof) but needs a real SVG engine (a third-party
  renderer or rasterizing through WebKit/`librsvg`) before it's trustworthy on
  this stack. (Full detail in PROBLEMS.md.)

**Verdict for V1.7:** ship **PNG** as the rendered artifact; keep the SVG file
for export/zoom-to-vector later behind a proper SVG renderer.

### Plot failures are structured, never protocol-corrupting

- A **bad plot call** (`plot(sin(x), (x, 0, 'notanumber'))`) raises inside the
  eval → a normal **error envelope** (`ok:false, kind:"error"`), like any other
  exception. No artifacts.
- A **save failure** (unwritable dir, a `.save()` that raises) is caught
  per-format: that entry becomes `{"type":"image","format":"svg","path":null,
  "error":"..."}` and the eval **still returns `ok:true`** with whatever saved.
  One bad format never fails the eval or corrupts the JSONL wire. Proven: after
  forced save failures the very next `1+1` eval returns `2` cleanly.

---

## The `symbols` op (V0.6 — live symbol-table introspection)

Returns the **user-created** bindings in the live Sage namespace, classified and
summarized, so the app can render a Symbols sidebar (V1.6). Read-only: it never
runs user code and never mutates the namespace.

### Request / response

```json
{"id": "s-1", "op": "symbols"}
```

```json
{"id": "s-1", "ok": true, "op": "symbols",
 "symbols": [
   {"name": "A", "kind": "matrix",            "summary": "2×2 over Integer Ring"},
   {"name": "f", "kind": "symbolic function", "summary": "x |--> sin(x)/x"},
   {"name": "n", "kind": "integer",           "summary": "104729"},
   {"name": "x", "kind": "symbolic variable", "summary": "x"}
 ]}
```

Each entry is `{name, kind, summary}` (all strings). `symbols` is **sorted by
`name`** for a stable sidebar; it is `[]` before any user code.

| Field | Type | Meaning |
| --- | --- | --- |
| `name` | string | The binding's namespace name. |
| `kind` | string | One of the symbol-kind vocabulary (below). |
| `summary` | string | A short, **bounded** (`≤ 200` chars + ` …`), **cheap** one-line label. Never a full stringification of a large object. |

### Filtering policy — only user-created symbols

The worker snapshots the **pristine namespace** (`_SYMBOL_BASELINE = dict(NS)`)
*before any user code runs* — i.e. everything `from sage.all import *` injected
(`var`, `matrix`, `pi`, the predefined `x`, the exported functions `n`/`N`, the
Gaussian `i`, …), every dunder, all worker plumbing. A name surfaces iff it is:

- **absent** from the baseline (a brand-new name — the common case), **or**
- **present** in the baseline but now bound to a **different object** (the user
  *reassigned* a name Sage already used).

The diff is by **object identity against the retained baseline objects**
(`live is not baseline_obj`), not by name — because Sage exports very common
variable names (`n` = `numerical_approx`, `N`, `i` = Gaussian unit), so a
name-only diff would hide a user's `n = 104729`. Retaining the objects (not just
their `id()`) avoids an `id`-recycle false-hide. Dunder names (`__…__`) are
skipped as a belt-and-suspenders guard. **Result: no Sage builtin, import, or
worker internal ever leaks into the sidebar** (proven: `[]` before user code; a
23-name junk probe finds nothing).

Deleted names (`del n`) vanish (gone from `NS`). Reassigned names re-classify and
re-summarize from their **current** value every call (the op reads `NS` live).

### Kind vocabulary

The V0.3 result kinds — `integer rational real complex symbolic relation list
matrix plot text boolean none unknown` (classified by the shared `_classify`) —
**plus four symbol-table-only kinds**:

| Kind | When | Detection |
| --- | --- | --- |
| `symbolic variable` | a bare SR symbol, `x = var("x")` | Expression with `value.is_symbol()` |
| `symbolic function` | a callable symbolic expr, `f(x) = sin(x)/x` | Expression whose `parent()` is a `Callable…` ring (Sage preparses `f(x)=…` to a callable-expression **assignment**, so it's a normal binding and *does* appear) |
| `module` | a user `import numpy` | `isinstance(value, types.ModuleType)` |
| `function` | a user `def`/lambda | `isinstance(value, FunctionType/Lambda/BuiltinFunction)` |

(`error` from the result set does not occur here — bindings are values, not eval
outcomes.) A user-defined **class** lands as `unknown` (a type isn't any math
kind), which is fine — it still shows.

### Summary policy — bounded **and** cheap (no big computation, no huge output)

Summaries are **structural**, computed from metadata, never by stringifying a
large object:

- **matrix** → `"<rows>×<cols> over <base ring>"` from `nrows()/ncols()/
  base_ring()` (e.g. `"200×200 over Integer Ring"`) — never renders the cells.
- **list / tuple / set / dict / Sequence** → `"list of N items"` (or the type
  name) from `len()` only — never the elements. So `big_list = list(range(10**6))`
  → `"list of 1000000 items"`, **not** a 7.9 MB string.
- **module** → its dotted `__name__`; **function** → `"<name>()"`; **plot** →
  `"graphics"`.
- **symbolic variable / function / scalar / everything else** → a capped
  `str(value)` (`x`, `x |--> sin(x)/x`, `104729`, `hello`, …).

Everything is finally passed through a `≤ 200`-char cap. An object whose
`__repr__`/`__str__` **raises** degrades to `"<unprintable: …>"` — the op never
crashes. **Measured:** the `symbols` op over a namespace holding a 200×200 matrix
and a million-item list returns in **~0.6–0.9 ms** (cheap summary ~1e-5 s vs
`str()` ~0.05 s + megabytes). Inspection is safe to call on every keystroke.

---

## The `config` op (V0.8 — session settings)

Session-level configuration. Currently one setting: `precision_digits`, the
default decimal precision for the envelope's `approx` field (and the numeric
primary in force-numeric mode). Persists for the worker's lifetime until changed.

```json
{"id":"c-1","op":"config","precision_digits":20}   // setter
{"id":"c-2","op":"config"}                          // getter (no setting field)
// response:
{"id":"c-1","ok":true,"op":"config","precision_digits":20}
```

Default is **10**. A non-positive / non-int `precision_digits` is rejected
(`ok:false`, `error:{type:"ValueError",…}`) and the session is left unchanged.
See the full exact/numeric policy below for how this interacts with the
per-request `precision_digits` override and `numeric:true`.

---

## Exact / numeric display policy (V0.8 — the product policy)

The display rule: an **exact** result is the **primary** value; its
approximation is **secondary** (rendered with `≈`, or on demand). The spec's
desired display for `1/3 + 1/5`:

```text
8/15
≈ 0.5333333333
```

### `exact` (true | false | null)

**Decided per kind — NOT off `parent().is_exact()`**, because the entire
Symbolic Ring reports `is_exact() == False`, which would mislabel `sqrt(2)`,
`pi`, `sin(1)` as inexact.

| Kind | `exact` |
| --- | --- |
| `integer`, `rational` | `true` (exact rings) |
| `real`, `complex` | `false` (a float-backed `RealLiteral`/`RealNumber`/mpc is approximate by nature — incl. `N(...)` and a `2.5` literal) |
| `symbolic` | `true` **unless** the expression contains an inexact numeric atom. `sqrt(2)`, `pi`, `sin(1)`, `sin(pi/3)`, `sqrt(2)+pi` → `true`; `2.5+sqrt(2)`, `1.5*x` → `false`. |
| matrix, list, relation, plot, text, boolean, none, error, unknown | `null` (exactness isn't a scalar property) |

The symbolic discriminator is a recursive `operands()` tree-walk: a leaf is
inexact iff `is_numeric()` and its `pyobject().parent().is_exact()` is False.

> **TRAP (PROBLEMS.md):** `sin(1)` stays **symbolic and exact** in Sage (it is
> *not* evaluated to a float). A definite integral / limit (`integrate(x^2,
> (x,0,1))` → `1/3`) is also `kind:"symbolic"` yet exact — don't key "is exact?"
> off the kind being `rational`/`real`.

### `primary_is_approx`

- `false` for an exact result → exact form is primary, `approx` is the `≈`
  secondary line.
- `true` when the primary already **is** a float (a `real`/`complex`, an inexact
  symbolic) — the `≈` goes on the primary; secondary `approx` is `null`.
- `true` for a force-numeric (`numeric:true`) eval.

### `approx` / `approx_digits`

Computed **per kind**, never blindly:

- `integer / boolean / none / text / list / matrix / relation / plot / error` →
  `approx:null` (an integer is already exact; a matrix/list approx isn't a
  scalar; a relation/plot has no single number).
- `rational / real / complex / symbolic` → a decimal string at `approx_digits`
  precision, **only if the result is constant** (free `variables()` empty;
  `x^2+5*x+6` → `null`).
- **Precision is clamped** to a concrete value's own `prec()`, so `.n(bits)`
  never raises Sage's "cannot approximate to N bits, use at most M" (PROBLEMS.md).
  A high-precision real (`N(sqrt(2),digits=50)`, 170 bits) shows 10 digits cleanly
  and is never downcast in storage; a 53-bit complex asked for 40 digits is
  clamped, not raised. Exact values get the full requested precision.

### Configurable precision

- **Session default** via the `config` op (default **10**, matching the spec's
  `0.5333333333`):
  ```json
  {"op":"config","precision_digits":20}   // setter; omit the field to read it
  // -> {"ok":true,"op":"config","precision_digits":20}
  ```
- **Per-request override** via the `precision_digits` eval field — applies to
  that request only, does not change the session.
- Non-positive / non-int precision is rejected (`ok:false`), session unchanged.

### Force-numeric — no session pollution

`{"code":"y","numeric":true}` makes the **primary** result the numeric value
(`N()` at the effective precision); the exact form is preserved in `exact_value`.
It is a **display re-presentation only**: the eval runs normally (the namespace
stays exact), then `N()` is applied to the *echoed* value. Proven: after
`y = 1/3` then a `numeric:true` eval of `y`, the next normal `y` is `1/3` and
`parent(y)` is `Rational Field`.

---

## `actions` map (UI-driving metadata)

Names only; V1.10 maps a chosen action on result `R` to a follow-up eval
(e.g. "det" on matrix `A` runs `A.det()`).

| Kind | Actions |
| --- | --- |
| `integer` | `factor`, `is_prime`, `next_prime`, `approx`, `hex` |
| `rational` | `numerator`, `denominator`, `approx`, `continued_fraction` |
| `real` | `approx_more_digits`, `round`, `continued_fraction` |
| `complex` | `real_part`, `imag_part`, `abs`, `arg`, `conjugate` |
| `symbolic` | `simplify`, `trig_simplify`, `factor`, `expand`, `approx`, `diff`, `integrate` |
| `relation` | `solve`, `lhs`, `rhs`, `subtract_sides` |
| `matrix` | `det`, `rank`, `rref`, `eigenvalues`, `transpose`, `inverse`, `column_space`, `row_space`, `right_kernel` |
| `list` | `length`, `sort`, `sum`, `set` |
| `plot` | `save_png`, `save_svg`, `show` |
| `text` | `copy` |
| `boolean` | *(none)* |
| `unknown` | `repr`, `type` |
| `error` | `copy_traceback` |

---

## Truncation policy

`plain` and `repr` are capped at **8192 chars**, `latex` at **16384**. On
overflow: append `" …"`, set `truncated:true`, and emit a `truncation` object with
the original `plain_len`/`repr_len` and the caps. Error messages and tracebacks
are capped the same way. Proven against `list(range(10^6))` (~7.9 MB) and
`factorial(10^5)` (~456 KB).

---

## Lifecycle states (parent-side; V0.2)

The `SessionController` maps worker envelopes + its own timeouts to:
`idle / running / completed / error / interrupted / timed_out / crashed /
restarting`. SIGINT (to the real pid) escalates to a hard process-group kill if
the worker won't yield. See `v0/02-lifecycle/` and PROBLEMS.md.
