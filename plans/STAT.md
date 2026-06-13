# Statistics Plan

Casette should make school-stat and early probability work feel like a
calculator, not a tour through Sage's internal naming. This plan covers the
user-facing statistics vocabulary. The raw Python/Sage helper layer it depends
on lives in [PRELOAD.md](PRELOAD.md).

## Principle

Expose common textbook questions directly:

- "What is this summary statistic?"
- "What is `P(X <= k)`?"
- "What is `P(a <= X <= b)`?"
- "What cutoff gives this tail area?"
- "Show me the distribution."

The friendly compiler should lower to humane helper names, not Sage's native
distribution objects. Generated Sage should stay readable:

```python
normal_between(-1, 1)
binomial_cdf(3, n=10, p=0.5)
```

instead of:

```python
RealDistribution('gaussian', 1).cum_distribution_function(...)
```

## Two layers

1. **Friendly compiler shortcuts** turn compact calculator input into Python
   helper calls. These get formula bars, completion chips, structured errors,
   and live Generated Sage previews.
2. **Preloaded Python helpers** define the actual human API in the worker
   namespace. Raw Sage users can type the same helper calls directly. These
   helpers are treated as built-ins and hidden from the user's Symbols list;
   see [PRELOAD.md](PRELOAD.md).

This keeps the Swift compiler layer small and makes raw Sage less hostile at
the same time.

## First batch (implemented)

### Normal distribution

Friendly forms:

```text
normal_pdf x
normal_pdf x, mean=mu, sd=sigma

normal_cdf x
normal_cdf x, mean=mu, sd=sigma

normal_between a, b
normal_between a, b, mean=mu, sd=sigma

normal_inv p
normal_inv p, mean=mu, sd=sigma
```

Preload helpers:

```python
normal_pdf(x, mean=0, sd=1)
normal_cdf(x, mean=0, sd=1)
normal_between(a, b, mean=0, sd=1)
normal_inv(p, mean=0, sd=1)
```

Backend preference: SciPy's `scipy.stats.norm` if available in Sage's Python,
because it provides the vocabulary users expect. Sage 9.5 on the current
machine has SciPy. A fallback can use Sage's
`RealDistribution('gaussian', sd)` for standard CDF/inverse CDF operations,
with `mean` handled as a shift.

### Binomial distribution

Friendly forms:

```text
binomial_pmf k, n=10, p=.5
binomial_cdf k, n=10, p=.5
binomial_between a, b, n=10, p=.5
binomial_at_most k, n=10, p=.5
binomial_at_least k, n=10, p=.5
```

Preload helpers:

```python
binomial_pmf(k, n, p)
binomial_cdf(k, n, p)
binomial_between(a, b, n, p)
binomial_at_most(k, n, p)
binomial_at_least(k, n, p)
```

Backend preference: owned exact Sage formulas first:

```python
binomial(n, k) * p**k * (1 - p)**(n - k)
sum(binomial_pmf(i, n=n, p=p) for i in range(a, b + 1))
```

This keeps exact results when `p` is exact, such as `p=1/2`, while still
approximating nicely under Casette's existing numeric controls.

## Second batch (implemented)

### Poisson

```text
poisson_pmf k, lambda=3
poisson_cdf k, lambda=3
poisson_between a, b, lambda=3
poisson_at_least k, lambda=3
```

Helper names should accept both `lam` and `lambda_` at the Python level; the
friendly syntax should display `lambda=` because that is the textbook term.
The generated Python call must use `lambda_=` because `lambda` is reserved.

### Exponential

```text
exponential_pdf x, rate=lambda
exponential_cdf x, rate=lambda
exponential_between a, b, rate=lambda
exponential_inv p, rate=lambda
```

Accept `rate=` as the friendly/default parameter. Consider `mean=` as an alias
later, but do not expose both in the first UI pass unless the formula bar can
make the mode unambiguous.

### Uniform

```text
uniform_pdf x, min=a, max=b
uniform_cdf x, min=a, max=b
uniform_between a, b, min=lo, max=hi
uniform_inv p, min=lo, max=hi
```

