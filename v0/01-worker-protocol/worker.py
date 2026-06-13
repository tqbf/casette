#!/usr/bin/env python
"""Casette Sage worker.

Launched by the parent app as::

    sage -python worker.py

It speaks a line-delimited JSON (JSONL) protocol: one JSON request object per
line on stdin, one JSON response object per line on stdout. The Sage namespace
is created once and persists across every request, so assignments made in one
eval are visible in the next.

This file is one of the few V0 artifacts expected to survive into the real app,
so it is written to be read.

Protocol
--------
Request (one JSON object per line)::

    {"id": "req-1", "code": "factor(x^4 - 1)"}

Optional request ops::

    {"id": "p-1", "op": "ping"}        -> {"id":"p-1","ok":true,"op":"ping","pong":true}
    {"id": "q-1", "op": "shutdown"}    -> {"id":"q-1","ok":true,"op":"shutdown"}; worker exits

Response (the V0.3 result envelope)::

    {
      "id": "req-1",
      "ok": true,
      "kind": "matrix",
      "plain": "[1 2]\n[3 4]",
      "latex": "\\left(\\begin{array}{rr} 1 & 2 \\\\ 3 & 4 \\end{array}\\right)",
      "repr": "[1 2]\n[3 4]",
      "approx": null,                       # numeric approximation, or null
      "actions": ["det","rank","rref","eigenvalues","transpose","inverse",
                  "column_space","row_space","right_kernel","change_ring_RDF"],
      "artifacts": [],
      "truncated": false,                   # was plain/repr capped?
      "stdout": "",
      "stderr": "",
      "value": true            # whether the eval produced a value (vs a statement)
    }

Error response::

    {
      "id": "req-1",
      "ok": false,
      "kind": "error",
      "plain": "rational division by zero",
      "latex": null,
      "error": {"type": "ZeroDivisionError",
                "message": "rational division by zero",
                "traceback": "Traceback (most recent call last): ..."},
      "stdout": "",
      "stderr": "",
      "artifacts": []
    }

The hard rule
-------------
User code may print to stdout/stderr (``print("hello")``) or Sage internals may
write directly to file descriptor 1/2. None of that may corrupt the JSONL
protocol. We therefore dup the *real* stdout/stderr fds aside at startup and use
those private fds for protocol writes; during ``exec`` we redirect both the
Python-level ``sys.stdout``/``sys.stderr`` and the OS-level fds 1/2 into capture
buffers, then fold what was captured into the response envelope.
"""

import ast
import contextlib
import io
import json
import os
import signal
import sys
import traceback


# ---------------------------------------------------------------------------
# Protocol I/O: private fds so user code can never corrupt the wire.
# ---------------------------------------------------------------------------

# Dup the real stdout/stderr to private fds *before* anything (Sage import,
# user code) gets a chance to scribble on 1/2.
_PROTO_OUT_FD = os.dup(1)
_PROTO_ERR_FD = os.dup(2)
_proto_out = os.fdopen(_PROTO_OUT_FD, "w", buffering=1, encoding="utf-8")
_proto_err = os.fdopen(_PROTO_ERR_FD, "w", buffering=1, encoding="utf-8")


def _emit(obj):
    """Write one JSON object as a single line on the private protocol fd."""
    _proto_out.write(json.dumps(obj, ensure_ascii=False) + "\n")
    _proto_out.flush()


def _log(msg):
    """Diagnostic line on the private stderr fd (never on the protocol fd)."""
    _proto_err.write("[worker] " + msg + "\n")
    _proto_err.flush()


# ---------------------------------------------------------------------------
# Interrupt handling (V0.2).
# ---------------------------------------------------------------------------
#
# The parent interrupts an in-flight eval by sending SIGINT to the worker's
# *real* pid (reported in the ready banner — NOT the `sage` bash-wrapper pid).
# SIGINT becomes a KeyboardInterrupt, which `_handle_eval` catches and reports
# as a distinct `interrupted` envelope.
#
# WHO ACTUALLY HANDLES SIGINT — the load-bearing truth (measured; PROBLEMS.md):
# We set a plain Python handler below, BUT `from sage.all import *` (run just
# after) makes **cysignals** install its OWN SIGINT handler
# (`cysignals.python_check_interrupt`) on top of ours. cysignals wraps Sage's
# C/Cython code in sig_on()/sig_off() and longjmps out at the next interrupt
# check, so SIGINT **promptly aborts mid-flight C computation** like
# `factorial(10^8)` (verified: interrupted at +3.00s, vs >60s to run). It also
# raises KeyboardInterrupt for Python-level loops. So in practice our handler is
# a harmless fallback that cysignals supersedes — and that's the good outcome.
#
# CAVEAT carried to the parent: do NOT assume SIGINT always lands. Sage code
# *not* wrapped in sig_on/sig_off, or a tight loop in pure-C that never reaches
# a check, can still ignore it. The controller therefore escalates SIGINT -> a
# hard process-group kill if the worker doesn't acknowledge within a grace
# window (spec policy: brutal restart is acceptable).

def _sigint_handler(signum, frame):  # fallback; cysignals overrides this
    raise KeyboardInterrupt()


signal.signal(signal.SIGINT, _sigint_handler)


# ---------------------------------------------------------------------------
# Sage bootstrap.
# ---------------------------------------------------------------------------

from sage.all import *  # noqa: E402,F401,F403  (the whole point is the star)
from sage.repl.preparse import preparse  # noqa: E402

# The persistent user namespace. Seeded with everything `from sage.all import *`
# exposes, exactly like an interactive Sage session, so unqualified names such
# as `var`, `matrix`, `factor`, `x` resolve.
NS = {}
exec("from sage.all import *", NS)


# ---------------------------------------------------------------------------
# Casette preload helpers.
# ---------------------------------------------------------------------------
#
# These are humane calculator APIs layered over Sage/Python's rougher names.
# They are installed BEFORE the symbol-table baseline so they behave like
# built-ins: raw users can call them, friendly compiler lowerings can target
# them, and untouched helpers do not clutter the Symbols sidebar.

def _casette_require_positive(name, value):
    if value <= 0:
        raise ValueError("%s must be positive" % name)


def _casette_require_probability(name, value):
    if value < 0 or value > 1:
        raise ValueError("%s must be between 0 and 1" % name)


def _casette_int(name, value):
    ivalue = int(value)
    if value != ivalue:
        raise ValueError("%s must be an integer" % name)
    return ivalue


try:
    from scipy.stats import norm as _casette_scipy_norm  # noqa: E402
except Exception:  # noqa: BLE001 - helper calls raise clearly if fallback fails
    _casette_scipy_norm = None


def normal_pdf(x, mean=0, sd=1):
    _casette_require_positive("sd", sd)
    if _casette_scipy_norm is not None:
        return _casette_scipy_norm.pdf(x, loc=mean, scale=sd)
    z = (x - mean) / sd
    return exp(-z**2 / 2) / (sd * sqrt(2 * pi))  # noqa: F405


def normal_cdf(x, mean=0, sd=1):
    _casette_require_positive("sd", sd)
    if _casette_scipy_norm is not None:
        return _casette_scipy_norm.cdf(x, loc=mean, scale=sd)
    d = RealDistribution("gaussian", sd)  # noqa: F405
    return d.cum_distribution_function(x - mean)


