# Worker Preload Plan

Casette should define a small, humane Python/Sage API in every fresh worker
namespace. These helpers should be available to raw Sage input and to friendly
compiler lowerings, but they should not appear in the user's Symbols list.

The statistics vocabulary that motivates the first preload batch is documented
in [STAT.md](STAT.md).

## Goals

- Let raw users type readable calls like `normal_between(-1, 1)` and
  `binomial_cdf(3, n=10, p=0.5)`.
- Let the friendly compiler lower to those readable calls instead of Sage's
  awkward native names.
- Keep helper functions and constants out of Symbols, History actions, and any
  future "user variable" workflows.
- Keep restart semantics simple: a restarted worker gets the same built-in
  helpers and constants automatically.
- Keep user code authoritative: if a user intentionally reassigns
  `normal_cdf`, the reassigned name should appear in Symbols, just like
  reassigned Sage built-ins do today.

## Placement

Load preloads inside `v0/01-worker-protocol/worker.py` after `NS` is seeded
with `from sage.all import *`, but before `_SYMBOL_BASELINE = dict(NS)`.

That makes preloads part of the pristine namespace:

```python
NS = {}
exec("from sage.all import *", NS)
_install_casette_preloads(NS)
_SYMBOL_BASELINE = dict(NS)
```

Do not send these helpers as an app-side boot prelude. App-side boot preludes
happen after the baseline, so names created there are user-created from the
symbol-table point of view. That is correct for calculator variables when the
product wants them visible or explicitly toggleable; it is wrong for built-in
helper functions.

## Shape

Prefer a bundled Python module or a clearly separated preload block over a long
inline string inside the worker core. The worker should remain the one canonical
worker, but the helper definitions should be easy to test and review.

Possible layout:

```text
v0/01-worker-protocol/worker.py
v0/01-worker-protocol/casette_preload.py
```

If bundling a second Python file into the app complicates the build, keep the
first implementation inline behind `_install_casette_preloads(NS)` and split it
later.

## Symbol-table behavior

The existing symbol table diffs live `NS` against `_SYMBOL_BASELINE` by object
identity. Preloaded names should obey that same rule:

- untouched preload helper: hidden
- deleted preload helper: absent
- reassigned preload helper: visible as a user-created binding
- restored original object: hidden again

Do not special-case helper names by prefix unless the baseline approach proves
insufficient. Identity diffing already gives the right user mental model.

Private implementation helpers may use `__casette_*` names, but public preload
functions should be pleasant names without prefixes.

## Implemented preload batch

Statistics helpers from [STAT.md](STAT.md):

```python
normal_pdf(x, mean=0, sd=1)
normal_cdf(x, mean=0, sd=1)
normal_between(a, b, mean=0, sd=1)
normal_inv(p, mean=0, sd=1)

binomial_pmf(k, n, p)
binomial_cdf(k, n, p)
binomial_between(a, b, n, p)
binomial_at_most(k, n, p)
binomial_at_least(k, n, p)

poisson_pmf(k, lambda_)
poisson_cdf(k, lambda_)
poisson_between(a, b, lambda_)
poisson_at_most(k, lambda_)
poisson_at_least(k, lambda_)

exponential_pdf(x, rate)
exponential_cdf(x, rate)
exponential_between(a, b, rate)
exponential_inv(p, rate)

uniform_pdf(x, low, high)
uniform_cdf(x, low, high)
uniform_between(a, b, low, high)
uniform_inv(p, low, high)
```

Future descriptive-stat helpers:

```python
stat_mean(data)
stat_median(data)
stat_variance(data, sample=True)
stat_stddev(data, sample=True)
quantile(data, q)
percentile(data, p)
zscore(x, mean, sd)
```

The friendly compiler may expose `mean`, `median`, `stddev`, etc. as command
words even when the Python helpers are prefixed with `stat_`.

## Constants

Preload constants should be conservative. Sage already provides many useful
mathematical constants, and Casette's boot-variable prelude already owns common
symbolic variables.

Candidates:

```python
TAU = 2*pi
PHI = (1 + sqrt(5)) / 2
```

Avoid adding many aliases early. Constants are easier to add than remove, and
short names can collide with normal math notation.

## Dependency policy

Sage 9.5 on the current development machine has SciPy available. Use SciPy
where it materially improves the human API, especially continuous
distributions:

```python
from scipy.stats import norm
```

But keep fallbacks or focused Doctor checks for optional dependencies:

- Normal CDF/inverse can fall back to Sage `RealDistribution('gaussian', sd)`.
- Binomial PMF/CDF can use exact Sage formulas and should not need SciPy.
- Future Poisson/exponential/uniform helpers can use exact formulas where
  simple, SciPy where inverse CDFs or edge behavior are tricky.

If a helper cannot be installed because an optional dependency is unavailable,
the worker should fail that helper with a clear runtime error, not fail worker
boot. Sage Doctor can later report "stats preload: SciPy missing" as a warning
or failure depending on how central the helper has become.

## Error policy

Helpers should validate common domain errors with short, human messages:

- `sd <= 0`
- `n < 0` or non-integer `n`
- `k` outside a discrete distribution's support
- `p < 0` or `p > 1`
- invalid CDF probability for inverse commands
- malformed or empty data

Prefer `ValueError` with a clear sentence. The worker already turns exceptions
into readable error envelopes.

## Generated Sage policy

Friendly compiler lowerings should call public preload helpers:

```python
normal_between(-1, 1, mean=0, sd=1)
binomial_cdf(3, n=10, p=0.5)
```

They should not inline long formulas or backend-specific calls. This keeps the
preview line useful and makes the raw equivalent obvious.

The exception is a tiny exact expression that is already established and more
readable than a helper call, such as the existing `mean` lowering. New stats
commands should prefer preloads unless there is a strong reason not to.

## Testing

Add worker-level tests before UI work:

- helper names are available immediately after boot
- helper names are absent from the Symbols op before reassignment
- reassigned helper names appear in Symbols
- restart restores helper availability and hides untouched helpers again
- normal helper values match known reference values
- binomial helper values preserve exactness for exact `p`
- domain errors return readable worker error envelopes

Then add friendly compiler tests:

- accepted syntax lowers to public helper calls
- missing required arguments produce structured errors
- named arguments render consistently
- formula bars round-trip partial edits without dropping typed text

## Future preload families

Preloads do not need to be stats-only. Good candidates are small, stable,
calculator-friendly functions whose Sage names are obscure or whose raw API is
needlessly verbose:

- probability/distribution helpers from [STAT.md](STAT.md)
- data summaries and regression helpers
- common plot constructors once their API stabilizes
- small linear algebra conveniences where Sage's method names are surprising
- readable aliases for exact/numeric conversion if the current UI vocabulary
  grows a matching raw API

Avoid preloading large stateful objects or anything that mutates the namespace
on import. A preload should feel like a standard library, not a hidden session.
