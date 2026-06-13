# Completions Guide

The catalog of every completion Casette currently ships. A completion is a
friendly command word that (a) compiles to Sage through `FriendlyCompiler`
and (b) — for every entry below except `forget` — grows a Numbers-style
formula bar under the input: a pinned function chip plus editable token
pills that rewrite the draft as you fill them.

This file documents the *vocabulary*. The architecture contract (draft as
single source of truth, typed IRs, the compile boundary, the partial-edit
round-trip rule) lives in [COMPLETION-UI.md](COMPLETION-UI.md). The original
design catalog these were cut from is `COMPLETIONS-HITLIST.md` at the repo
root.

## How to read an entry

```text
trigger (aliases)          what you type
chips                      the editable tokens in the lane
lowers to                  the generated Sage (shown live in the preview line)
```

Conventions that apply everywhere:

- **Friendly in, Sage out.** The bar edits friendly text, never Sage. The
  `↪` preview line under the input always shows the exact Sage that Return
  will evaluate.
- **`#ROW` tape references** (`factor #14 + 2`) stay verbatim in the bar and
  the draft; they expand to `__casette_tape_refs[ROW]` only at the compile
  boundary.
- **Call syntax bypasses.** A command word is only a command when followed by
  a space (or alone): `det A` is friendly; `det(A)`, `factorial(5)`,
  `subs(...)` are raw Sage, untouched.
- **Aliases display canonical.** Typing `determinant A` or
  `prime_factorization 60` renders the bar and draft with the canonical word
  (`det`, `factor_integer`).
- **Ranges** are written `var=lo..hi` and render as one semantic bounds
  group (`lower .. upper`), never as independent optional chips.
- **Keyboard.** Tab from the editor enters the lane's first token when a bar
  is showing; Tab/Shift-Tab walk the tokens. Return submits from the main
  editor.

---

## Expression transforms

| Trigger | Aliases | Chips | Lowers to |
| --- | --- | --- | --- |
| `expand (x+1)^5` | — | expr | `expand((x+1)^5)` |
| `factor x^4 - 1` | — | expr | `factor(x^4 - 1)` |
| `simplify sin(x)^2 + cos(x)^2` | — | expr | `(…).simplify_full()` (so trig identities collapse) |
| `latex x^2/2` | — | expr | `latex(x^2/2)` |

## Equation solving

```text
solve x^2 + 5*x + 6 = 0            chips: eqn · for var(optional)
solve x^2 - 4 = 0 for x        →   solve(x^2 - 4 == 0, x)
```

The body needs a single `=` (translated to Sage `==`). Without `for`, one
free variable is used automatically; several free variables raise the
ambiguity picker (one candidate per variable). A bare expression without `=`
is an error by frozen contract — write the `= 0` yourself.

## Calculus

```text
integral x^2                   →   integrate(x^2, x)          chips: expr · var · lower..upper(optional)
integral x^2, x=0..1           →   integrate(x^2, (x, 0, 1))
integral x*y, wrt y            →   integrate(x*y, y)
double integral x*y, x=0..1, y=0..x
                               →   integrate(integrate(x*y, (y, 0, x)), (x, 0, 1))
                                   (outer range first, inner last; no bar — typed form only)

derivative sin(x^2)            →   derivative(sin(x^2), x)    chips: expr · var · order(optional)
  aliases: diff                    (single free variable inferred)
derivative sin(x), 2           →   derivative(sin(x), x, 2)   (trailing all-digits clause = order)
derivative x*y, 2 wrt y        →   derivative(x*y, y, 2)

limit sin(x)/x, x->0           →   limit(sin(x)/x, x=0)       chips: expr · var → point · direction
limit 1/x, x->0, right         →   limit(1/x, x=0, dir='+')   (direction: both/left/right menu)
limit 1/x, x->0, left          →   limit(1/x, x=0, dir='-')

taylor sin(x), x=0, order=7    →   taylor(sin(x), x, 0, 7)    chips: expr · var = around · order

sum k^2, k=1..n                →   sum(k^2, k, 1, n)          chips: expr · index · lower..upper
product 1 + 1/k, k=1..n        →   product(1 + 1/k, k, 1, n)  chips: expr · index · lower..upper
```

## Plotting

```text
plot sin(x), x=-pi..pi         →   plot(sin(x), (x, -pi, pi))     chips: expr · var · lower..upper
                                   (a range is required — by frozen contract there is no default)

parametric_plot (cos(t), sin(t)), t=0..2*pi                       chips: x(t) · y(t) · var · lower..upper
  aliases: parametric plot     →   parametric_plot((cos(t), sin(t)), (t, 0, 2*pi))

implicit_plot x^2 + y^2 = 1, x=-2..2, y=-2..2                     chips: eq · x lower..upper · y lower..upper
  aliases: implicit plot       →   implicit_plot(x^2 + y^2 == 1, (x, -2, 2), (y, -2, 2))
```

Implicit-plot equation sugar: a single `=` becomes `==`; `==` passes
through; no equals at all is normalized to `EXPR == 0`. Both axis ranges are
required.

## Linear algebra

Matrix payloads accept Sage row lists (`[[1,2],[3,4]]`) and MATLAB-style
literals (`[1,2; 3,4]`), which normalize to Sage form. The method commands
also take anything matrix-valued — a variable, an expression, or a tape
reference — lowering to a parenthesized method call.