def normal_between(a, b, mean=0, sd=1):
    return normal_cdf(b, mean=mean, sd=sd) - normal_cdf(a, mean=mean, sd=sd)


def normal_inv(p, mean=0, sd=1):
    _casette_require_probability("p", p)
    _casette_require_positive("sd", sd)
    if _casette_scipy_norm is not None:
        return _casette_scipy_norm.ppf(p, loc=mean, scale=sd)
    d = RealDistribution("gaussian", sd)  # noqa: F405
    return mean + d.cum_distribution_function_inv(p)


def binomial_pmf(k, n, p):
    k = _casette_int("k", k)
    n = _casette_int("n", n)
    _casette_require_probability("p", p)
    if n < 0:
        raise ValueError("n must be nonnegative")
    if k < 0 or k > n:
        return 0
    return binomial(n, k) * p**k * (1 - p)**(n - k)  # noqa: F405


def binomial_between(a, b, n, p):
    a = _casette_int("a", a)
    b = _casette_int("b", b)
    if b < a:
        return 0
    return sum(binomial_pmf(i, n=n, p=p) for i in range(a, b + 1))


def binomial_at_most(k, n, p):
    k = _casette_int("k", k)
    return binomial_between(0, k, n=n, p=p)


def binomial_cdf(k, n, p):
    return binomial_at_most(k, n=n, p=p)


def binomial_at_least(k, n, p):
    k = _casette_int("k", k)
    n = _casette_int("n", n)
    return binomial_between(k, n, n=n, p=p)


def poisson_pmf(k, lambda_):
    k = _casette_int("k", k)
    _casette_require_positive("lambda", lambda_)
    if k < 0:
        return 0
    return exp(-lambda_) * lambda_**k / factorial(k)  # noqa: F405


def poisson_between(a, b, lambda_):
    a = _casette_int("a", a)
    b = _casette_int("b", b)
    if b < a:
        return 0
    return sum(poisson_pmf(i, lambda_=lambda_) for i in range(a, b + 1))


def poisson_at_most(k, lambda_):
    k = _casette_int("k", k)
    return poisson_between(0, k, lambda_=lambda_)


def poisson_cdf(k, lambda_):
    return poisson_at_most(k, lambda_=lambda_)


def poisson_at_least(k, lambda_):
    k = _casette_int("k", k)
    return 1 - poisson_at_most(k - 1, lambda_=lambda_)


def exponential_pdf(x, rate):
    _casette_require_positive("rate", rate)
    if x < 0:
        return 0
    return rate * exp(-rate * x)  # noqa: F405


def exponential_cdf(x, rate):
    _casette_require_positive("rate", rate)
    if x < 0:
        return 0
    return 1 - exp(-rate * x)  # noqa: F405


def exponential_between(a, b, rate):
    if b < a:
        return 0
    return exponential_cdf(b, rate=rate) - exponential_cdf(a, rate=rate)


def exponential_inv(p, rate):
    _casette_require_probability("p", p)
    _casette_require_positive("rate", rate)
    return -log(1 - p) / rate  # noqa: F405


def uniform_pdf(x, low, high):
    if high <= low:
        raise ValueError("high must be greater than low")
    if x < low or x > high:
        return 0
    return 1 / (high - low)


def uniform_cdf(x, low, high):
    if high <= low:
        raise ValueError("high must be greater than low")
    if x <= low:
        return 0
    if x >= high:
        return 1
    return (x - low) / (high - low)


def uniform_between(a, b, low, high):
    if b < a:
        return 0
    return uniform_cdf(b, low=low, high=high) - uniform_cdf(a, low=low, high=high)


def uniform_inv(p, low, high):
    _casette_require_probability("p", p)
    if high <= low:
        raise ValueError("high must be greater than low")
    return low + p * (high - low)


class _CasetteSVDResult:
    """Display wrapper for Sage's three-matrix SVD tuple.

    Sage returns `(U, S, V)` as a tuple. A tuple's default LaTeX is unlabeled,
    which makes the tape hard to read. This wrapper keeps the plain fallback
    simple and gives the math renderer an explicit `U`, `S`, `V` display.
    """

    def __init__(self, factors):
        self.factors = tuple(factors)
        if len(self.factors) != 3:
            raise ValueError("SVD() did not return three matrices")

    def __iter__(self):
        return iter(self.factors)

    def __len__(self):
        return len(self.factors)

    def __str__(self):
        labels = ("U", "S", "V")
        return "\n\n".join("%s =\n%s" % (label, matrix)
                           for label, matrix in zip(labels, self.factors))

    def __repr__(self):
        return "_CasetteSVDResult(%r)" % (self.factors,)

    def _latex_(self):
        labels = ("U", "S", "V")
        pieces = []
        for label, matrix in zip(labels, self.factors):
            pieces.append("%s = %s" % (label, latex(matrix)))  # noqa: F405
        return "\\qquad ".join(pieces)


def __casette_svd_labeled(factors):
    return _CasetteSVDResult(factors)


def _install_casette_preloads(ns):
    names = [
        "normal_pdf", "normal_cdf", "normal_between", "normal_inv",
        "binomial_pmf", "binomial_cdf", "binomial_between",
        "binomial_at_most", "binomial_at_least",
        "poisson_pmf", "poisson_cdf", "poisson_between",
        "poisson_at_most", "poisson_at_least",
        "exponential_pdf", "exponential_cdf", "exponential_between",
        "exponential_inv",
        "uniform_pdf", "uniform_cdf", "uniform_between", "uniform_inv",
    ]
    for name in names:
        ns[name] = globals()[name]
    ns["__casette_svd_labeled"] = __casette_svd_labeled
    ns["TAU"] = 2 * pi  # noqa: F405
    ns["PHI"] = (1 + sqrt(5)) / 2  # noqa: F405


_install_casette_preloads(NS)

# V0.6 — Live symbol-table baseline.
# ----------------------------------
# The `symbols` op shows only USER-created bindings, so we must know what the
# namespace held *before* any user code ran. We snapshot {name: id(object)} for
# every binding the star-import + plumbing put there (`var`, `matrix`, `pi`, the
# predefined `x`, the exported functions `n`/`N`, the Gaussian `i`, every dunder,
# …). A name surfaces as user-created iff it is EITHER absent from the baseline
# OR still present but now bound to a DIFFERENT object (identity changed → the
# user reassigned it).
#
# Why identity, not just name: Sage exports very common variable names as
# functions — `n` is `numerical_approx`, `N` is `numerical_approx`, `i` is the
# Gaussian unit. A user who writes `n = 104729` (a spec test case!) MUST see `n`
# in the sidebar, so a name-only diff is wrong; the identity diff catches the
# reassignment. Trade-off: if a user rebinds a name to the *same* object Sage
# already had there, it won't surface — vanishingly rare and harmless. Brand-new
# names (the common case) always surface.
#
# We keep the baseline OBJECTS (not just their ids) so a baseline object can't
# be garbage-collected and have its id() recycled by a later user object — which
# would otherwise make an identity check lie. `is` on the live binding vs the
# stored object is exact.
_SYMBOL_BASELINE = dict(NS)
_SYMBOL_BASELINE_MISS = object()  # sentinel: "name not in baseline"


