#!/usr/bin/env python3
"""Parent-side test harness for the Casette exact/numeric display policy (V0.8).

Boots the *canonical* worker once (`sage -python ../01-worker-protocol/worker.py`),
drives every spec test case plus the exactness trap cases through it in one
persistent session, and asserts the V0.8 contract:

  * `exact`           — true for integer/rational/exact-symbolic, false for an
                        inherently approximate real/complex/inexact-symbolic,
                        null where exactness isn't a scalar property.
  * `primary_is_approx` — does the "≈" belong on the PRIMARY value (the result
                        already IS a float / force-numeric) or the secondary?
  * `approx` / `approx_digits` — the decimal approximation + its precision.
  * configurable precision — the `config` op sets a session default; a
                        per-request `precision_digits` overrides it.
  * force-numeric (`numeric:true`) — primary becomes the numeric value WITHOUT
                        polluting the session (stored vars stay exact).
  * NO global float coercion — exact in, exact out across many kinds; stored
                        high-precision reals keep their RealField precision.

It also proves the spec's *desired display* is DERIVABLE from one envelope with
no further worker round-trip: from `1/3 + 1/5` -> "8/15" + "≈ 0.5333333333".

Runs under plain Python 3 (the parent app's runtime), NOT under Sage. Usage::

    python3 harness.py
    python3 harness.py --sage /usr/local/bin/sage   # override Sage path
    python3 harness.py --json                        # dump full envelopes

Exit status is 0 iff every exit criterion passes.
"""

import argparse
import json
import os
import signal
import subprocess
import sys
import time


HERE = os.path.dirname(os.path.abspath(__file__))
# We test the ONE canonical worker (owned by V0.1, extended in place for V0.8),
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

    def request(self, req):
        if "id" not in req:
            req["id"] = "r%d" % int(time.time() * 1e6)
        self.proc.stdin.write(json.dumps(req) + "\n")
        self.proc.stdin.flush()
        line = self.proc.stdout.readline()
        if not line:
            raise RuntimeError("worker closed stdout (no response)")
        return json.loads(line)

    def eval(self, code, **kw):
        req = {"code": code}
        req.update(kw)
        return self.request(req)

    def config(self, **kw):
        req = {"op": "config"}
        req.update(kw)
        return self.request(req)

    def shutdown(self):
        try:
            self.proc.stdin.write(json.dumps({"op": "shutdown"}) + "\n")
            self.proc.stdin.flush()
            self.proc.wait(timeout=5)
        except Exception:
            try:
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


V08_FIELDS = ("kind", "plain", "latex", "repr", "approx", "approx_digits",
              "exact", "primary_is_approx", "actions", "artifacts", "truncated")


