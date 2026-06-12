## Numeric precision: clamp the request to the value's own `prec()` or `.n(bits)` raises

**The trap (V0.8, extends the V0.3 `digits=` lesson).** To approximate a value to
N decimal digits you convert to bits (`ceil(N*log2(10))`) and call `.n(bits)`.
But a **concrete** real/complex has a *fixed native precision*, and asking for
MORE bits than it holds raises:

```
CC(3,4).n(digits=15)  -> TypeError: cannot approximate to a precision of 54 bits,
                          use at most 53 bits
```

A configurable-precision feature WILL ask for arbitrary digit counts, so this
fires in normal use (e.g. "show this 53-bit result to 40 digits"). The V0.3
work-around was "use `str(value)` for concrete reals" — but that can't honor a
request for *fewer* digits (show `N(sqrt(2),digits=50)` at 10).

**The fix — one path that clamps:** if the value has a `prec()`, request
`min(bits_wanted, value.prec())` bits; otherwise (rational / symbolic-constant)
pass the full requested `digits=`. So:

- `N(sqrt(2),digits=50)` (170 bits) asked for 10 digits → 10 digits, no raise,
  and the **stored** object is never downcast.
- `CC(3,4)` (53 bits) asked for 40 digits → clamped to 53, no raise.
- `8/15` (exact rational) asked for 20 digits → full 20 digits.

**Force-numeric must be display-only, or it pollutes the namespace.** The
temptation is to `N()` the assignment. Don't: evaluate normally (so `y = 1/3`
stores an exact `Rational`), then apply `N()` only to the *echoed* value for
display. Namespace isolation then needs zero extra machinery — the next normal
eval of `y` is exactly `1/3` and `parent(y)` is still `Rational Field`.

---