# ---------------------------------------------------------------------------
# V0.5 — Plot & artifact pipeline.
# ---------------------------------------------------------------------------
#
# Goal: when an eval produces a Sage Graphics (a plot), save it to an image file
# and report it in the envelope's `artifacts` array, so the parent app can render
# it. The contract (frozen in plans/WORKER-PROTOCOL.md):
#
#     "artifacts": [
#         {"type": "image", "format": "svg", "path": "/tmp/sagecalc/session-<id>/plot-<n>.svg",
#          "width": 480, "height": 360, "bytes": 20542}
#     ]
#
# Decisions owned here (documented in WORKER-PROTOCOL.md):
#
#  * DIRECTORY LAYOUT. One session-scoped dir per worker process:
#      /tmp/sagecalc/session-<pid>-<rand>/
#    created lazily on the first plot. The <pid> ties it to this worker; the
#    random suffix prevents collision if a pid is recycled. All of a worker's
#    plot files live here for its whole lifetime.
#
#  * LIFETIME. The directory lives as long as the worker process. On a clean
#    shutdown (`op:"shutdown"`) the worker removes it. On a hard kill it is left
#    behind, but it is under /tmp (OS-reaped) and namespaced by pid+rand so it
#    never collides with a future worker. The parent app may also delete the
#    whole `/tmp/sagecalc/` tree on launch. (Per-eval files are NOT deleted while
#    the worker lives, so the UI can re-load an older tape entry's plot.)
#
#  * UNIQUE FILENAMES. A monotonic per-worker counter (`plot-00001.svg`,
#    `plot-00002.svg`, …) guarantees no collision across multiple plots in one
#    eval and across rapid successive evals. The counter never resets while the
#    worker lives.
#
#  * FORMAT. SVG first (vector, crisp at any zoom — proven to save cleanly in
#    Sage 9.5), with PNG saved ALONGSIDE as a fallback for renderers that can't
#    do SVG. Both are reported in `artifacts`; the SVG entry comes first. The
#    worker never fails an eval just because one format failed to save.
#
#  * TWO CAPTURE CHANNELS, so "several plots in one eval" works:
#      1. The echoed return value — if the trailing expression is a Graphics /
#         GraphicsArray, it is saved. (Covers `plot(sin(x), (x,-pi,pi))`.)
#      2. `.show()` — we wrap Graphics.show / GraphicsArray.show during eval so
#         every `p.show()` saves an artifact instead of trying to open a GUI
#         window (which would be wrong in a headless worker). Covers
#         `p1.show(); p2.show()` in one eval.
#    De-duplicated by object identity so a plot that is both shown and echoed is
#    saved once.
#
#  * FAILURES ARE STRUCTURED. A save error (bad format, unwritable dir, an
#    object whose .save() raises) is caught: that artifact is recorded as
#    {"type":"image","error":"..."} rather than crashing the eval or corrupting
#    the protocol. The eval still returns its normal envelope.

import shutil as _shutil  # noqa: E402

# Session-scoped artifact dir, created lazily. One per worker lifetime.
_ARTIFACT_ROOT = "/tmp/sagecalc"
_SESSION_DIR = None
_PLOT_COUNTER = 0

# The Sage classes whose instances are saveable plots. GraphicsArray lives in a
# different module (sage.plot.multigraphics) but has the same .save() contract.
try:
    from sage.plot.graphics import Graphics as _Graphics
except Exception:  # pragma: no cover
    _Graphics = ()
try:
    from sage.plot.multigraphics import GraphicsArray as _GraphicsArray
    _MultiGraphics = (_GraphicsArray,)
except Exception:  # pragma: no cover
    _MultiGraphics = ()

_PLOT_TYPES = tuple(t for t in (_Graphics,) + _MultiGraphics if isinstance(t, type))


def _is_plot(value):
    """True if `value` is a saveable 2D Sage plot (Graphics / GraphicsArray)."""
    return bool(_PLOT_TYPES) and isinstance(value, _PLOT_TYPES)


def _session_dir():
    """Lazily create and return this worker's session-scoped artifact dir."""
    global _SESSION_DIR
    if _SESSION_DIR is None:
        import binascii
        rand = binascii.hexlify(os.urandom(4)).decode()
        _SESSION_DIR = os.path.join(
            _ARTIFACT_ROOT, "session-%d-%s" % (os.getpid(), rand))
        os.makedirs(_SESSION_DIR, exist_ok=True)
    return _SESSION_DIR


def _cleanup_session_dir():
    """Remove the session dir on clean shutdown. Best-effort."""
    global _SESSION_DIR
    if _SESSION_DIR and os.path.isdir(_SESSION_DIR):
        try:
            _shutil.rmtree(_SESSION_DIR, ignore_errors=True)
        except Exception:
            pass
    _SESSION_DIR = None


def _save_plot_artifact(plot_obj):
    """Save one plot to SVG (+ PNG fallback). Return a list of artifact dicts.

    SVG is reported first; PNG alongside as a fallback. A per-format save error
    is captured into a structured artifact entry, never raised — one bad format
    must not corrupt the protocol or fail the eval.
    """
    global _PLOT_COUNTER
    _PLOT_COUNTER += 1
    stem = "plot-%05d" % _PLOT_COUNTER

    # Probe the rendered pixel size (for the UI's intrinsic size). Best-effort:
    # Graphics has a default 480x360-ish figure; we don't hard-fail if absent.
    artifacts = []
    for fmt in ("svg", "png"):
        path = os.path.join(_session_dir(), "%s.%s" % (stem, fmt))
        try:
            plot_obj.save(path)
            size = os.path.getsize(path)
            if size <= 0:
                raise IOError("saved file is empty")
            artifacts.append({
                "type": "image",
                "format": fmt,
                "path": path,
                "bytes": size,
            })
        except Exception as exc:  # noqa: BLE001 - any save failure is structured
            artifacts.append({
                "type": "image",
                "format": fmt,
                "path": None,
                "error": "%s: %s" % (type(exc).__name__, exc),
            })
    return artifacts


# Per-eval collector for plots captured via `.show()`. Reset at the start of
# each eval; a list of (object) refs in call order, de-duplicated by identity.
_SHOWN_PLOTS = []
_orig_graphics_show = None
_orig_multigraphics_show = None


def _install_show_hooks():
    """Wrap Graphics.show / GraphicsArray.show to collect, not display.

    In a headless worker, `.show()` must not try to open a GUI window. We record
    the plot for artifact saving instead. Idempotent.
    """
    global _orig_graphics_show, _orig_multigraphics_show
    if _Graphics and isinstance(_Graphics, type) and _orig_graphics_show is None:
        _orig_graphics_show = _Graphics.show

        def _show(self, *a, **k):  # noqa: ANN001
            _SHOWN_PLOTS.append(self)
        _Graphics.show = _show

    if _MultiGraphics and _orig_multigraphics_show is None:
        cls = _MultiGraphics[0]
        _orig_multigraphics_show = cls.show

        def _mshow(self, *a, **k):  # noqa: ANN001
            _SHOWN_PLOTS.append(self)
        cls.show = _mshow


