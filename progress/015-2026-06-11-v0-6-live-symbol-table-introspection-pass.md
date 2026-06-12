## 2026-06-11 — V0.6: Live symbol-table introspection — PASS

**Did.** Added a read-only `symbols` op to the **one canonical worker**
(`v0/01-worker-protocol/worker.py`, extended in place) and a Python harness
(`v0/06-symbol-table/`) that drives the spec sequence through a live worker —
**24/24 checks**. The op returns the user-created bindings as
`{name, kind, summary}`, sorted by name. No worker regression: V0.1 18/18 · V0.2
35/35 · V0.3 97/97 · V0.5 88/88. `pgrep -fl "sage -python"` clean.

**How it works.** At startup, right after `exec("from sage.all import *", NS)`,
the worker snapshots the **pristine namespace** (`_SYMBOL_BASELINE = dict(NS)` —
the star-import, dunders, plumbing). The op diffs the live `NS` against it: a
name surfaces iff it's **new** OR **rebound to a different object**
(`live is not baseline_obj`). Each surfaced value is classified (`_symbol_kind`,
which extends V0.3's `_classify`) and summarized cheaply (`_symbol_summary`).

**Exit criteria — all PASS (executed evidence in README):**
- **User symbols appear** — spec sequence → `x` (symbolic variable, "x"),
  `A` (matrix, "2×2 over Integer Ring" via `parent()` dims+base ring),
  `f(x)=sin(x)/x` (symbolic function, "x |--> sin(x)/x"), `n` (integer,
  "104729").
- **Junk filtered** — `[]` before any user code; a 23-name probe
  (`var matrix SR ZZ pi x i e I __builtins__ NS preparse latex …`) finds nothing.
- **Deleted disappears** — `del n` → n gone.
- **Reassigned updates** — `n=5` → integer "5"; `n="hello"` → text "hello"
  (kind+summary re-derived live each call).
- **Summaries bounded** — `M = matrix(ZZ,200,200,…)` → "200×200 over Integer
  Ring" (25 ch); `big_list = list(range(10**6))` → "list of 1000000 items"
  (21 ch), NOT the 7.9 MB string. Cap = 200 ch.
- **No huge computation** — the op over M + big_list returns in **~0.6–0.9 ms**
  (timed in-harness). Cheap structural summary ~1e-5 s vs `str()` ~0.05 s and
  megabytes; the op never `str()`s a matrix or a big container.
- **Bonus robustness** — a `Boom` whose `__repr__`/`__str__` raise →
  "<unprintable: …>", op survives, shape intact; `import numpy` → module
  "numpy"; `def g` → function "g()"; wire intact (`1+1`→`2`) afterward.

**Kind vocabulary.** V0.3's kinds plus four symbol-table-only kinds:
`symbolic variable` (SR `is_symbol()`), `symbolic function` (callable-expression
`parent()`), `module` (`types.ModuleType`), `function`
(`types.FunctionType/Lambda/Builtin`). A user-defined class → `unknown` (a type
isn't a math kind) but still shows. Frozen in plans/WORKER-PROTOCOL.md.

**Learned / surprised.**
- **The diff MUST be by object identity, not name** — and this was the only real
  trap. Sage's `from sage.all import *` exports `n` (= `numerical_approx`), `N`
  (also `numerical_approx`), and `i` (the Gaussian unit) as builtins. A name-only
  baseline diff therefore **hid the spec's own `n = 104729`** (it "already
  existed"). First harness run was 20/24 for exactly this reason. Fix: snapshot
  the pristine **objects** and surface a baseline name when it's rebound to a
  *different* object. → PROBLEMS.md.
- **Retain the baseline objects, not their `id()`s.** If the baseline only stored
  `id()` ints, a freed baseline object's id could be recycled by a later user
  object and make `==` on ids lie. Holding the objects + using `is` is exact.
- **`f(x) = sin(x)/x` is "just" an assignment.** Sage preparses it to an
  assignment of a *callable symbolic expression* (parent = a `Callable…` ring,
  str = `x |--> sin(x)/x`), so it lands as a normal binding and needs no special
  eval path to surface — only a kind detector.
- **Bounded ≠ slow.** The win is summarizing **structurally** (matrix dims, list
  `len`) instead of stringifying. That's what makes inspection both bounded AND
  ~microseconds — the same move solves "don't emit 7.9 MB" and "don't take 50 ms"
  at once.

**Next.** V0.7 — friendly input compiler. V1.6 (Symbols sidebar) should call the
`symbols` op (cheap enough to refresh after every eval), render
`{name, kind, summary}`, and rely on it never leaking Sage internals or
stringifying huge values.

---
