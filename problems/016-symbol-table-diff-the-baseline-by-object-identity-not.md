## Symbol table: diff the baseline by OBJECT IDENTITY, not name — Sage exports `n`/`N`/`i`

**The trap (V0.6).** The `symbols` op shows only user-created bindings, so it
diffs the live namespace against a baseline snapshotted before any user code
(everything `from sage.all import *` injects). The obvious diff is by **name**:
"surface a name that isn't in the baseline." That's **wrong**, and it fails on a
spec test case.

`from sage.all import *` exports a bunch of **very common single-letter variable
names** as builtins:

- **`n`** is `numerical_approx` (a function).
- **`N`** is also `numerical_approx`.
- **`i`** is the Gaussian unit (a `NumberFieldElement_gaussian`).

So when the spec does `n = 104729`, the name `n` was *already in the baseline* —
a name-only diff hides it. The first harness run was **20/24** for exactly this:
`n` never appeared, and its reassignments couldn't be tested. (Other names a user
will reach for — `N`, `i`, and depending on imports more — hit the same wall.)

**The fix.** Snapshot the baseline **objects** (`_SYMBOL_BASELINE = dict(NS)`)
and surface a name iff it is **absent** from the baseline OR **rebound to a
different object** (`live_value is not baseline_obj`). The identity check catches
"user reassigned a name Sage already used" while still hiding the untouched
builtins. Brand-new names (the common case) surface trivially.

**Two corollaries that matter:**
1. **Retain the objects, not their `id()`s.** If the baseline stored only
   `id()` integers, a freed baseline object's id could be **recycled** by a later
   user object bound to that same name, and an id-equality check would wrongly
   *hide* the user's symbol. Holding the actual objects and using `is` is exact
   and immune to id reuse.
2. **`del n` then re-check works for free.** `del n` removes the user binding
   entirely (it does *not* restore Sage's `numerical_approx`), so the name is
   simply gone from `NS` and the op omits it — no special-casing.

**Bounded summaries are also CHEAP summaries — by being structural.** The other
half of the op's safety is never stringifying a large object. The lever is to
summarize from **metadata**: a matrix → `"<r>×<c> over <base ring>"` from
`nrows/ncols/base_ring` (microseconds), a container → `"list of N items"` from
`len` (microseconds) — *not* `str(value)`. Measured: a 200×200 matrix and a
million-item list summarize in ~1e-5 s each, vs `str()` at ~0.05 s and megabytes;
the whole `symbols` op over both returns in ~0.6 ms. So "don't put 7.9 MB on the
wire" and "don't take 50 ms" are the **same fix**. (And wrap every summary in a
`try/except` → `"<unprintable: ExcType>"`, because a user object's `__repr__`
can raise.)

---