# ---------------------------------------------------------------------------
# V0.3 — Result classification & the result envelope.
# ---------------------------------------------------------------------------
#
# The job of this section: turn an arbitrary Sage/Python value into a small,
# STABLE result envelope the app can render without re-deriving anything:
#
#   kind      one of the spec's fixed result kinds (see KINDS below)
#   plain     str(value), capped (the human-readable text)
#   latex     Sage LaTeX where it renders, else null
#   repr      repr(value), capped (the unambiguous form; the safety net)
#   approx    a numeric approximation string where meaningful, else null
#   actions   result-kind-aware op names the UI can offer (V1.10 wires them up)
#   artifacts always [] here; V0.5 fills it (plot files etc.)
#   truncated bool: was plain/repr capped? (so the UI can say "truncated")
#
# Design rules:
#   * Unknown objects DEGRADE to repr, they never fail classification.
#   * Large outputs are CAPPED with an explicit `truncated` flag + the policy
#     in `truncation` so the UI can show "… (truncated, N of M chars)".
#   * `approx` is per-kind, not blind: exact scalars (rational/real/complex/
#     symbolic-constant) get one; things where it makes no sense (a matrix of
#     symbols, a list, a relation, a plot) degrade to null gracefully.

# The fixed kind set (spec "Minimum Result Kinds" + the framing kinds the
# protocol already uses). Stable; the app renders against these names.
KINDS = (
    "integer", "rational", "real", "complex", "symbolic", "relation",
    "list", "matrix", "plot", "text", "boolean", "none", "error", "unknown",
)

# Output cap. str()/repr() of e.g. `list(range(10^6))` or `factorial(10^5)`
# (a ~456 KB decimal) is huge; we never put an unbounded string on the wire.
# Cap, flag it, and record the policy so the UI can be honest about it.
_MAX_PLAIN = 8192   # chars kept for `plain`
_MAX_REPR = 8192    # chars kept for `repr`
_MAX_LATEX = 16384  # chars kept for `latex` (LaTeX of a huge object is useless)
_MAX_STDOUT = 32768  # chars kept for captured stdout/stderr
_ELLIPSIS = " …"


# Per-kind UI action menus. These are *names*; V1.10 maps them to follow-up
# evals (e.g. selecting "det" on a matrix `A` runs `A.det()`). Driving the UI
# from result metadata is a V0.3 exit criterion, so this table is the proof.
_ACTIONS = {
    "integer": ["factor", "is_prime", "next_prime", "approx", "hex"],
    "rational": ["numerator", "denominator", "approx", "continued_fraction"],
    "real": ["approx_more_digits", "round", "continued_fraction"],
    "complex": ["real_part", "imag_part", "abs", "arg", "conjugate"],
    "symbolic": [
        "simplify", "trig_simplify", "factor", "expand", "approx", "diff",
        "integrate",
    ],
    "relation": ["solve", "lhs", "rhs", "subtract_sides"],
    "matrix": [
        "det", "rank", "rref", "eigenvalues", "transpose", "inverse",
        "column_space", "row_space", "right_kernel",
    ],
    "list": ["length", "sort", "sum", "set"],
    "plot": ["save_png", "save_svg", "show"],
    "text": ["copy"],
    "boolean": [],
    "unknown": ["repr", "type"],
}


def _cap(text, limit):
    """Cap `text` at `limit` chars. Returns (capped_text, was_truncated)."""
    if text is None:
        return None, False
    if len(text) <= limit:
        return text, False
    return text[:limit] + _ELLIPSIS, True


def _cap_captured_stream(text, name):
    """Cap captured stdout/stderr so help() cannot freeze the app UI."""
    capped, truncated = _cap(text, _MAX_STDOUT)
    if not truncated:
        return capped
    omitted = len(text) - _MAX_STDOUT
    return (
        capped
        + "\n\n[Casette truncated %s after %d characters; %d characters omitted.]"
        % (name, _MAX_STDOUT, omitted)
    )


def _classify(value):
    """Return a `kind` string from the fixed KINDS set for any value.

    Keyed off type/module so it survives Sage's many concrete classes (e.g. a
    Gaussian integer is a number-field element; a high-precision real is an
    mpfr). Anything we don't recognise is `unknown` — never an error."""
    if value is None:
        return "none"

    mod = type(value).__module__ or ""
    name = type(value).__name__

    # bool is an int subclass — check it FIRST so True/False isn't "integer".
    if isinstance(value, bool):
        return "boolean"

    # Sage numeric types, keyed off their module path.
    if "sage.rings.integer" in mod:
        return "integer"
    if "sage.rings.rational" in mod:
        return "rational"
    if "sage.rings.real" in mod:               # real_mpfr, real_double, …
        return "real"
    if "sage.rings.complex" in mod:            # complex_mpfr, complex_double, …
        return "complex"
    # `3 + 4*I` is a Gaussian element of QQ[i], a *number-field* element — not
    # under sage.rings.complex. Catch the Gaussian/complex number-field cases.
    if "number_field" in mod and ("gaussian" in name.lower()
                                  or "Cyclotomic" in name):
        return "complex"

    if "sage.matrix" in mod:
        return "matrix"

    if isinstance(value, _CasetteSVDResult):
        return "list"

    if "sage.symbolic.expression" in mod:
        # Relations (==, <, >, …) share the Expression type but are their own
        # kind: they drive a different action menu (solve, lhs, rhs).
        try:
            if value.is_relational():
                return "relation"
        except Exception:
            pass
        return "symbolic"

    if "sage.plot" in mod or "Graphics" in name:
        return "plot"

    # Plain-Python and Sage list-likes. `solve(...)` returns a
    # sage.structure.sequence.Sequence_generic, which IS a list subclass, so
    # this isinstance catches it too.
    if isinstance(value, (list, tuple)):
        return "list"
    if isinstance(value, int):
        return "integer"
    if isinstance(value, float):
        return "real"
    if isinstance(value, str):
        return "text"

    return "unknown"


def _safe_str(value):
    try:
        return str(value)
    except Exception as exc:  # pragma: no cover - defensive
        return "<unprintable: %r>" % (exc,)


def _safe_repr(value):
    try:
        return repr(value)
    except Exception as exc:  # pragma: no cover - defensive
        return "<unrepr-able: %r>" % (exc,)


def _safe_latex(value):
    """Best-effort LaTeX. Never raise; return None if Sage can't render it.

    We cap LaTeX too: the LaTeX of `list(range(10^6))` is megabytes and useless
    to a renderer."""
    try:
        s = _vector_sequence_latex(value)
        if s is None:
            s = str(latex(value))  # noqa: F405 (latex from sage.all)
    except Exception:
        return None
    capped, _ = _cap(s, _MAX_LATEX)
    return capped


