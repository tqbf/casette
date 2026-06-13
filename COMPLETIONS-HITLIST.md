## Core rule shape

I’d model a completion rule as:

```text
trigger
display label
argument chips
accepted calculator spelling
Sage lowering
validation / defaults
```

Example:

```text
integral
∫  INTEGRAL
expr, var, [lower .. upper]
integral x^2
integral x^2, x=0..1
integral(x^2, x)
integral(x^2, x, 0, 1)
```

Important design rule: **your UI language should not be Sage syntax**. It should be calculator syntax that lowers to Sage.

---

# Expression transformation rules

## `expand`

```text
expand expr
```

Lowers to:

```python
expand(expr)
```

Examples:

```text
expand (x+1)^3
expand sin(x+y)
```

Chips:

```text
expr (x+1)^3
```

Notes: canonical beginner operation. Should rank very high.

---

## `factor`

```text
factor expr
```

Lowers to:

```python
factor(expr)
```

Examples:

```text
factor x^2 - 1
factor x^4 - 16
```

Chips:

```text
expr x^2 - 1
```

---

## `simplify`

```text
simplify expr
```

Lowers to:

```python
simplify(expr)
```

Examples:

```text
simplify sin(x)^2 + cos(x)^2
simplify (x^2 - 1)/(x - 1)
```

Chips:

```text
expr
```

Variants worth completing:

```text
simplify_full expr
simplify_trig expr
simplify_rational expr
simplify_radical expr
```

---

## `collect`

```text
collect expr, var
```

Lowers to:

```python
collect(expr, var)
```

Examples:

```text
collect x*y + x*z + y, x
```

Chips:

```text
expr
var
```

---

## `combine`

```text
combine expr
```

Lowers to:

```python
expr.combine()
```

or:

```python
combine(expr)
```

Depending on the object.

Examples:

```text
combine log(x) + log(y)
combine 1/x + 1/y
```

---

## `partial_fraction`

```text
partial_fraction expr, var
```

Lowers to:

```python
expr.partial_fraction(var)
```

Examples:

```text
partial_fraction 1/(x^2 - 1), x
```

Chips:

```text
expr
var optional
```

Alias candidates:

```text
apart
partial fractions
```

---

## `numerator`

```text
numerator expr
```

Lowers to:

```python
numerator(expr)
```

or:

```python
expr.numerator()
```

---

## `denominator`

```text
denominator expr
```

Lowers to:

```python
denominator(expr)
```

or:

```python
expr.denominator()
```

---

## `canonicalize_radical`

```text
canonicalize_radical expr
```

Lowers to:

```python
expr.canonicalize_radical()
```

Example:

```text
canonicalize_radical sqrt(8)
```

---

# Calculus rules

## `derivative`

Aliases:

```text
derivative
differentiate
diff
d/dx
```

Accepted forms:

```text
derivative expr
derivative expr, var
derivative expr, var, n
d/dx expr
```

Lowers to:

```python
diff(expr, var)
diff(expr, var, n)
```

Examples:

```text
derivative x^3
derivative sin(x), x
derivative sin(x), x, 2
d/dx sin(x)
```

Chips:

```text
expr sin(x)
var x
order optional
```

Defaulting rule: infer `var` from expression if there is exactly one symbolic variable. Otherwise require `var`.

---

## `integral`

Aliases:

```text
integral
integrate
int
∫
```

Accepted forms:

```text
integral expr
integral expr, var
integral expr, var=lower..upper
integral expr, var, lower, upper
```

Lowers to:

```python
integral(expr, var)
integral(expr, var, lower, upper)
```

Examples:

```text
integral x^2
integral x^2, x
integral x^2, x=0..1
integral sin(x), x=0..pi
```

Chips:

```text
expr x^2
var x
bounds optional: lower .. upper
```

Do not show `lower optional` and `upper optional` as separate independent chips. They’re one semantic unit.

---

## `limit`

Accepted forms:

```text
limit expr, var=point
limit expr, var -> point
limit expr, var=point, direction
```

Lowers to:

```python
limit(expr, var=point)
limit(expr, var=point, dir='+')
limit(expr, var=point, dir='-')
```

Examples:

```text
limit sin(x)/x, x=0
limit 1/x, x=0, right
limit 1/x, x=0, left
limit (1 + 1/x)^x, x=infinity
```

Chips:

```text
expr sin(x)/x
var x
point 0
direction optional
```

Directions:

```text
left  -> dir='-'
right -> dir='+'
both  -> omit dir
```

---

## `taylor`

Accepted forms:

```text
taylor expr, var=point, order
taylor expr, var, point, order
```

Lowers to:

```python
taylor(expr, var, point, order)
```

Examples:

```text
taylor sin(x), x=0, 5
taylor exp(x), x=0, 4
```

Chips:

```text
expr
var
around
order
```

Alias:

```text
series
```

