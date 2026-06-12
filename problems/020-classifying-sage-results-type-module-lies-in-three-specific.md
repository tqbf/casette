## Classifying Sage results: type module lies in three specific ways

Building the V0.3 result classifier (`worker._classify`), three Sage types refused
to land where their math suggested. Key off `type(value).__module__`, but special-case:

1. **`3 + 4*I` is not a complex — it's a number-field element.** Its type is
   `NumberFieldElement_gaussian` in `sage.rings.number_field.number_field_element_quadratic`
   — it's an element of `QQ[i]`, *not* under `sage.rings.complex*`. A naive
   `"sage.rings.complex" in mod` check misses every Gaussian literal. Fix: add an
   explicit branch for `number_field` modules whose type name is Gaussian/Cyclotomic.

2. **`solve(...)` returns a `Sequence_generic`, not a list.** Type is
   `sage.structure.sequence.Sequence_generic`. It *subclasses* `list`, though, so an
   `isinstance(value, (list, tuple))` branch catches it (lands as `list`) — but only
   if that branch exists *and* runs after the Sage-module checks. Don't assume
   `type(...).__module__ == 'builtins'` for list-likes.

3. **`bool` is an `int` subclass.** `isinstance(True, int)` is `True`, so you must
   test `boolean` *before* `integer` or `True`/`False` classify as integers.

Corollary: **unknowns still render LaTeX.** A `Permutation` is `kind:"unknown"` yet
`latex(value)` happily returns `[2, 1, 3]`. So compute `latex` best-effort for every
kind, not just the math ones; it just returns `None` when Sage can't.

---