def _vector_sequence_latex(value):
    """Custom LaTeX for a Sage sequence of vectors, e.g. `M.right_kernel().basis()`.

    Sage's default tuple-list shape (`\left[\left(1,\,-2,\,1\right)\right]`)
    is semantically thin for a vector-space basis and can crash SwiftMath during
    layout. When the value is specifically a sequence of Sage vectors, render it
    as a set of column vectors instead. Ordinary lists, solve results, and other
    sequences keep Sage's own LaTeX.
    """
    if type(value).__module__ != "sage.structure.sequence":
        return None

    try:
        items = list(value)
    except Exception:
        return None

    if not items:
        try:
            universe = str(value.universe())
        except Exception:
            return None
        return "\\mathcal{B} = \\varnothing" if "Free module" in universe else None

    if not all(_is_vector_like(item) for item in items):
        return None

    columns = []
    for item in items:
        entries = list(item)
        if not entries:
            return None
        columns.append(
            "\\begin{pmatrix}"
            + " \\\\ ".join(str(latex(entry)) for entry in entries)  # noqa: F405
            + "\\end{pmatrix}")

    return "\\mathcal{B} = \\left\\{" + ", ".join(columns) + "\\right\\}"


def _is_vector_like(value):
    mod = type(value).__module__ or ""
    if "sage.modules.vector" not in mod:
        return False
    try:
        len(value)
        iter(value)
        return True
    except Exception:
        return False


def _matrix_base_ring_is_rdf_or_cdf(value):
    try:
        base_ring = value.base_ring()
    except Exception:
        return False
    try:
        return bool(base_ring == RDF or base_ring == CDF)  # noqa: F405
    except Exception:
        return str(base_ring) in ("Real Double Field", "Complex Double Field")


def _actions_for(value, kind):
    actions = list(_ACTIONS.get(kind, []))
    if kind == "matrix":
        actions.append("change_ring_RDF")
        if _matrix_base_ring_is_rdf_or_cdf(value):
            actions.append("svd")
    return actions


# ---------------------------------------------------------------------------
# V0.8 — Exact / numeric display policy.
# ---------------------------------------------------------------------------
#
# The product policy: an EXACT result is the primary value; its approximation is
# secondary (shown with "≈", or on demand). The spec's desired display for
# `1/3 + 1/5` is:
#
#     8/15
#     ≈ 0.5333333333
#
# To drive that, the envelope carries (in addition to the V0.3 `approx` string):
#
#   exact            true | false | null
#       Is the PRIMARY result an exact value?
#         true  — integer, rational, exact symbolic (sqrt(2), pi, sin(1), 8/15).
#         false — an inherently approximate real/complex (a 53-bit RealLiteral
#                 from `2.5`, a RealNumber from `N(sqrt(2),digits=50)`, sin(1.0),
#                 or an inexact symbolic like `2.5 + sqrt(2)`).
#         null  — exactness is not a scalar property here (matrix, list,
#                 relation, plot, text, boolean, none, error, unknown).
#
#   primary_is_approx  bool
#       Should the UI put the "≈" on the PRIMARY value (not the secondary)?
#         true  — the primary already IS an approximation: an inexact real/
#                 complex (N(...), 2.5), or a force-numeric request. Then `plain`
#                 is the number to mark with "≈"; `approx`/secondary is null.
#         false — primary is exact; show it plainly, with `approx` as the "≈"
#                 secondary line.
#
#   approx           string | null   (unchanged meaning: the decimal string)
#   approx_digits    int    | null   the precision (decimal digits) `approx` carries
#
# WHY exactness can NOT be read off `parent().is_exact()`:
#   The whole Symbolic Ring reports `parent().is_exact() == False`, so sqrt(2),
#   pi, sin(1) would all be called "inexact" — wrong. Exactness is decided
#   per-kind, and for symbolic by a tree-walk for inexact numeric atoms (below).
#
# PRECISION is configurable two ways (documented in WORKER-PROTOCOL.md):
#   * session default: {"op":"config","precision_digits":N}   (default 10)
#   * per request override: {"id":..,"code":..,"precision_digits":N}
# FORCE-NUMERIC is a per-request flag: {"id":..,"code":..,"numeric":true} makes
#   the PRIMARY result the numeric approximation (N() at the effective digits),
#   WITHOUT mutating the session — stored variables stay exact (proven: `y = 1/3`
#   with numeric:true leaves NS['y'] an exact Rational 1/3).

import math as _math

# Session-level default precision for `approx` (decimal digits). The spec's
# desired "≈ 0.5333333333" is 10 significant digits, so 10 is the default.
DEFAULT_PRECISION_DIGITS = 10
_PRECISION_DIGITS = DEFAULT_PRECISION_DIGITS

# Decimal digits -> binary bits (a real with D decimal digits needs
# ceil(D*log2(10)) bits; +1 of headroom). Used to clamp a precision request to a
# concrete value's own precision so `.n(bits)` never raises "use at most N bits".
_LOG2_10 = _math.log2(10)


def _digits_to_bits(digits):
    return int(_math.ceil(digits * _LOG2_10)) + 1


def _symbolic_has_inexact_atom(expr):
    """True if a symbolic expression contains an inexact numeric leaf.

    Walks the expression tree; a leaf is inexact iff it is a numeric whose
    parent ring reports `is_exact() == False` (a RealLiteral/RealNumber/
    ComplexNumber). So `2.5 + sqrt(2)` and `1.5*x` are inexact, while
    `sqrt(2)`, `pi`, `sin(1)`, `sin(pi/3)`, `sqrt(2)+pi` are exact. Never raises.
    """
    try:
        ops = expr.operands()
    except Exception:
        ops = []
    if not ops:  # leaf
        try:
            if expr.is_numeric():
                p = expr.pyobject().parent()
                return hasattr(p, "is_exact") and not p.is_exact()
        except Exception:
            return False
        return False
    try:
        return any(_symbolic_has_inexact_atom(o) for o in ops)
    except Exception:
        return False


def _is_exact(value, kind):
    """Is the primary `value` an EXACT value? Returns True / False / None.

    None for kinds where exactness is not a scalar property (matrix, list,
    relation, plot, text, boolean, none, error, unknown). Never raises.
    """
    if kind == "integer" or kind == "rational":
        return True
    if kind == "real" or kind == "complex":
        # A concrete float-backed real/complex (RealLiteral from `2.5`,
        # RealNumber from `N(...)`, mpc) is inherently approximate.
        return False
    if kind == "symbolic":
        # Exact unless the expression carries an inexact numeric atom.
        try:
            return not _symbolic_has_inexact_atom(value)
        except Exception:
            return True
    return None


def _napprox_string(value, kind, digits):
    """Numeric approximation of `value` to ~`digits` decimal digits, as a string.

    Clamps the requested precision to a concrete value's OWN precision so
    `.n(bits)` never raises the Sage "cannot approximate to N bits, use at most
    M" error (PROBLEMS.md). Exact values (rational / symbolic-constant) get the
    full requested precision. Returns None when no scalar approximation applies.
    """
    if kind not in ("rational", "real", "complex", "symbolic"):
        return None
    # A symbolic with free variables has no single numeric value.
    try:
        if hasattr(value, "variables") and len(value.variables()) > 0:
            return None
    except Exception:
        pass
    bits_wanted = _digits_to_bits(digits)
    # Concrete real/complex: it has a fixed native precision. Clamp the request
    # to it (asking for MORE bits than it holds raises), then approximate. This
    # keeps `N(sqrt(2),digits=50)` (170 bits) showing 10 digits cleanly and
    # never downcasts below what was asked when fewer digits are wanted.
    try:
        own = value.prec()
        bits = min(bits_wanted, own)
        return str(value.n(bits))
    except (AttributeError, TypeError):
        pass
    # Exact value (rational / symbolic-constant): full requested precision.
    try:
        return str(value.n(digits=digits))
    except Exception:
        pass
    try:
        return str(value.n(bits_wanted))
    except Exception:
        pass
    try:
        return repr(round(float(value), max(0, digits)))
    except Exception:
        return None