But `series` and `taylor` are not always identical in Sage semantics, so I’d make `taylor` the visible calculator operation.

---

## `laplace`

Accepted forms:

```text
laplace expr, t, s
```

Lowers to:

```python
laplace(expr, t, s)
```

Examples:

```text
laplace exp(a*t), t, s
```

Chips:

```text
expr
time var t
frequency var s
```

---

## `inverse_laplace`

Accepted forms:

```text
inverse_laplace expr, s, t
```

Lowers to:

```python
inverse_laplace(expr, s, t)
```

Examples:

```text
inverse_laplace 1/(s^2+1), s, t
```

---

## `sum`

Accepted forms:

```text
sum expr, var=lower..upper
sum expr, var, lower, upper
```

Lowers to:

```python
sum(expr, var, lower, upper)
```

Examples:

```text
sum k^2, k=1..n
sum 1/k^2, k=1..infinity
```

Chips:

```text
expr
index
bounds lower .. upper
```

---

## `product`

Accepted forms:

```text
product expr, var=lower..upper
product expr, var, lower, upper
```

Lowers to:

```python
product(expr, var, lower, upper)
```

Examples:

```text
product k, k=1..n
product (1 + 1/k), k=1..n
```

---

# Equation solving

## `solve`

Accepted forms:

```text
solve equation
solve equation, var
solve [eq1, eq2], [x, y]
```

Lowers to:

```python
solve(equation, var)
solve([eq1, eq2], [x, y])
```

Examples:

```text
solve x^2 - 1 == 0, x
solve x^2 - 1, x
solve [x+y==3, x-y==1], [x,y]
```

Normalization rule:

```text
solve x^2 - 1, x
```

should lower to:

```python
solve(x^2 - 1 == 0, x)
```

Chips:

```text
equation
variable(s)
```

---

## `roots`

Accepted forms:

```text
roots polynomial
roots polynomial, var
```

Lowers to:

```python
polynomial.roots()
polynomial.roots(ring=...)
```

But for symbolic expressions, safest lowering is:

```python
solve(poly == 0, var)
```

or coerce to polynomial if possible.

Examples:

```text
roots x^3 - x
```

---

## `find_root`

Accepted forms:

```text
find_root expr, var=lower..upper
find_root expr, lower, upper
```

Lowers to:

```python
find_root(expr, lower, upper)
```

or if var is needed:

```python
find_root(expr, lower, upper)
```

after constructing callable.

Examples:

```text
find_root cos(x) - x, x=0..1
```

Chips:

```text
expr
var
bracket lower .. upper
```

---

## `numerical_solve`

Aliases:

```text
nsolve
find solution
```

Sage has multiple pathways here. I’d reserve this for systems/nonlinear numeric solving and lower conservatively.

Accepted forms:

```text
nsolve equation, var, guess
nsolve [eqs], [vars], guesses
```

Potential lowerings:

```python
find_root(...)
```

for one variable with bracket.

For multivariable:

```python
solve(..., solution_dict=True)
```

symbolically first, or use `scipy`/Sage numerical machinery if available.

I would not expose this early unless you have a known lowering.

---

## `solve_ode`

Accepted forms:

```text
solve_ode equation, y, x
```

Lowers to:

```python
desolve(equation, y)
```

or:

```python
desolve(equation, y, ivar=x)
```

Examples:

```text
solve_ode diff(y,x) == y, y, x
```

Chips:

```text
differential equation
function y
independent var x
```

This is useful but needs careful UI help.

---

# Plotting rules

## `plot`

Accepted forms:

```text
plot expr
plot expr, var=lower..upper
plot expr, lower..upper
```

Lowers to:

```python
plot(expr, (var, lower, upper))
```

Examples:

```text
plot sin(x)
plot sin(x), x=-pi..pi
plot x^2, -5..5
```

Chips:

```text
expr
var x
range optional: lower .. upper
```

Default range:

```text
x=-10..10
```

if variable inferable.

---

## `parametric_plot`

Accepted forms:

```text
parametric_plot (xexpr, yexpr), var=lower..upper
```

Lowers to:

```python
parametric_plot((xexpr, yexpr), (var, lower, upper))
```

Examples:

```text
parametric_plot (cos(t), sin(t)), t=0..2*pi
```

Chips:

```text
x(t)
y(t)
parameter
range
```

---

## `polar_plot`

Accepted forms:

```text
polar_plot r_expr, theta=lower..upper
```

Lowers to:

```python
polar_plot(r_expr, (theta, lower, upper))
```

Examples:

```text
polar_plot 1 + cos(theta), theta=0..2*pi
```

Chips:

```text
r(theta)
angle var
range
```

---

## `implicit_plot`

Accepted forms:

```text
implicit_plot equation, x=lo..hi, y=lo..hi
```

Lowers to:

```python
implicit_plot(equation, (x, xlo, xhi), (y, ylo, yhi))
```

Examples:

```text
implicit_plot x^2 + y^2 == 1, x=-2..2, y=-2..2
```

Chips:

```text
equation
x range
y range
```

---

## `plot3d`

Accepted forms:

```text
plot3d expr, x=lo..hi, y=lo..hi
```

Lowers to:

```python
plot3d(expr, (x, xlo, xhi), (y, ylo, yhi))
```

Examples:

```text
plot3d x^2 + y^2, x=-2..2, y=-2..2
```

---

## `contour_plot`

Accepted forms:

```text
contour_plot expr, x=lo..hi, y=lo..hi
```

Lowers to:

```python
contour_plot(expr, (x,xlo,xhi), (y,ylo,yhi))
```

---

## `density_plot`

Accepted forms:

```text
density_plot expr, x=lo..hi, y=lo..hi
```

Lowers to:

```python
density_plot(expr, (x,xlo,xhi), (y,ylo,yhi))
```

---

## `list_plot`

Accepted forms:

```text
list_plot points
```

Lowers to:

```python
list_plot(points)
```

Examples:

```text
list_plot [(1,2), (2,3), (3,5)]
```

---

## `scatter_plot`

Alias for `list_plot`.

I’d expose this as calculator vocabulary even if Sage’s direct function differs.

```text
scatter points
```

Lowers to:

```python
list_plot(points)
```

---

## `bar_chart`

Accepted forms:

```text
bar_chart values
```

Lowers to:

```python
bar_chart(values)
```

Examples:

```text
bar_chart [3, 1, 4, 1, 5]
```

---

# Linear algebra rules

## `matrix`

Accepted forms:

```text
matrix [[...], [...]]
matrix rows, cols, entries
```

Lowers to:

```python
matrix([[...], [...]])
matrix(rows, cols, entries)
```

Examples:

```text
matrix [[1,2], [3,4]]
matrix 2, 2, [1,2,3,4]
```

Chips:

```text
entries
```

---

## `vector`

Accepted forms:

```text
vector [...]
```

Lowers to:

```python
vector([...])
```

Examples:

```text
vector [1,2,3]
```

---

## `det`

Aliases:

```text
det
determinant
```

Accepted forms:

```text
det matrix
```

Lowers to:

```python
matrix.det()
```

or:

```python
det(matrix)
```

Examples:

```text
det A
det [[1,2], [3,4]]
```

If the arg is a literal list-of-lists, wrap it in `matrix(...)`.

---

## `inverse`

Accepted forms:

```text
inverse matrix
```

Lowers to:

```python
matrix.inverse()
```

or:

```python
matrix^-1
```

Examples:

```text
inverse [[1,2], [3,4]]
inverse A
```

---

## `transpose`

Accepted forms:

```text
transpose matrix
```

Lowers to:

```python
matrix.transpose()
```

---

## `rank`

Accepted forms:

```text
rank matrix
```

Lowers to:

```python
matrix.rank()
```

---

## `rref`

Aliases:

```text
rref
row_reduce
echelon
```

Accepted forms:

```text
rref matrix
```

Lowers to:

```python
matrix.rref()
```

or:

```python
matrix.echelon_form()
```

Important: `rref` is the calculator word; Sage’s exact method name is not what users want to remember.

---

## `eigenvalues`

Aliases:

```text
eigenvalues
eigs
```

Accepted forms:

```text
eigenvalues matrix
```

Lowers to:

```python
matrix.eigenvalues()
```

---

## `eigenvectors`

Accepted forms:

```text
eigenvectors matrix
```

Lowers to:

```python
matrix.eigenvectors_right()
```

Chips:

```text
matrix
side right|left optional
```

Possible variants:

```text
right eigenvectors A
left eigenvectors A
```

---

## `charpoly`

Aliases:

```text
characteristic polynomial
charpoly
```

Accepted forms:

```text
charpoly matrix
charpoly matrix, var
```

Lowers to:

```python
matrix.charpoly(var)
```

Examples:

```text
charpoly A
charpoly A, λ
```

---

## `minimal_polynomial`

Accepted forms:

```text
minimal_polynomial matrix
```

Lowers to:

```python
matrix.minpoly()
```

---

## `nullspace`

Aliases:

```text
kernel
nullity
```

Accepted forms:

```text
nullspace matrix
kernel matrix
```

Lowers to:

```python
matrix.right_kernel()
```

Variant:

```text
left nullspace matrix
```

lowers to:

```python
matrix.left_kernel()
```

---

## `column_space`

Accepted forms:

```text
column_space matrix
```

Lowers to:

```python
matrix.column_space()
```

---

## `row_space`

Accepted forms:

```text
row_space matrix
```

Lowers to:

```python
matrix.row_space()
```

---

## `gram_schmidt`

Accepted forms:

```text
gram_schmidt vectors
```

Lowers to:

```python
Sequence(vectors).gram_schmidt()
```

or your own helper if you have one.

Examples:

