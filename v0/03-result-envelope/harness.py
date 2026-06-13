#!/usr/bin/env python3
"""Parent-side test harness for the Casette result envelope (V0.3).

Boots the *canonical* worker once (`sage -python ../01-worker-protocol/worker.py`),
drives the spec's test cases through it in a single persistent session, and
asserts that each result has a STABLE `kind` and a sane envelope (plain present,
latex where it should be, repr always present, approx per the documented policy,
actions populated per kind, large outputs capped with a truncation flag, unknown
objects degraded to repr rather than failed).

Runs under plain Python 3 (the parent app's runtime), NOT under Sage. Usage::

    python3 harness.py
    python3 harness.py --sage /usr/local/bin/sage   # override Sage path
    python3 harness.py --json                        # dump full envelopes

Exit status is 0 iff every exit criterion passes.
"""

import argparse
import json
import os
import subprocess
import sys
import time


HERE = os.path.dirname(os.path.abspath(__file__))
# We test the ONE canonical worker (owned by V0.1, extended in place for V0.3),
# not a copy. Single source of truth.
WORKER = os.path.normpath(os.path.join(HERE, "..", "01-worker-protocol", "worker.py"))


class Worker:
    """Thin parent-side wrapper around the worker subprocess."""

    def __init__(self, sage):
        # `sage -python` is a bash wrapper that fork-execs the real worker as a
        # child; own process group so a later kill takes the whole tree (V0.1).
        self.proc = subprocess.Popen(
            [sage, "-python", WORKER],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            bufsize=1,
            start_new_session=True,
        )

    def await_ready(self):
        deadline = time.time() + 120
        while time.time() < deadline:
            line = self.proc.stdout.readline()
            if not line:
                raise RuntimeError("worker died before ready")
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if obj.get("op") == "ready":
                return obj
        raise RuntimeError("worker never became ready")

    def eval(self, code, rid=None):
        rid = rid or ("e%d" % int(time.time() * 1e6))
        self.proc.stdin.write(json.dumps({"id": rid, "code": code}) + "\n")
        self.proc.stdin.flush()
        line = self.proc.stdout.readline()
        if not line:
            raise RuntimeError("worker closed stdout (no response)")
        return json.loads(line)

    def shutdown(self):
        try:
            self.proc.stdin.write(json.dumps({"op": "shutdown"}) + "\n")
            self.proc.stdin.flush()
            self.proc.wait(timeout=5)
        except Exception:
            try:
                import signal
                os.killpg(os.getpgid(self.proc.pid), signal.SIGKILL)
            except ProcessLookupError:
                pass


# ---------------------------------------------------------------------------
# Assertions / reporting.
# ---------------------------------------------------------------------------

PASS, FAIL = "PASS", "FAIL"
results = []


def check(name, ok, detail=""):
    results.append((name, PASS if ok else FAIL, detail))
    mark = "  ok " if ok else " FAIL"
    print(f"[{mark}] {name}" + (f"  — {detail}" if detail else ""))
    return ok


# The fixed kind set the app renders against.
KINDS = {
    "integer", "rational", "real", "complex", "symbolic", "relation",
    "list", "matrix", "plot", "text", "boolean", "none", "error", "unknown",
}

ENVELOPE_FIELDS = ("kind", "plain", "latex", "repr", "approx", "actions",
                   "artifacts", "truncated")