def _approx(value, kind, digits=None):
    """Backwards-compatible wrapper: the V0.3 `approx` decimal string, or None.

    `digits` defaults to the session precision. Kept so existing callers/tests
    that don't pass digits behave as before; V0.8 callers pass an explicit
    effective precision.
    """
    if digits is None:
        digits = _PRECISION_DIGITS
    return _napprox_string(value, kind, digits)


def _build_envelope(value, artifacts=None, digits=None, numeric=False):
    """Turn an evaluated value into the result envelope fields.

    `artifacts` (V0.5) is the already-collected list of artifact dicts (plot
    files saved during the eval); defaults to [].

    V0.8 parameters:
      * `digits` — decimal precision for the `approx` field (defaults to the
        session precision `_PRECISION_DIGITS`).
      * `numeric` — force-numeric mode: make the PRIMARY result the numeric
        approximation. The exact value (if any) moves to `exact_value`, `plain`
        becomes the decimal, `primary_is_approx` is True, and the secondary
        `approx` is null (the primary already IS the number).

    Emits the V0.3 fields plus the V0.8 exact/numeric policy fields:
    `exact`, `approx_digits`, `primary_is_approx`, and (in numeric mode)
    `exact_value`. Never raises: an exotic object degrades to its repr with
    kind="unknown"."""
    if digits is None:
        digits = _PRECISION_DIGITS
    kind = _classify(value)
    exact = _is_exact(value, kind)

    plain_full = _safe_str(value)
    repr_full = _safe_repr(value)
    latex_str = _safe_latex(value)
    approx_str = _napprox_string(value, kind, digits)

    # primary_is_approx: does the "≈" belong on the PRIMARY value?
    #   * force-numeric request -> yes (we're replacing the primary with N()).
    #   * an inherently approximate real/complex/inexact-symbolic -> yes (the
    #     primary IS already a float; there's nothing more exact to show).
    #   * an exact result -> no; the exact form is primary, approx is secondary.
    primary_is_approx = bool(numeric and approx_str is not None) or (exact is False)

    exact_value = None
    if numeric and approx_str is not None:
        # Force-numeric: the numeric string becomes the primary `plain`. Preserve
        # the original exact form (for "show exact" toggles / provenance) as
        # `exact_value`, but DO NOT mutate the namespace — the caller evaluated
        # the value normally; we only re-present it here.
        exact_value = plain_full
        plain_full = approx_str
        repr_full = approx_str
        approx_str = None  # primary already carries the number; no secondary.

    plain, plain_trunc = _cap(plain_full, _MAX_PLAIN)
    repr_s, repr_trunc = _cap(repr_full, _MAX_REPR)
    truncated = plain_trunc or repr_trunc

    actions = _actions_for(value, kind)

    env = {
        "kind": kind,
        "plain": plain,
        "latex": latex_str,
        "repr": repr_s,
        "approx": approx_str,
        "approx_digits": digits if approx_str is not None else None,
        "exact": exact,
        "primary_is_approx": primary_is_approx,
        "actions": actions,
        "artifacts": list(artifacts) if artifacts else [],
        "truncated": truncated,
    }
    if exact_value is not None:
        env["exact_value"] = exact_value
    if truncated:
        # Make the cap policy explicit so the UI can say exactly what happened.
        env["truncation"] = {
            "plain_len": len(plain_full),
            "repr_len": len(repr_full),
            "plain_cap": _MAX_PLAIN,
            "repr_cap": _MAX_REPR,
        }
    return env


# ---------------------------------------------------------------------------
# V0.6 — Live symbol-table introspection (the `symbols` op).
# ---------------------------------------------------------------------------
#
# Request:  {"id":"s-1","op":"symbols"}
# Response: {"id":"s-1","ok":true,"op":"symbols",
#            "symbols":[{"name":"x","kind":"symbolic variable","summary":"x"},
#                       {"name":"A","kind":"matrix","summary":"2×2 over Integer Ring"}]}
#
# Design decisions (frozen in plans/WORKER-PROTOCOL.md):
#
#  * FILTERING — only user-created bindings. We diff the live namespace against
#    `_SYMBOL_BASELINE` (snapshot taken before any user code: the star-import,
#    dunders, plumbing). A name not in the baseline is user-created. Dunder names
#    (`__…__`) are skipped too as a belt-and-suspenders guard. This guarantees
#    NO Sage builtins / imports / worker internals ever leak into the sidebar.
#
#  * WHAT COUNTS AS A USER SYMBOL — anything the user bound to a NEW name:
#    values (Integer, matrix, list, …), symbolic variables (`var("x")`),
#    symbolic functions (`f(x)=sin(x)/x` — Sage preparses this to a *callable
#    symbolic expression* assignment, so it lands as a normal binding and DOES
#    appear), and user `import`s / `def`s (a module / function binding). We
#    classify modules and functions distinctly rather than hide them, because
#    they're real things the user created and the sidebar should show them.
#
#  * SUMMARIES ARE BOUNDED AND CHEAP — never stringify a huge object. A matrix
#    summarizes structurally ("200×200 over Integer Ring") from nrows/ncols/
#    base_ring; a list/tuple/set/dict as "list of N items" from len() only; a
#    long scalar's str() is capped to _MAX_SUMMARY chars. So inspecting
#    `big_list = list(range(10**6))` is microseconds and yields a 21-char
#    summary, never a 7.9 MB stringification. Measured: cheap summary ~1e-5 s vs
#    str() ~0.05 s and megabytes. Objects whose __repr__/__str__ RAISE degrade
#    to a placeholder ("<unprintable: ExcType>"), never crash the op.
#
#  * KIND VOCABULARY — reuses the V0.3 envelope kinds (integer, rational, real,
#    complex, symbolic, relation, list, matrix, plot, text, boolean, none,
#    unknown) PLUS three symbol-table-only kinds:
#        "symbolic variable"  — a bare SR symbol from var() (x.is_symbol())
#        "symbolic function"  — a callable symbolic expr, f(x)=…
#        "module"             — a user `import`
#        "function"           — a user `def`/lambda or other callable
#    (matrix/list/etc. classify exactly as in the result envelope.)

_MAX_SUMMARY = 200  # chars; a symbol summary is a sidebar label, kept short.


def _is_symbolic_variable(value):
    """True for a bare symbolic symbol, e.g. `x = var("x")`."""
    if "sage.symbolic.expression" not in (type(value).__module__ or ""):
        return False
    try:
        return bool(value.is_symbol())
    except Exception:
        return False


def _is_symbolic_function(value):
    """True for a callable symbolic expression, e.g. `f(x) = sin(x)/x`.

    Sage preparses `f(x) = …` to an assignment of a *callable symbolic
    expression* whose parent is a CallableSymbolicExpressionRing. Detect via the
    parent ring's class name so we don't import a private class."""
    if "sage.symbolic.expression" not in (type(value).__module__ or ""):
        return False
    try:
        parent = value.parent()
    except Exception:
        return False
    return "Callable" in type(parent).__name__