def shape_ok(r):
    for f in V08_FIELDS:
        if f not in r:
            return False, f"missing field {f!r}"
    if r["exact"] not in (True, False, None):
        return False, f"exact not tri-state: {r['exact']!r}"
    if not isinstance(r["primary_is_approx"], bool):
        return False, "primary_is_approx not bool"
    return True, ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sage", default="/usr/local/bin/sage")
    ap.add_argument("--json", action="store_true", help="dump full envelopes")
    args = ap.parse_args()

    w = Worker(args.sage)
    banner = w.await_ready()
    check("worker boots & reports pid", bool(banner.get("pid")),
          f"pid={banner.get('pid')}")

    dump = {}

    # =====================================================================
    # PART 1 — Spec test cases + the exactness traps. Default precision (10).
    # Each row: (code, expected_kind, expected_exact, expected_primary_is_approx,
    #            approx_required, note)
    # =====================================================================
    SPEC = [
        # The spec's six cases:
        ("1/3 + 1/5",           "rational", True,  False, True,
         "exact rational; approx secondary -> '8/15' + '≈ 0.533…'"),
        ("sqrt(2)",             "symbolic", True,  False, True,
         "exact SYMBOLIC (Symbolic Ring is_exact()==False, but it IS exact)"),
        ("N(sqrt(2), digits=50)", "real",   False, True,  True,
         "already approximate; primary IS the 50-digit number"),
        ("pi",                  "symbolic", True,  False, True,
         "exact symbolic constant"),
        ("sin(1)",              "symbolic", True,  False, True,
         "TRAP: Sage keeps sin(1) symbolic & EXACT; not coerced to a float"),
        ("sin(pi/3)",           "symbolic", True,  False, True,
         "exact (auto-simplifies to 1/2*sqrt(3)); approx available"),
        # The extra trap cases the spec calls out:
        ("2.5",                 "real",     False, True,  True,
         "input float literal -> Real, approximate by nature"),
        ("ZZ(104729)",          "integer",  True,  False, False,
         "exact integer; no approx (already its exact value)"),
        ("3 + 4*I",             "complex",  False, True,  True,
         "Gaussian element; complex floats are approximate-by-nature"),
        # Bonus exactness discriminators:
        ("2.5 + sqrt(2)",       "symbolic", False, True,  True,
         "INEXACT symbolic: contains a float atom -> exact:false"),
        ("sqrt(2) + pi",        "symbolic", True,  False, True,
         "exact symbolic sum (no inexact atoms)"),
    ]

    print("\n--- PART 1: spec cases + exactness traps (precision=10) ---")
    for code, ekind, eexact, eprimary, need_approx, note in SPEC:
        r = w.eval(code)
        dump[code] = r
        ok_shape, why = shape_ok(r)
        check(f"shape: {code}", ok_shape, why)
        check(f"kind: {code} -> {ekind}", r["kind"] == ekind,
              f"got {r['kind']}")
        check(f"exact: {code} -> {eexact}  ({note})", r["exact"] == eexact,
              f"got exact={r['exact']!r}")
        check(f"primary_is_approx: {code} -> {eprimary}",
              r["primary_is_approx"] == eprimary,
              f"got {r['primary_is_approx']!r}")
        if need_approx:
            check(f"approx present: {code}", r["approx"] is not None,
                  f"approx={r['approx']!r}")
            check(f"approx_digits=10: {code}", r["approx_digits"] == 10,
                  f"got {r['approx_digits']!r}")
        else:
            check(f"approx null (exact, no scalar approx): {code}",
                  r["approx"] is None, f"approx={r['approx']!r}")

    # =====================================================================
    # PART 2 — The spec's desired display is DERIVABLE from ONE envelope,
    # with NO further worker round-trip.
    # =====================================================================
    print("\n--- PART 2: derive the spec's desired display from one envelope ---")
    env = dump["1/3 + 1/5"]

    def render(e):
        """A pure renderer (what the UI does): exact primary + '≈' secondary,
        or, if the primary already IS an approximation, '≈' on the primary."""
        lines = []
        if e["primary_is_approx"]:
            lines.append("≈ " + e["plain"])
        else:
            lines.append(e["plain"])               # exact primary
            if e["approx"] is not None:
                lines.append("≈ " + e["approx"])   # secondary
        return "\n".join(lines)

    rendered = render(env)
    expected_display = "8/15\n≈ 0.5333333333"
    check("spec display derivable from envelope (no round-trip)",
          rendered == expected_display,
          f"rendered={rendered!r}")
    # And the primary IS the exact form, the secondary IS the approximation:
    check("primary == exact '8/15'", env["plain"] == "8/15", env["plain"])
    check("secondary == '0.5333333333'", env["approx"] == "0.5333333333",
          env["approx"])

    # An N(...) result renders with '≈' on the PRIMARY (no secondary):
    n50 = dump["N(sqrt(2), digits=50)"]
    check("N(...) renders '≈' on primary",
          render(n50).startswith("≈ 1.41"), render(n50))

    # =====================================================================
    # PART 3 — Configurable precision (session default + per-request override).
    # =====================================================================
    print("\n--- PART 3: configurable precision ---")
    # Read current config (getter).
    cfg = w.config()
    check("config getter returns current precision",
          cfg.get("precision_digits") == 10, str(cfg))

    # Change session default to 20.
    cfg = w.config(precision_digits=20)
    check("config sets precision_digits=20",
          cfg.get("ok") and cfg.get("precision_digits") == 20, str(cfg))
    r = w.eval("1/3 + 1/5")
    check("8/15 now approximates to 20 digits",
          r["approx"] == "0.53333333333333333333" and r["approx_digits"] == 20,
          f"approx={r['approx']!r} digits={r['approx_digits']}")

    # Per-request override beats the session default (request=6, session=20).
    r = w.eval("1/3 + 1/5", precision_digits=6)
    check("per-request precision_digits=6 overrides session",
          r["approx"] == "0.533333" and r["approx_digits"] == 6,
          f"approx={r['approx']!r} digits={r['approx_digits']}")
    # The override does NOT change the session default:
    r = w.eval("1/3 + 1/5")
    check("per-request override does not change session default (still 20)",
          r["approx_digits"] == 20, f"digits={r['approx_digits']}")

    # Invalid precision is rejected, session unchanged.
    bad = w.config(precision_digits=0)
    check("config rejects non-positive precision",
          bad.get("ok") is False and bad.get("precision_digits") == 20,
          str(bad))

    # Reset to default 10 for the remaining parts.
    w.config(precision_digits=10)

    # A precision request HIGHER than a concrete real can hold must NOT raise
    # (PROBLEMS.md: `.n(bits)` raises if asked for more than the object holds).
    r = w.eval("3 + 4*I", precision_digits=40)
    check("high precision on a 53-bit complex doesn't raise (clamped)",
          r["ok"] and r["approx"] is not None, f"approx={r['approx']!r}")

    # =====================================================================
    # PART 4 — Force-numeric mode WITHOUT polluting the session.
    # =====================================================================
    print("\n--- PART 4: force-numeric mode + namespace isolation ---")
    # Store y = 1/3 exactly.
    w.eval("y = 1/3")
    # Force-numeric on y: primary becomes the decimal, exact form preserved.
    r = w.eval("y", numeric=True)
    dump["y (numeric:true)"] = r
    check("numeric:true makes primary the decimal",
          r["plain"].startswith("0.3333333333") and r["primary_is_approx"] is True,
          f"plain={r['plain']!r} primary_is_approx={r['primary_is_approx']}")
    check("numeric:true preserves the exact form in exact_value",
          r.get("exact_value") == "1/3", f"exact_value={r.get('exact_value')!r}")
    check("numeric:true secondary approx is null (primary already numeric)",
          r["approx"] is None, f"approx={r['approx']!r}")

    # The NEXT normal request must be exact again — session not polluted.
    r = w.eval("y")
    check("next normal eval of y is EXACT again",
          r["plain"] == "1/3" and r["kind"] == "rational" and r["exact"] is True,
          f"plain={r['plain']!r} kind={r['kind']} exact={r['exact']}")

    # And the underlying stored variable is STILL exactly 1/3 in the namespace
    # (prove via parent / type, not just str): a Rational, not a float.
    r = w.eval("parent(y)")
    check("stored y's parent is the exact Rational Field",
          r["plain"] == "Rational Field", f"parent(y)={r['plain']!r}")
    r = w.eval("type(y).__name__")
    check("stored y is a Rational object (not a float)",
          "Rational" in r["plain"], f"type={r['plain']!r}")

    # Per-request precision also applies in numeric mode.
    r = w.eval("y", numeric=True, precision_digits=5)
    check("numeric:true honors per-request precision",
          r["plain"] == "0.33333", f"plain={r['plain']!r}")

    # Force-numeric on an exact symbolic constant.
    r = w.eval("sqrt(2)", numeric=True, precision_digits=10)
    check("numeric:true on sqrt(2) -> decimal primary, exact_value preserved",
          r["plain"].startswith("1.414213562")
          and r.get("exact_value") == "sqrt(2)"
          and r["primary_is_approx"] is True,
          f"plain={r['plain']!r} exact_value={r.get('exact_value')!r}")

    # =====================================================================
    # PART 5 — NO global float coercion: exact in -> exact out across kinds,
    # and a stored high-precision real keeps its RealField precision untouched
    # by approximation requests.
    # =====================================================================
    print("\n--- PART 5: no global float coercion ---")
    EXACT_IN_OUT = [
        ("factor(x^4 - 1)", "(x^2 + 1)", "symbolic"),   # stays symbolic/exact
        ("2^100", "1267650600228229401496703205376", "integer"),
        ("1/7", "1/7", "rational"),
        ("matrix([[1,2],[3,4]])", "[1 2]", "matrix"),
    ]
    # x is predefined by Sage, but declare to be safe.
    w.eval("x = var('x')")
    for code, needle, ekind in EXACT_IN_OUT:
        r = w.eval(code)
        check(f"exact in -> exact out: {code}",
              needle in r["plain"] and r["kind"] == ekind,
              f"kind={r['kind']} plain={r['plain'][:40]!r}")

    # Integers/matrices are exact:true / null appropriately, never floats.
    r = w.eval("2^100")
    check("2^100 is exact:true and approx:null (already exact)",
          r["exact"] is True and r["approx"] is None,
          f"exact={r['exact']} approx={r['approx']!r}")
    r = w.eval("matrix([[1,2],[3,4]])")
    check("matrix exact is null (not a scalar exactness property)",
          r["exact"] is None, f"exact={r['exact']!r}")

    # Stored high-precision real: its RealField precision is UNTOUCHED by an
    # approximation request at lower precision.
    w.eval("hp = N(sqrt(2), digits=50)")
    r = w.eval("hp.prec()")
    check("stored hp has 170-bit RealField precision", r["plain"] == "170",
          f"prec={r['plain']!r}")
    # Ask for a LOW-precision approx of hp — must not mutate hp.
    w.eval("hp", numeric=True, precision_digits=5)
    r = w.eval("hp.prec()")
    check("hp precision UNCHANGED after a low-precision numeric request",
          r["plain"] == "170", f"prec after={r['plain']!r}")
    r = w.eval("hp")
    check("hp still shows its full 50-digit value (not downcast)",
          r["plain"].startswith("1.41421356237309504880"),
          f"hp={r['plain'][:30]!r}")

    # =====================================================================
    # PART 6 — Wire still intact after all of the above.
    # =====================================================================
    print("\n--- PART 6: wire integrity ---")
    r = w.eval("1 + 1")
    check("wire intact: 1+1 -> 2 exact", r["plain"] == "2" and r["exact"] is True,
          f"plain={r['plain']!r}")

    w.shutdown()

    if args.json:
        print("\n=== ENVELOPES ===")
        for k, v in dump.items():
            print(f"\n# {k}")
            print(json.dumps(v, ensure_ascii=False, indent=2))

    # ----- summary -----
    n = len(results)
    npass = sum(1 for _, s, _ in results if s == PASS)
    print(f"\n{'='*60}\nV0.8 exact/numeric: {npass}/{n} checks passed")
    if npass != n:
        print("FAILURES:")
        for name, s, detail in results:
            if s == FAIL:
                print(f"  - {name}  ({detail})")
        return 1
    print("ALL PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