def envelope_shape_ok(r):
    """Every value-bearing envelope must carry the full field set with sane
    types — this is the contract V0.4+/V1 build against."""
    for f in ENVELOPE_FIELDS:
        if f not in r:
            return False, f"missing field {f!r}"
    if r["kind"] not in KINDS:
        return False, f"kind {r['kind']!r} not in fixed set"
    if not isinstance(r["plain"], str):
        return False, "plain not a string"
    if not isinstance(r["repr"], str):
        return False, "repr not a string"
    if r["latex"] is not None and not isinstance(r["latex"], str):
        return False, "latex neither str nor null"
    if r["approx"] is not None and not isinstance(r["approx"], str):
        return False, "approx neither str nor null"
    if not isinstance(r["actions"], list):
        return False, "actions not a list"
    if not isinstance(r["truncated"], bool):
        return False, "truncated not a bool"
    return True, ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sage", default="/usr/local/bin/sage")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    print(f"Booting worker: {args.sage} -python {WORKER}\n")
    w = Worker(args.sage)
    ready = w.await_ready()
    check("Sage worker boots from parent", ready.get("ok") is True)

    def show(r):
        if args.json:
            print("    " + json.dumps(r))

    # Sage 9.5 predefines `x`, but be explicit about what we rely on: var it.
    w.eval('x = var("x")', "setup-x")

    # -- The spec's V0.3 test cases, each with its EXPECTED stable kind. --------
    # (code, expected_kind, expect_latex, expect_approx_nonnull)
    spec_cases = [
        ("ZZ(104729)",                       "integer",  True,  False),
        ("1/3 + 1/5",                        "rational", True,  True),
        ("sqrt(2)",                          "symbolic", True,  True),
        ("N(sqrt(2), digits=50)",            "real",     True,  True),
        ("sin(pi/3)",                        "symbolic", True,  True),
        ("x^2 + 5*x + 6",                    "symbolic", True,  False),
        ("x^2 + 5*x + 6 == 0",               "relation", True,  False),
        ("solve(x^2 + 5*x + 6 == 0, x)",     "list",     True,  False),
        ("matrix([[1,2],[3,4]])",            "matrix",   True,  False),
        ("matrix([[1,2],[3,4]]).rref()",     "matrix",   True,  False),
    ]
    # Plus the extra kinds the spec asks us to exercise.
    extra_cases = [
        ("3 + 4*I",                          "complex",  True,  True),   # complex
        ("plot(sin(x), (x,-pi,pi))",         "plot",     None,  False),  # plot
        ("Permutation([2,1,3])",             "unknown",  None,  False),  # unknown
    ]

    for code, want_kind, want_latex, want_approx in spec_cases + extra_cases:
        r = w.eval(code)
        show(r)
        shape_ok, why = envelope_shape_ok(r)
        check(f"[{code}] envelope shape complete & typed", shape_ok, why)
        check(f"[{code}] stable kind == {want_kind!r}",
              r.get("kind") == want_kind, f"got {r.get('kind')!r}")
        check(f"[{code}] has plain output",
              isinstance(r.get("plain"), str) and len(r["plain"]) > 0,
              f"plain={r.get('plain')!r}")
        check(f"[{code}] has repr (degrade target)",
              isinstance(r.get("repr"), str) and len(r["repr"]) > 0,
              f"repr={r.get('repr')!r}")
        if want_latex is True:
            check(f"[{code}] math result carries LaTeX",
                  bool(r.get("latex")), f"latex={r.get('latex')!r}")
        if want_approx is True:
            check(f"[{code}] numeric approx present",
                  bool(r.get("approx")), f"approx={r.get('approx')!r}")
        elif want_approx is False:
            # We assert approx is null where it makes no sense (free vars,
            # matrices, lists, relations, plots, exact integers).
            check(f"[{code}] approx null where not meaningful",
                  r.get("approx") is None, f"approx={r.get('approx')!r}")
        check(f"[{code}] actions populated per kind (UI-driving metadata)",
              isinstance(r.get("actions"), list)
              and (len(r["actions"]) > 0 or want_kind == "boolean"),
              f"actions={r.get('actions')!r}")

    r = w.eval("matrix([[1,2],[3,4]])")
    check("exact matrix offers RDF conversion but not SVD",
          "change_ring_RDF" in r.get("actions", [])
          and "svd" not in r.get("actions", []),
          f"actions={r.get('actions')!r}")
    r = w.eval("matrix(RDF, [[1,2],[3,4]])")
    check("RDF matrix offers SVD",
          "svd" in r.get("actions", []),
          f"actions={r.get('actions')!r}")
    r = w.eval("matrix(CDF, [[1,2],[3,4]])")
    check("CDF matrix offers SVD",
          "svd" in r.get("actions", []),
          f"actions={r.get('actions')!r}")
    r = w.eval("__casette_svd_labeled(matrix(RDF, [[1,2],[3,4]]).SVD())")
    check("SVD helper produces labeled plain text",
          r.get("kind") == "list"
          and all(label in r.get("plain", "") for label in ("U =", "S =", "V =")),
          f"kind={r.get('kind')!r} plain={r.get('plain')!r}")
    check("SVD helper produces labeled LaTeX",
          all(label in r.get("latex", "") for label in ("U =", "S =", "V =")),
          f"latex={r.get('latex')!r}")

    # -- Unknown-object degradation: classify as unknown, plain==repr-ish,
    #    NEVER an error. (Permutation above already covers it; assert explicitly
    #    that ok is true and it didn't fail.) -----------------------------------
    r = w.eval("Permutation([2,1,3])")
    check("unknown object degrades to repr, not failure",
          r.get("ok") is True and r.get("kind") == "unknown"
          and bool(r.get("repr")),
          f"ok={r.get('ok')} kind={r.get('kind')!r}")

    # -- text kind via print (captured to stdout; the value itself is none) ----
    r = w.eval('print("hello tape")')
    show(r)
    check("print(...) -> kind none, text captured in stdout",
          r.get("ok") and r.get("kind") == "none"
          and r.get("stdout") == "hello tape\n",
          f"kind={r.get('kind')!r} stdout={r.get('stdout')!r}")
    # An actual string value -> kind text.
    r = w.eval('"a literal string"')
    show(r)
    check('a string value -> kind "text"',
          r.get("ok") and r.get("kind") == "text",
          f"kind={r.get('kind')!r}")

    # -- error kind: 1/0 returns a structured error envelope, ok false --------
    r = w.eval("1/0")
    show(r)
    check("1/0 -> structured error envelope (ok false, kind error)",
          r.get("ok") is False and r.get("kind") == "error"
          and r.get("error", {}).get("type") == "ZeroDivisionError"
          and bool(r.get("plain")),
          f"errtype={r.get('error', {}).get('type')!r}")

    # -- Large outputs capped/summarized with an explicit truncation flag. -----
    r = w.eval("list(range(10^6))")
    show({k: r[k] for k in ("kind", "truncated", "truncation") if k in r})
    big_list_ok = (r.get("ok") and r.get("kind") == "list"
                   and r.get("truncated") is True
                   and len(r.get("plain", "")) < 20000
                   and isinstance(r.get("truncation"), dict)
                   and r["truncation"].get("plain_len", 0) > 1_000_000)
    check("list(range(10^6)) capped with truncation flag + policy",
          big_list_ok,
          f"truncated={r.get('truncated')} plainlen={len(r.get('plain',''))} "
          f"orig={r.get('truncation', {}).get('plain_len')}")

    r = w.eval("factorial(10^5)")
    big_int_ok = (r.get("ok") and r.get("kind") == "integer"
                  and r.get("truncated") is True
                  and len(r.get("plain", "")) < 20000
                  and r.get("truncation", {}).get("plain_len", 0) > 100000)
    check("factorial(10^5) (huge integer) capped with truncation flag",
          big_int_ok,
          f"truncated={r.get('truncated')} plainlen={len(r.get('plain',''))} "
          f"orig={r.get('truncation', {}).get('plain_len')}")

    # -- Worker still healthy after all that (no desync from big/odd output). --
    r = w.eval("6 * 7")
    check("worker healthy after big-output + error cases",
          r.get("ok") and r.get("plain") == "42" and r.get("kind") == "integer",
          f"plain={r.get('plain')!r}")

    w.shutdown()

    print()
    npass = sum(1 for _, s, _ in results if s == PASS)
    nfail = sum(1 for _, s, _ in results if s == FAIL)
    print(f"SUMMARY: {npass} passed, {nfail} failed, {len(results)} total")
    return 0 if nfail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