```text
gram_schmidt [vector([1,1,0]), vector([1,0,1])]
```

---

## `qr`

Accepted forms:

```text
qr matrix
```

Lowers to Sage/numpy depending on your backend choice. I’d avoid unless you have stable object support.

---

## `svd`

Accepted forms:

```text
svd matrix
```

Sage support here is less uniform than users expect. For your app, I’d either:

1. implement your own symbolic/numeric helper, or
2. route numeric matrices through NumPy/SciPy.

Display chips:

```text
matrix
mode exact|numeric optional
```

This is worth having because coursework users will ask for it.

---

## `solve_linear`

Aliases:

```text
linear_solve
solve Ax=b
```

Accepted forms:

```text
solve_linear A, b
```

Lowers to:

```python
A.solve_right(b)
```

Examples:

```text
solve_linear [[1,2],[3,4]], [5,6]
```

Normalization:

```python
matrix(A).solve_right(vector(b))
```

---

# Vector calculus rules

## `gradient`

Aliases:

```text
grad
gradient
```

Accepted forms:

```text
gradient expr
gradient expr, [vars]
```

Lowers to:

```python
vector([diff(expr, v) for v in vars])
```

Examples:

```text
gradient x^2 + y^2
gradient x^2*y + z, [x,y,z]
```

Chips:

```text
scalar field
variables optional
```

Default variables: all symbolic vars in expression, sorted by user/recent order.

---

## `divergence`

Aliases:

```text
div
divergence
```

Accepted forms:

```text
divergence vector_field, [vars]
```

Lowers to:

```python
sum(diff(F[i], vars[i]) for i in range(n))
```

Examples:

```text
divergence [x^2, y^2, z^2], [x,y,z]
```

---

## `curl`

Accepted forms:

```text
curl vector_field, [x,y,z]
```

Lowers to explicit determinant/diff formula.

Examples:

```text
curl [y*z, x*z, x*y], [x,y,z]
```

---

## `jacobian`

Accepted forms:

```text
jacobian functions, vars
```

Lowers to:

```python
jacobian(functions, vars)
```

or:

```python
matrix([[diff(f, v) for v in vars] for f in funcs])
```

Examples:

```text
jacobian [x^2+y, sin(x*y)], [x,y]
```

Chips:

```text
functions
variables
```

---

## `hessian`

Accepted forms:

```text
hessian expr
hessian expr, [vars]
```

Lowers to:

```python
hessian(expr, vars)
```

Examples:

```text
hessian x^2 + x*y + y^2
```

---

## `laplacian`

Accepted forms:

```text
laplacian expr, [vars]
```

Lowers to:

```python
sum(diff(expr, v, 2) for v in vars)
```

Examples:

```text
laplacian x^2 + y^2 + z^2, [x,y,z]
```

---

## `directional_derivative`

Accepted forms:

```text
directional_derivative expr, point, direction
directional_derivative expr, [vars], point, direction
```

Lowers to:

```python
grad(expr).subs(point).dot(unit(direction))
```

Examples:

```text
directional_derivative x^2+y^2, (1,2), (3,4)
```

Chips:

```text
expr
point
direction vector
```

---

## `tangent_plane`

Accepted forms:

```text
tangent_plane expr, point
tangent_plane z=f(x,y), point
```

Lowers to constructed plane:

```text
z = f(a,b) + fx(a,b)(x-a) + fy(a,b)(y-b)
```

This is probably a custom helper, not vanilla Sage. Worth it.

---

## `critical_points`

Accepted forms:

```text
critical_points expr
critical_points expr, [vars]
```

Lowers to:

```python
solve([diff(expr,v)==0 for v in vars], vars)
```

Examples:

```text
critical_points x^3 - 3*x*y^2
```

---

# Probability / statistics rules

## `mean`

Accepted forms:

```text
mean data
```

Lowers to:

```python
mean(data)
```

Examples:

```text
mean [1,2,3,4]
```

---

## `median`

```text
median data
```

Lowers to:

```python
median(data)
```

---

## `variance`

Accepted forms:

```text
variance data
variance data, sample
variance data, population
```

Lowers depending on sample/population. Sage has stats functions, but I’d own this lowering because the denominator matters.

```python
sum((x - mean(data))^2 for x in data)/(n-1)
sum((x - mean(data))^2 for x in data)/n
```

Chips:

```text
data
kind sample|population
```

Default: sample, but show it.

---

## `stddev`

Accepted forms:

```text
stddev data
stddev data, sample
stddev data, population
```

Same denominator issue.

---

## `normal_pdf`

Accepted forms:

```text
normal_pdf x, mean, sd
```

Lowers to custom expression:

```python
1/(sd*sqrt(2*pi)) * exp(-1/2*((x-mean)/sd)^2)
```

---

## `normal_cdf`

Accepted forms:

```text
normal_cdf x, mean, sd
normal_cdf lower..upper, mean, sd
```

