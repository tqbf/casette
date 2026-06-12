## Numeric approximation: respect the value's native precision; `digits=` can raise

For the envelope's `approx` field, the obvious `value.n(digits=15)` has two traps:

- **It downcasts high-precision reals.** `N(sqrt(2), digits=50)` is a 50-digit
  `RealNumber`; `.n(digits=15)` quietly truncates it back to 53-bit, throwing away
  the precision the user explicitly asked for. For a value that's *already* a
  concrete real/complex, use `str(value)` (its native decimal); only call `.n()` for
  things that need approximating (rationals, symbolic constants).
- **`digits=` can raise on an already-low-precision object.** `CC(3,4).n(digits=15)`
  raises `TypeError: cannot approximate to a precision of 54 bits, use at most 53
  bits` — 15 decimal digits ⇒ 54 bits > the object's 53. Use **no `digits=` arg**
  (native precision) and the call succeeds.

Also: `approx` must be **per-kind**, not blind. `value.n()` on a matrix returns a
*matrix of floats* (not a scalar), and on a symbolic expr with free variables
(`x^2+5*x+6`) raises `TypeError`. Gate it: only rational/real/complex/symbolic, and
for symbolic only when `value.variables()` is empty.

---
