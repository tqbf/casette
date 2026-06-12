## 2026-06-11 — V0.3: Result envelope & type classification — PASS

**Did.** Turned the worker's rough V0.1 `kind` into a real result model: a proper
classifier + envelope builder in the **one canonical worker**
(`v0/01-worker-protocol/worker.py`, extended in place). Test harness under
`v0/03-result-envelope/` — **97/97 checks**, no stray Sage processes.

- Replaced `_classify`/`_safe_plain`/`_safe_latex` with `_classify` (a frozen
  14-kind set) + `_build_envelope`, which emits the V0.3 envelope:
  `kind, plain, latex, repr, approx, actions, artifacts, truncated` (+ a
  `truncation` policy object when capped). Error/interrupted envelopes gained the
  same shape (`repr`/`approx`/`actions`) so the contract is uniform.
- Documented and **froze** the protocol + envelope in
  `plans/WORKER-PROTOCOL.md` (fields, kinds, approx/actions policy, truncation,
  framing) and added it to PLAN.md's Documents table. V0.4+/V1 build against it.
- `harness.py` drives every spec case (`ZZ(104729)`, `1/3+1/5`, `sqrt(2)`,
  `N(sqrt(2),digits=50)`, `sin(pi/3)`, `x^2+5*x+6`, the `== 0` relation, `solve`,
  `matrix`, `rref`) plus `complex` (`3+4*I`), `plot`, `text`, `error` (`1/0`),
  an `unknown` (`Permutation([2,1,3])`), and huge outputs — asserting kind
  stability and envelope sanity for each.

**Exit criteria — all PASS (evidence in README):** every common result has a
**stable kind** (13 cases matched exactly); every value-bearing result has
non-empty `plain`; math results carry **LaTeX** (rational `\frac{8}{15}`, matrix
`array`, relation `… = 0`, even the unknown Permutation); **unknown degrades to
repr, not failure** (`Permutation` → `ok:true, kind:unknown, repr:"[2, 1, 3]"`);
**large outputs capped** with a flag + policy (`list(range(10^6))` → `truncated`,
8192 of 7,888,890 chars; `factorial(10^5)` → 8192 of 456,574); **actions drive the
UI** (matrix → `det/rank/rref/eigenvalues/transpose/inverse`, etc.).

**Policy decisions (the load-bearing ones).**
- **`approx` is per-kind, not blind.** Only rational/real/complex/symbolic-constant
  get a numeric approximation; integer/matrix/list/relation/plot/boolean → `null`
  (an integer is already exact; a matrix approx isn't a scalar). A symbolic expr
  with **free variables** (`x^2+5*x+6`) → `null`; a constant one (`sin(pi/3)`) →
  `0.866…`. High-precision reals keep their **own** precision via `str(value)` —
  `.n()` silently downcasts `N(sqrt(2),digits=50)` to 53-bit.
- **`actions` is a static per-kind name table.** The proof that result metadata can
  drive UI; V1.10 maps a chosen action to a follow-up eval.
- **Truncation is explicit.** `plain`/`repr` capped at 8192, `latex` at 16384, with
  a `truncation{plain_len,repr_len,plain_cap,repr_cap}` object so the UI can say
  "N of M chars". Never an unbounded string on the wire.

**Learned / surprised.**
- **`3 + 4*I` is not a `sage.rings.complex` object** — it's a
  `NumberFieldElement_gaussian` (an element of `QQ[i]`, module
  `sage.rings.number_field.…`). The rough V0.1 classifier's `mod` check would have
  missed it; added an explicit Gaussian/cyclotomic number-field branch → `complex`.
- **`solve(...)` returns a `Sequence_generic`, not a plain list** — but it
  subclasses `list`, so `isinstance(v,(list,tuple))` catches it. No special case
  needed; it lands as `list` with the solve roots inside.
- **`bool` is an `int` subclass** — must test `boolean` *before* `integer` or
  `True` classifies as integer.
- **`.n(digits=15)` can raise on an already-53-bit `ComplexNumber`** ("cannot
  approximate to 54 bits, use at most 53") — so the approx path uses the value's
  *native* precision (`.n()` no-arg, or `str` for concrete reals/complexes), never
  a fixed `digits=`.
- **Unknowns still carry LaTeX.** A `Permutation` is `kind:unknown` yet
  `latex(value)` renders `[2, 1, 3]` — so `latex` is best-effort regardless of kind.

**Next.** V0.4 — LaTeX rendering in SwiftUI/Textual. Render the envelope's `latex`
field beautifully; keep a `MathRenderer` abstraction so we're not trapped if one
path falls short.

---