This likely needs numerical backend.

Examples:

```text
normal_cdf 1.96, 0, 1
normal_cdf -1..1, 0, 1
```

---

## `binomial`

Ambiguous: distribution vs coefficient. I’d split.

### `binomial_coefficient`

Aliases:

```text
choose
n choose k
binomial_coefficient
```

Accepted forms:

```text
choose n, k
n choose k
```

Lowers to:

```python
binomial(n, k)
```

Examples:

```text
choose 10, 3
10 choose 3
```

### `binomial_pmf`

Accepted forms:

```text
binomial_pmf k, n, p
```

Lowers to:

```python
binomial(n,k) * p^k * (1-p)^(n-k)
```

---

## `poisson_pmf`

Accepted forms:

```text
poisson_pmf k, lambda
```

Lowers to:

```python
exp(-lambda) * lambda^k / factorial(k)
```

---

## `zscore`

Accepted forms:

```text
zscore x, mean, sd
```

Lowers to:

```python
(x - mean)/sd
```

---

## `confidence_interval`

This is probably custom app sugar.

Accepted forms:

```text
confidence_interval mean, sd, n, level
confidence_interval proportion, n, level
```

I’d expose two separate completions:

```text
mean_confidence_interval
proportion_confidence_interval
```

---

# Number theory rules

## `gcd`

Accepted forms:

```text
gcd a, b
gcd [values]
```

Lowers to:

```python
gcd(a, b)
gcd(values)
```

---

## `lcm`

Same shape:

```text
lcm a, b
lcm [values]
```

---

## `xgcd`

Aliases:

```text
extended_gcd
bezout
```

Accepted forms:

```text
xgcd a, b
```

Lowers to:

```python
xgcd(a, b)
```

Returns:

```text
g, s, t where s*a + t*b = g
```

---

## `mod`

Accepted forms:

```text
mod a, n
a mod n
```

Lowers to:

```python
mod(a, n)
```

or:

```python
a % n
```

---

## `inverse_mod`

Accepted forms:

```text
inverse_mod a, n
```

Lowers to:

```python
inverse_mod(a, n)
```

Example:

```text
inverse_mod 3, 11
```

---

## `power_mod`

Accepted forms:

```text
power_mod base, exponent, modulus
base^exponent mod modulus
```

Lowers to:

```python
power_mod(base, exponent, modulus)
```

Examples:

```text
power_mod 2, 100, 17
2^100 mod 17
```

---

## `is_prime`

Accepted forms:

```text
is_prime n
prime? n
```

Lowers to:

```python
is_prime(n)
```

---

## `next_prime`

```text
next_prime n
```

Lowers to:

```python
next_prime(n)
```

---

## `factor_integer`

Aliases:

```text
factor_integer
prime_factorization
```

Accepted forms:

```text
factor_integer n
```

Lowers to:

```python
factor(n)
```

But display differently from symbolic `factor`.

---

## `euler_phi`

Aliases:

```text
phi
totient
```

Accepted forms:

```text
totient n
```

Lowers to:

```python
euler_phi(n)
```

---

## `crt`

Aliases:

```text
chinese_remainder
crt
```

Accepted forms:

```text
crt residues, moduli
```

Lowers to:

```python
crt(residues, moduli)
```

Examples:

```text
crt [2,3], [5,7]
```

---

# Combinatorics rules

## `factorial`

Accepted forms:

```text
factorial n
n!
```

Lowers to:

```python
factorial(n)
```

or native parser for `n!`.

---

## `permutations`

Accepted forms:

```text
permutations items
permutations items, k
```

Potential lowerings:

```python
Permutations(items)
Arrangements(items, k)
```

---

## `combinations`

Accepted forms:

```text
combinations items, k
```

Lowers to:

```python
Combinations(items, k)
```

---

## `subsets`

Accepted forms:

```text
subsets set
subsets set, k
```

Lowers to:

```python
Subsets(set)
Subsets(set, k)
```

---

## `partitions`

Accepted forms:

```text
partitions n
```

Lowers to:

```python
Partitions(n)
```

---

# Complex number rules

## `real_part`

Aliases:

```text
real
re
```

Accepted forms:

```text
real expr
```

Lowers to:

```python
real(expr)
```

---

## `imag_part`

Aliases:

```text
imag
im
```

Accepted forms:

```text
imag expr
```

Lowers to:

```python
imag(expr)
```

---

## `conjugate`

Accepted forms:

```text
conjugate expr
```

Lowers to:

```python
conjugate(expr)
```

---

## `abs`

For complex numbers and vectors this is overloaded.

Accepted forms:

```text
abs expr
```

Lowers to:

```python
abs(expr)
```

---

## `arg`

Accepted forms:

```text
arg z
```

Lowers to:

```python
arg(z)
```

---

## `rectangular`

Accepted forms:

```text
rectangular polar_expr
```

Custom helper; useful for calculator mode.