Use `min`/`max` in the friendly syntax because they are understandable in a
calculator UI. The helper can use `low`/`high` internally if shadowing Python
built-ins feels too ugly.

## Descriptive statistics

Casette already ships:

```text
mean [1, 2, 3] -> sum([1, 2, 3])/len([1, 2, 3])
```

Future friendly forms:

```text
median [1, 2, 3]
variance [1, 2, 3]
variance [1, 2, 3], sample
stddev [1, 2, 3]
stddev [1, 2, 3], population
quantile [1, 2, 3, 4], .75
percentile [1, 2, 3, 4], 75
zscore x, mean=mu, sd=sigma
```

Do not blindly expose Sage's deprecated `mean`, `std`, or `variance` functions
as the generated code. Prefer owned helpers with explicit sample/population
semantics:

```python
stat_mean(data)
stat_median(data)
stat_variance(data, sample=True)
stat_stddev(data, sample=True)
quantile(data, q)
percentile(data, p)
zscore(x, mean, sd)
```

The friendly command can remain `mean`; the helper can be `stat_mean` to avoid
fighting Sage's own namespace.

## Plots and visual workflows

These should come after numeric probability queries, because they are more UI
heavy and may want richer formula bars.

```text
normal_plot mean=0, sd=1, x=-4..4
binomial_plot n=20, p=.4
poisson_plot lambda=3
histogram [data]
boxplot [data]
scatter [xs], [ys]
qqplot [data]
```

Plot helpers should return Sage/Matplotlib graphics that already work with the
existing artifact pipeline.

## Sampling and simulation

Useful, but not first:

```text
sample_normal 1000, mean=0, sd=1
sample_binomial 1000, n=10, p=.5
sample_poisson 1000, lambda=3
simulate_binomial 10000, n=10, p=.5
```

Keep sampling explicitly named so deterministic symbolic calculations do not
look random by surprise. Add seed support at the helper layer before making
sampling prominent in the UI.

## Syntax rules

- Distribution commands use `distribution_operation`: `normal_cdf`,
  `binomial_between`, `poisson_pmf`.
- Positional values come first. Named parameters follow.
- Prefer textbook parameter names in friendly input: `mean`, `sd`, `n`, `p`,
  `lambda`, `rate`, `min`, `max`.
- Generated Sage may use Python-safe names: `lambda_`, `low`, `high`.
- Range probability commands use inclusive endpoints for discrete
  distributions and interval endpoints for continuous distributions.
- Tail helpers should be explicit: `at_most`, `at_least`, `between`.

## Formula bars

First-pass bars can be compact:

- `normal_cdf`: function chip, `x`, optional `mean`, optional `sd`
- `normal_between`: function chip, `lower`, `upper`, optional `mean`,
  optional `sd`
- `binomial_pmf`: function chip, `k`, `n`, `p`
- `binomial_between`: function chip, `lower`, `upper`, `n`, `p`

The bar edits friendly input only. It must preserve `#ROW` tape references
until the normal `CompiledInput` boundary.

## Exactness and numeric display

Descriptive statistics and discrete distributions should preserve exactness
when possible. Continuous distributions will usually produce real floats. That
is acceptable, but the result should still participate in Casette's existing
numeric precision controls where the worker can represent the value.

Avoid hidden namespace mutation. Probability helpers should be pure functions.
Sampling helpers are the exception; if they use global RNG state, document it
and expose seed controls.

## Implementation phases

1. **Done:** Add [PRELOAD.md](PRELOAD.md)'s hidden worker preload mechanism.
2. **Done:** Add preload helpers for normal and binomial distributions, with
   worker tests.
3. **Done:** Add friendly compiler forms for normal/binomial probability
   queries, with lowering tests and completion docs.
4. **Done:** Add formula bars for the first batch.
5. **Done:** Add Poisson, exponential, and uniform helpers/forms.
6. Add descriptive statistics helpers/forms.
7. Add plots and sampling once the probability core feels solid.