def _symbol_kind(value):
    """Classify a namespace binding for the symbol table.

    Extends the V0.3 result classifier with symbol-table-only kinds (symbolic
    variable / symbolic function / module / function) and otherwise reuses
    `_classify`."""
    import types as _types
    if isinstance(value, _types.ModuleType):
        return "module"
    if _is_symbolic_variable(value):
        return "symbolic variable"
    if _is_symbolic_function(value):
        return "symbolic function"
    # Plain Python callables the user `def`d / assigned a lambda. (Sage classes
    # like Integer are callable too, but they classify via _classify first; only
    # bare Python functions reach here as "function".)
    if isinstance(value, (_types.FunctionType, _types.LambdaType,
                          _types.BuiltinFunctionType)):
        return "function"
    return _classify(value)


def _bounded(text):
    """Cap a summary string at _MAX_SUMMARY chars (never an unbounded label)."""
    if text is None:
        return ""
    if len(text) > _MAX_SUMMARY:
        return text[:_MAX_SUMMARY] + _ELLIPSIS
    return text


def _symbol_summary(value, kind):
    """A SHORT, BOUNDED, CHEAP one-line summary for a symbol-table entry.

    Must never trigger a big computation or a huge stringification: structural
    summaries (matrix dims, container length) are computed from metadata, not by
    rendering the object. Falls back to a capped str() only for small scalars.
    Never raises — a value whose str()/repr() blows up degrades to a placeholder.
    """
    try:
        # Matrix: dims + base ring, no element stringification. "2×2 over ZZ".
        if kind == "matrix":
            try:
                return _bounded("%d×%d over %s" % (
                    value.nrows(), value.ncols(), value.base_ring()))
            except Exception:
                pass

        # Containers: length only, never the elements. "list of 1000000 items".
        if kind == "list" or isinstance(value, (list, tuple, set, frozenset, dict)):
            try:
                tname = type(value).__name__
                # Normalise the common Sage Sequence to "list".
                label = "list" if isinstance(value, (list, tuple)) else tname
                return _bounded("%s of %d items" % (label, len(value)))
            except Exception:
                pass

        # Module: its dotted name, not its giant repr.
        if kind == "module":
            return _bounded(getattr(value, "__name__", "module"))

        # Function: its name + a callable marker.
        if kind == "function":
            return _bounded(getattr(value, "__name__", "function") + "()")

        # Plot: a fixed label (no point stringifying a Graphics).
        if kind == "plot":
            return "graphics"

        # Symbolic function f(x)=…: its compact "x |--> sin(x)/x" form (small).
        # Symbolic variable x: just "x". Scalars: their str(), capped.
        # Everything else: a capped str(); if str() is huge we still cap it,
        # and a structural-summary kind above already handled the big cases.
        return _bounded(_safe_str(value))
    except Exception as exc:  # noqa: BLE001 - inspection must never crash the op
        return "<unprintable: %s>" % type(exc).__name__


def _handle_symbols(req):
    """Return the live user-created symbol table.

    Diffs the namespace against the pre-user baseline so only user bindings
    appear; classifies and (cheaply, boundedly) summarizes each. Deleted names
    vanish (they're gone from NS); reassigned names re-classify/re-summarize from
    their current value (we read NS live). Sorted by name for a stable sidebar."""
    syms = []
    for name in sorted(NS.keys()):
        if name.startswith("__") and name.endswith("__"):
            continue
        value = NS[name]
        # User-created iff the name is new, OR it shadows a baseline name but is
        # now bound to a different object (the user reassigned it). `is` against
        # the retained baseline object is exact (no id() recycle hazard).
        _MISSING = _SYMBOL_BASELINE_MISS
        base_obj = _SYMBOL_BASELINE.get(name, _MISSING)
        if base_obj is not _MISSING and base_obj is value:
            continue
        try:
            kind = _symbol_kind(value)
        except Exception:
            kind = "unknown"
        summary = _symbol_summary(value, kind)
        syms.append({"name": name, "kind": kind, "summary": summary})
    return {"id": req.get("id"), "ok": True, "op": "symbols", "symbols": syms}


# ---------------------------------------------------------------------------
# Eval core: REPL-style "last expression yields a value".
# ---------------------------------------------------------------------------

def _eval_code(src):
    """Preparse `src`, exec it in NS, and if the final statement is an
    expression, return its value. Mirrors how the Sage REPL echoes results.

    Returns (has_value, value).
    """
    pp = preparse(src)
    tree = ast.parse(pp, mode="exec")
    if not tree.body:
        return (False, None)

    last = tree.body[-1]
    if isinstance(last, ast.Expr):
        # Exec all leading statements, then eval the trailing expression so we
        # capture its value.
        if len(tree.body) > 1:
            head = ast.Module(body=tree.body[:-1], type_ignores=[])
            exec(compile(head, "<casette>", "exec"), NS)
        expr = ast.Expression(last.value)
        value = eval(compile(expr, "<casette>", "eval"), NS)
        return (True, value)

    # Pure statement(s): run for side effects, no echoed value.
    exec(compile(tree, "<casette>", "exec"), NS)
    return (False, None)


@contextlib.contextmanager
def _capture():
    """Capture both Python-level stdout/stderr and OS-level fds 1/2.

    Yields (out_buf, err_buf) text buffers. We redirect the OS fds to a pipe
    each so that C/Cython code in Sage that writes straight to fd 1/2 is also
    captured and cannot reach the protocol stream.
    """
    out_buf = io.StringIO()
    err_buf = io.StringIO()

    # Pipes to catch raw fd-level writes.
    out_r, out_w = os.pipe()
    err_r, err_w = os.pipe()

    # Save the current fd 1/2 so we can restore them (these point at the
    # private protocol dups' originals — i.e. the terminal/parent — but during
    # capture nothing should reach them).
    saved_out_fd = os.dup(1)
    saved_err_fd = os.dup(2)

    os.dup2(out_w, 1)
    os.dup2(err_w, 2)
    os.close(out_w)
    os.close(err_w)

    try:
        with contextlib.redirect_stdout(out_buf), contextlib.redirect_stderr(err_buf):
            yield out_buf, err_buf
    finally:
        # Flush Python's view, then restore the real fds.
        sys.stdout.flush()
        sys.stderr.flush()
        os.dup2(saved_out_fd, 1)
        os.dup2(saved_err_fd, 2)
        os.close(saved_out_fd)
        os.close(saved_err_fd)

        # Drain whatever raw bytes hit the pipes and fold them in.
        for fd, buf in ((out_r, out_buf), (err_r, err_buf)):
            os.set_blocking(fd, False)
            chunks = []
            while True:
                try:
                    data = os.read(fd, 65536)
                except BlockingIOError:
                    break
                if not data:
                    break
                chunks.append(data)
            os.close(fd)
            if chunks:
                buf.write(b"".join(chunks).decode("utf-8", "replace"))


# ---------------------------------------------------------------------------
# Request handling.
# ---------------------------------------------------------------------------