---

## `polar`

Accepted forms:

```text
polar z
```

Custom helper:

```python
(abs(z), arg(z))
```

---

# Trig rules

## `sin`

```text
sin expr
```

Lowers to:

```python
sin(expr)
```

Same for:

```text
cos
tan
sec
csc
cot
asin
acos
atan
arcsin
arccos
arctan
```

---

## `trig_expand`

Accepted forms:

```text
trig_expand expr
```

Lowers to:

```python
expand_trig(expr)
```

or:

```python
expr.expand_trig()
```

Examples:

```text
trig_expand sin(x+y)
```

---

## `trig_reduce`

Accepted forms:

```text
trig_reduce expr
```

Lowers to Sage’s trig simplification path; likely:

```python
expr.trig_reduce()
```

if available for that object, otherwise custom.

---

## `trig_simplify`

Accepted forms:

```text
trig_simplify expr
```

Lowers to:

```python
expr.simplify_trig()
```

---

# Log / exponential rules

## `log`

Accepted forms:

```text
log expr
log expr, base
```

Lowers to:

```python
log(expr)
log(expr, base)
```

Examples:

```text
log x
log x, 10
```

---

## `ln`

Alias:

```text
ln expr
```

Lowers to:

```python
log(expr)
```

---

## `exp`

Accepted forms:

```text
exp expr
```

Lowers to:

```python
exp(expr)
```

---

## `log_expand`

Accepted forms:

```text
log_expand expr
```

Lowers to a custom/symbolic expansion path.

Example:

```text
log_expand log(x*y)
```

Be careful: expansion has domain assumptions. Show a warning if variables have no positivity assumptions.

---

## `log_combine`

Accepted forms:

```text
log_combine expr
```

Examples:

```text
log_combine log(x) + log(y)
```

Again: assumptions matter.

---

# Assumption rules

This is a big Sage UX opportunity.

## `assume`

Accepted forms:

```text
assume condition
assume var is real
assume var > 0
```

Lowers to:

```python
assume(condition)
```

Examples:

```text
assume x > 0
assume x is real
```

For calculator spelling:

```text
assume x positive
assume x real
assume n integer
```

Lower to:

```python
assume(x > 0)
assume(x, 'real')
assume(n, 'integer')
```

or equivalent Sage assumptions syntax.

---

## `forget`

Accepted forms:

```text
forget assumptions
forget x
forget all
```

Lowers to:

```python
forget()
```

or variable-specific assumption clearing if you support it.

---

## `assumptions`

Accepted forms:

```text
assumptions
assumptions x
```

Lowers to:

```python
assumptions()
```

---

# Symbol / variable rules

## `var`

Accepted forms:

```text
var x
var x y z
var x, y, z
```

Lowers to:

```python
var('x y z')
```

Examples:

```text
var a b c
```

Chips:

```text
symbol names
```

Important UX: when user types an unknown bare identifier in a math expression, offer:

```text
Create symbol 'foo'
```

---

## `function`

Accepted forms:

```text
function f
function f(x)
```

Lowers to:

```python
function('f')
```

or:

```python
f = function('f')(x)
```

depending on context.

Useful for ODEs.

---

# Substitution rules

## `substitute`

Aliases:

```text
subs
replace
evaluate at
```

Accepted forms:

```text
subs expr, var=value
subs expr, {x:1, y:2}
expr at x=1
```

Lowers to:

```python
expr.subs(var=value)
expr.subs({x:1, y:2})
```

Examples:

```text
subs x^2 + y, x=3
x^2 + y at x=3, y=4
```

Chips:

```text
expr
bindings
```

This should be very high-value.

---

## `evaluate`

Accepted forms:

```text
evaluate expr
evaluate expr, var=value
```

Lowers to:

```python
expr
expr.subs(...).n()
```

depending on numeric mode.

I’d avoid using the word `evaluate` for pure expression entry because your Return key already does that.

---

# Numeric approximation rules

## `n`

Aliases:

```text
numeric
approx
decimal
N
```

Accepted forms:

```text
numeric expr
numeric expr, digits
expr to 20 digits
```

Lowers to:

```python
N(expr)
N(expr, digits=digits)
```

Examples:

```text
numeric pi
numeric sqrt(2), 50
pi to 100 digits
```

Chips:

```text
expr
digits optional
```

---

## `round`

Accepted forms:

```text
round expr
round expr, digits
```

Lowers to Python/Sage round behavior, but watch exact vs numeric coercion.

---

## `floor`

```text
floor expr
```

Lowers to:

```python
floor(expr)
```

Same for:

```text
ceil
ceiling
frac
```

---

# Units rules

Sage units can be awkward. Still, a calculator app wants this.

## `convert`

Accepted forms:

```text
convert quantity, unit
quantity to unit
```

Examples:

```text
convert 5 feet, meters
5 ft to m
```

Potential lowering:

```python
units.length.foot * 5
```

But you probably want your own unit parser.

Chips:

```text
quantity
target unit
```

---

# Geometry rules

## `distance`

Accepted forms:

```text
distance point1, point2
```

Lowers to:

```python
sqrt(sum((a-b)^2 for a,b in zip(p1,p2)))
```

Examples:

```text
distance (1,2), (4,6)
```

---

## `midpoint`

Accepted forms:

```text
midpoint point1, point2
```

Lowers to:

```python
vector(p1 + p2)/2
```

---

## `line`

Accepted forms:

```text
line point1, point2
line slope, point
```

For plotting or symbolic equation construction. This is custom helper territory.

---

## `circle`

Accepted forms:

```text
circle center, radius
```

Lowers to graphics:

```python
circle(center, radius)
```

Or equation:

```text
(x-h)^2 + (y-k)^2 == r^2
```

I’d distinguish:

```text
circle_plot center, radius
circle_equation center, radius
```

---

# Polynomial rules

## `degree`

Accepted forms:

```text
degree polynomial
degree polynomial, var
```

Lowers to:

```python
poly.degree(var)
```

---

## `coefficients`

Accepted forms:

```text
coefficients polynomial
coefficients polynomial, var
```

Lowers to:

```python
poly.coefficients()
```

---

## `coefficient`

Accepted forms:

```text
coefficient polynomial, var^power
coefficient polynomial, var, power
```

Examples:

```text
coefficient 3*x^2 + 2*x + 1, x^2
coefficient 3*x^2 + 2*x + 1, x, 2
```

Lowers to:

```python
expr.coefficient(x, 2)
```

---

## `leading_coefficient`

Accepted forms:

```text
leading_coefficient polynomial
```

Lowers to:

```python
poly.leading_coefficient()
```

---

## `roots_exact`

Accepted forms:

```text
roots_exact polynomial
```

Lowers to symbolic solve or polynomial ring roots.

---

## `discriminant`

Accepted forms:

```text
discriminant polynomial
discriminant polynomial, var
```

Lowers to:

```python
discriminant(poly, var)
```

---

# Algebraic structures / rings

These are more Sage-native, less calculator-native, but your user base may like them.

## `PolynomialRing`

Accepted forms:

```text
polynomial_ring base, var
polynomial_ring QQ, x
```

Lowers to:

```python
PolynomialRing(QQ, 'x')
```

---

## `GF`

Aliases:

```text
finite_field
field mod p
```

Accepted forms:

```text
GF p
finite_field p
```

Lowers to:

```python
GF(p)
```

Examples:

```text
GF 257
```

---

## `mod_ring`

Accepted forms:

```text
integers_mod n
Zmod n
```

Lowers to:

```python
Zmod(n)
```

---

## `elliptic_curve`

Accepted forms:

```text
elliptic_curve [a1,a2,a3,a4,a6]
elliptic_curve a, b
```

Lowers to:

```python
EllipticCurve([...])
EllipticCurve([a,b])
```

This is Sage candy. Probably hidden unless user types `ell`.

---

# Logic / sets rules

## `set`

Accepted forms:

```text
set elements
```

Lowers to:

```python
Set(elements)
```

or Python `set`.

---

## `union`

Accepted forms:

```text
union A, B
A union B
```

Lowers to:

```python
A.union(B)
```

---

## `intersection`

```text
intersection A, B
A intersect B
```

Lowers to:

```python
A.intersection(B)
```

---

## `difference`

```text
difference A, B
A minus B
```

Lowers to:

```python
A.difference(B)
```

---

## `cartesian_product`

```text
cartesian_product A, B
A × B
```

Lowers to:

```python
cartesian_product([A, B])
```

---

## `truth_table`

Accepted forms:

```text
truth_table expression
truth_table expression, vars
```

This is probably custom unless you lean on Sage symbolic logic.

---

# LaTeX / rendering rules

## `latex`

Accepted forms:

```text
latex expr
```

Lowers to:

```python
latex(expr)
```

Examples:

```text
latex integral(sin(x), x)
```

This is useful for debugging the renderer.

---

## `show`

Accepted forms:

```text
show expr
```

Lowers to:

```python
show(expr)
```

But in your app this should probably mean “render this result as display math/graphics,” not literally Sage notebook `show`.

---

# Financial / applied math rules

Probably not Sage-native, but calculator users expect them.

## `compound_interest`

Accepted forms:

```text
compound_interest principal, rate, periods
compound_interest principal, rate, years, compounds_per_year
```

Lowers to expression construction.

---

## `solve_interest`

Custom helper.

Accepted forms:

```text
solve_interest principal, future_value, years
```

---

# Physics-ish formula helpers

I would not overload Sage with too many of these initially, but formula completion gives you a path.

## `quadratic_formula`

Accepted forms:

```text
quadratic_formula a, b, c
```

Lowers to:

```python
(-b ± sqrt(b^2 - 4*a*c))/(2*a)
```

Actually produce both roots.

---

## `distance_formula`

```text
distance_formula point1, point2
```

Same as geometry `distance`.

---

## `pythagorean`

```text
pythagorean a, b
```

Lowers to:

```python
sqrt(a^2 + b^2)
```

---

# Data / table rules

## `table`

Accepted forms:

```text
table expr, var=lower..upper
table expr, var=lower..upper, step
```

Lowers to list comprehension:

```python
[(v, expr.subs(var=v)) for v in srange(lower, upper, step)]
```

Examples:

```text
table x^2, x=0..10
table sin(x), x=0..pi, pi/8
```

Chips:

```text
expr
var
range
step optional
```

This is very calculator-like and should exist.

---

## `sequence`

Accepted forms:

```text
sequence expr, var=lower..upper
```

Lowers to:

```python
[expr.subs(var=k) for k in range(lower, upper+1)]
```

Examples:

```text
sequence k^2, k=1..10
```

---

# Meta-rules for completion ranking

## 1. Prefer operators over ordinary functions

If the user types:

```text
int
```

Rank:

```text
∫ integral
```

above Python/Sage internals.

If they type:

```text
diff
```

Rank:

```text
d/dx derivative
```

above random objects named `diff`.

---

## 2. Use current worksheet symbols for defaults

Given prior cells using:

```text
arctan(x)
```

Then:

```text
integral
```

should suggest:

```text
expr arctan(x)
var x
```

or at least default the var chip to `x`.

Given current symbols:

```text
x, y, z
```

and expression contains `y`, default `var y`.

---

## 3. One-symbol expressions should not ask for a variable

```text
derivative sin(x)
```

should lower to:

```python
diff(sin(x), x)
```

No ceremony.

But:

```text
derivative x*y
```

should require:

```text
var
```

unless the user recently selected one.

---

## 4. Ranges should have a first-class grammar

Support:

```text
x=0..1
x = 0 .. 1
x in 0..1
0..1
[0,1]
```

Then normalize to Sage tuple form:

```python
(x, 0, 1)
```

This helps:

```text
plot sin(x), x=-pi..pi
integral sin(x), x=0..pi
sum k^2, k=1..n
```

---

## 5. Equation sugar should normalize `expr` to `expr == 0`

For `solve`, this:

```text
solve x^2 - 1, x
```

should be accepted and lowered to:

```python
solve(x^2 - 1 == 0, x)
```

For `implicit_plot`, this:

```text
implicit_plot x^2 + y^2 - 1
```

should become:

```python
implicit_plot(x^2 + y^2 - 1 == 0, ...)
```

---

## 6. Function application should allow space-call syntax

Support:

```text
sin x
cos x
sqrt x
factor x^2 - 1
integral x^2
```

But do not break multiplication. Heuristic:

Known function/operator followed by expression → call.

Unknown symbol followed by symbol:

```text
x y
```

should probably be rejected or interpreted only with explicit multiplication setting.

---

## 7. Parenthesize lowered expressions aggressively

This input:

```text
integral x+1, x
```

should lower as:

```python
integral(x + 1, x)
```

not anything weird.

For unary formula completions, consume the full expression span after the operator until comma/range/end.

---

## 8. Optional args should be semantic groups

Bad chips:

```text
lower optional
upper optional
```

Good chip:

```text
bounds optional: lower .. upper
```

Bad chips:

```text
mean optional
sd optional
```

Good chip:

```text
distribution parameters optional
```

---

## 9. Display aliases, lower canonical names

User types:

```text
differentiate
```

UI shows:

```text
d/dx DERIVATIVE
```

Lower to:

```python
diff(...)
```

User types:

```text
ln
```

UI shows:

```text
ln LOG
```

Lower to:

```python
log(...)
```

---

## 10. Preserve exact vs numeric mode in every rule

Your UI already has `Numeric` / `10 digits`.

Rules should know whether they are:

```text
exact by default
numeric by default
mode-sensitive
```

Examples:

```text
integral x^2, x=0..1
```

Exact mode:

```python
integral(x^2, x, 0, 1)
```

Numeric mode:

```python
N(integral(x^2, x, 0, 1), digits=10)
```

For `find_root`, always numeric.

For `solve`, exact by default; numeric fallback should be explicit or prompted.

---

# High-value first release set

If I were cutting scope, these are the ones I’d ship first:

```text
expand
factor
simplify
solve
derivative / diff
integral
limit
taylor
sum
product
plot
parametric_plot
implicit_plot
matrix
vector
det
inverse
transpose
rref
rank
eigenvalues
eigenvectors
gradient
jacobian
hessian
subs
numeric
latex
var
assume
forget
mean
stddev
choose
factorial
gcd
lcm
is_prime
factor_integer
```

That gets you through a large fraction of undergrad math and makes the app feel dramatically better than a Sage prompt.