| Trigger | Aliases | Lowers to (literal) | Lowers to (variable) |
| --- | --- | --- | --- |
| `matrix [1,2; 3,4]` | — | `matrix([[1,2],[3,4]])` | — |
| `vector [1,2,3]` | — | `vector([1,2,3])` | (bracketed list required) |
| `det [1,2; 3,4]` | `determinant` | `matrix([[1,2],[3,4]]).det()` | `det A` → `(A).det()` |
| `inverse M` | — | `matrix(…).inverse()` | `(M).inverse()` |
| `transpose M` | — | `matrix(…).transpose()` | `(M).transpose()` |
| `rank M` | — | `matrix(…).rank()` | `(M).rank()` |
| `rref M` | — | `matrix(…).rref()` | `(M).rref()` |
| `eigenvalues M` | `eigenvalue` | `matrix(…).eigenvalues()` | `(M).eigenvalues()` |
| `eigenvectors M` | `eigenvector` | `matrix(…).eigenvectors_right()` | `(M).eigenvectors_right()` |

All show a single chip: the kind's name pinned, one matrix/entries token.

## Vector calculus

```text
gradient x^2 + y^2             →   (x^2 + y^2).gradient()         chips: expr · vars(optional)
  aliases: grad
gradient x^2*y + z, [x,y,z]    →   (x^2*y + z).gradient([x, y, z])

hessian x^2 + x*y + y^2        →   (…).hessian()                  chips: expr
                                   (expression only; Sage's symbolic hessian takes no var list)

jacobian [x^2+y, sin(x*y)], [x,y]                                 chips: fns · vars
                               →   jacobian([x^2+y, sin(x*y)], [x, y])
```

## Substitution & numeric

```text
subs x^2 + y, x=3, y=4         →   (x^2 + y).subs(x=3, y=4)       chips: expr · at (one bindings token)
  aliases: substitute

numeric pi                     →   N(pi)                          chips: expr · digits(optional)
  aliases: approx, decimal
numeric sqrt(2), 50            →   N(sqrt(2), digits=50)
```

## Symbols & assumptions

```text
var a b c                      →   var('a b c')                   chips: names
var a, b, c                    →   var('a b c')
                                   (`var = 3` is still the plain assignment echo, not a command)

assume x > 0                   →   assume(x > 0)                  chips: condition
assume x real                  →   assume(x, 'real')
assume n is integer            →   assume(n, 'integer')
assume x positive              →   assume(x > 0)
assume x negative              →   assume(x < 0)

forget                         →   forget()                       (no bar — nothing to edit;
forget all                     →   forget()                        the preview line confirms)
```

Known `assume` properties: real, integer, rational, complex, imaginary,
even, odd, noninteger — plus the positive/negative comparison sugar. Any
comparison (`<`, `>`, `<=`, `>=`, `==`, `!=`) passes through verbatim.

## Combinatorics & number theory

```text
choose 10, 3                   →   binomial(10, 3)                chips: n · k
factorial 5                    →   factorial(5)                   chips: expr
gcd 12, 18                     →   gcd(12, 18)                    chips: a · b(optional)
gcd [12, 18, 24]               →   gcd([12, 18, 24])
gcd 12, 18, 24                 →   gcd([12, 18, 24])              (3+ args collect into a list)
lcm 4, 6                       →   lcm(4, 6)                      (same forms as gcd)
is_prime 104729                →   is_prime(104729)               chips: expr
factor_integer 3600            →   factor(3600)                   chips: expr
  aliases: prime_factorization
```

## Statistics

```text
mean [1, 2, 3]                 →   sum([1, 2, 3])/len([1, 2, 3])  chips: expr
```

`mean` is an owned lowering — Sage's global `mean()` was removed upstream —
and stays exact (`mean [1,2,3]` → `2`, not `2.0`).

---

## Not implemented (and why)

| Entry | Reason |
| --- | --- |
| `stddev` | No stable Sage backend (`std()` deprecated/removed upstream); an owned sample-stddev expression repeats the payload three times — unreadable as user-visible Generated Sage. |
| `solve EXPR, x` (`== 0` normalization) | The frozen V0.7 contract (`solveWithoutEquals`) pins that a bare-expression solve errors. Write the `= 0`. |
| `plot` default range (`-10..10`) | The frozen contract (`plotNoRange`) pins that a rangeless plot errors. |
| `n choose k` (infix) | The compiler is a leading-command shim; infix spellings don't match. `choose n, k` covers it. |
| Everything else in `COMPLETIONS-HITLIST.md` | Not yet scheduled — the hitlist remains the backlog (find_root, desolve, plot3d/contour/density/list plots, complex/trig/log helpers, mod arithmetic, sets, polynomial accessors, …). |

## Adding a completion

Follow the Extension Rule in [COMPLETION-UI.md](COMPLETION-UI.md): typed IR
in `FriendlyCompiler` + `FormulaIR` case, tolerant parsing (partial edits
must round-trip — add your family to `PartialEditInvarianceTests`), a bar on
the shared `FormulaFunctionChip`/`FormulaTokenField` vocabulary, and the
lowering behind the frozen-contract tests.