def _collect_plot_artifacts(echoed_value, has_value):
    """Save artifacts for every plot produced by the just-finished eval.

    Sources, in call order:
      1. plots captured via `.show()` during the eval (the _SHOWN_PLOTS list),
      2. the echoed trailing-expression value, if it is itself a plot.
    De-duplicated by object identity so a plot that is both shown and echoed is
    saved exactly once. Never raises (per-format errors are structured inside
    _save_plot_artifact)."""
    seen_ids = set()
    ordered = []
    for p in _SHOWN_PLOTS:
        if id(p) not in seen_ids:
            seen_ids.add(id(p))
            ordered.append(p)
    if has_value and _is_plot(echoed_value) and id(echoed_value) not in seen_ids:
        seen_ids.add(id(echoed_value))
        ordered.append(echoed_value)

    artifacts = []
    for p in ordered:
        artifacts.extend(_save_plot_artifact(p))
    return artifacts


def _effective_digits(req):
    """The precision (decimal digits) for this request: a valid per-request
    `precision_digits` overrides the session default, else the session default.
    """
    d = req.get("precision_digits")
    if isinstance(d, int) and not isinstance(d, bool) and d > 0:
        return d
    return _PRECISION_DIGITS


def _handle_eval(req):
    rid = req.get("id")
    src = req.get("code", "")
    numeric = bool(req.get("numeric", False))
    digits = _effective_digits(req)

    # Reset the per-eval plot collector; the .show() hooks append into it.
    _SHOWN_PLOTS.clear()

    out_text = ""
    err_text = ""
    try:
        with _capture() as (out_buf, err_buf):
            has_value, value = _eval_code(src)
        out_text = _cap_captured_stream(out_buf.getvalue(), "stdout")
        err_text = _cap_captured_stream(err_buf.getvalue(), "stderr")
    except KeyboardInterrupt:
        # SIGINT from the parent: report a distinct `interrupted` envelope so
        # the parent's state machine can move running -> interrupted (vs error).
        return {
            "id": rid,
            "ok": False,
            "kind": "interrupted",
            "plain": "",
            "latex": None,
            "repr": "",
            "approx": None,
            "approx_digits": None,
            "exact": None,
            "primary_is_approx": False,
            "actions": [],
            "error": {
                "type": "KeyboardInterrupt",
                "message": "eval interrupted",
                "traceback": "",
            },
            "stdout": out_text,
            "stderr": err_text,
            "artifacts": [],
        }
    except BaseException as exc:  # noqa: BLE001 - we want everything user code raises
        # Capture buffers were populated up to the point of failure; recover
        # them if the context manager set them (best effort).
        tb = traceback.format_exc()
        # Cap a pathological error message / traceback too.
        msg, _ = _cap(str(exc), _MAX_PLAIN)
        tb_capped, _ = _cap(tb, _MAX_REPR)
        return {
            "id": rid,
            "ok": False,
            "kind": "error",
            "plain": msg,
            "latex": None,
            "repr": msg,
            "approx": None,
            "approx_digits": None,
            "exact": None,
            "primary_is_approx": False,
            "actions": ["copy_traceback"],
            "error": {
                "type": type(exc).__name__,
                "message": str(exc),
                "traceback": tb_capped,
            },
            "stdout": out_text,
            "stderr": err_text,
            "artifacts": [],
        }

    # Collect plot artifacts produced by this eval (via .show() and/or the
    # echoed value). Done AFTER capture is restored so save()'s own output
    # doesn't pollute the user's stdout buffer. Never raises.
    try:
        artifacts = _collect_plot_artifacts(value, has_value)
    except Exception as exc:  # pragma: no cover - defensive
        artifacts = [{"type": "image", "path": None,
                      "error": "artifact collection failed: %r" % (exc,)}]

    # The Sage/IPython REPL suppresses a `None` result: a bare `print(...)`,
    # an assignment, or any call that returns None echoes nothing. We do the
    # same so `print("hello")` reports value=False with its text in stdout.
    # A plot that was `.show()`n (not echoed) still carries its artifacts here.
    if has_value and value is not None:
        env = _build_envelope(value, artifacts=artifacts,
                              digits=digits, numeric=numeric)
    else:
        has_value = False
        env = {
            "kind": "plot" if artifacts else "none",
            "plain": "",
            "latex": None,
            "repr": "",
            "approx": None,
            "approx_digits": None,
            "exact": None,
            "primary_is_approx": False,
            "actions": list(_ACTIONS.get("plot", [])) if artifacts else [],
            "artifacts": artifacts,
            "truncated": False,
        }

    resp = {
        "id": rid,
        "ok": True,
        "stdout": out_text,
        "stderr": err_text,
        "value": has_value,
    }
    resp.update(env)
    return resp


def _handle_config(req):
    """Session-level configuration (V0.8). Currently: `precision_digits`, the
    default decimal precision for the envelope's `approx` field. Setting it
    persists for the session; subsequent evals use it until changed. A request
    with no recognized setting just reports the current config (a getter).

    Request:  {"id":..,"op":"config","precision_digits":20}
    Response: {"id":..,"ok":true,"op":"config","precision_digits":20}
    """
    global _PRECISION_DIGITS
    d = req.get("precision_digits")
    if d is not None:
        if not (isinstance(d, int) and not isinstance(d, bool) and d > 0):
            return {"id": req.get("id"), "ok": False, "op": "config",
                    "error": {"type": "ValueError",
                              "message": "precision_digits must be a positive integer"},
                    "precision_digits": _PRECISION_DIGITS}
        _PRECISION_DIGITS = d
    return {"id": req.get("id"), "ok": True, "op": "config",
            "precision_digits": _PRECISION_DIGITS}


def _handle(req):
    op = req.get("op")
    if op == "ping":
        return {"id": req.get("id"), "ok": True, "op": "ping", "pong": True}
    if op == "shutdown":
        return {"id": req.get("id"), "ok": True, "op": "shutdown"}
    if op == "symbols":
        return _handle_symbols(req)
    if op == "config":
        return _handle_config(req)
    # Default op is eval.
    return _handle_eval(req)


def main():
    # Report the worker's *real* pid (this Python process), which differs from
    # the `sage` bash-wrapper pid the parent sees as its Popen child. The parent
    # targets SIGINT (interrupt) at this pid; for a hard kill it still signals
    # the whole process group. (V0.2.)
    # V0.5: wrap Graphics.show / GraphicsArray.show so plots are captured as
    # artifacts instead of trying to open a GUI window in this headless worker.
    _install_show_hooks()

    _log("ready (Sage %s) pid=%d" % (version(), os.getpid()))  # noqa: F405
    _emit({"op": "ready", "ok": True, "pid": os.getpid()})

    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except json.JSONDecodeError as exc:
            _emit({
                "id": None,
                "ok": False,
                "kind": "error",
                "error": {"type": "ProtocolError",
                          "message": "invalid JSON request: %s" % exc},
                "stdout": "",
                "stderr": "",
                "artifacts": [],
            })
            continue

        resp = _handle(req)
        _emit(resp)

        if req.get("op") == "shutdown":
            break

    # Clean shutdown: remove this worker's session-scoped artifact dir. A hard
    # kill skips this, but the dir is pid+rand-namespaced under /tmp, so it never
    # collides and the OS reaps /tmp. (V0.5 lifetime policy.)
    _cleanup_session_dir()
    _log("exiting")


if __name__ == "__main__":
    main()
