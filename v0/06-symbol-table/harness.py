#!/usr/bin/env python3
"""Parent-side test harness for the Casette live symbol table (V0.6).

Boots the *canonical* worker once (`sage -python ../01-worker-protocol/worker.py`),
drives the spec's test cases through it in a single persistent session, and
exercises the new `symbols` op end-to-end:

  * the spec sequence (x = var("x"); A = matrix(...); f(x) = sin(x)/x;
    n = 104729; del n),
  * junk filtering (no symbols before user code; no Sage builtins leak),
  * deletion (del n removes n),
  * reassignment (n = 5 then n = "hello" re-classifies + re-summarizes),
  * bounded summaries on a HUGE matrix + a million-item list, TIMED, to prove
    inspection never triggers a big computation / huge output,
  * graceful degradation when a value's __repr__/__str__ raises.

Runs under plain Python 3 (the parent app's runtime), NOT under Sage. Usage::

    python3 harness.py
    python3 harness.py --sage /usr/local/bin/sage   # override Sage path
    python3 harness.py --json                        # dump symbols responses

Exit status is 0 iff every exit criterion passes.
"""

import argparse
import json
import os
import subprocess
import sys
import time


HERE = os.path.dirname(os.path.abspath(__file__))
# We test the ONE canonical worker (owned by V0.1, extended in place for V0.6),
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

    def _send(self, obj):
        self.proc.stdin.write(json.dumps(obj) + "\n")
        self.proc.stdin.flush()
        line = self.proc.stdout.readline()
        if not line:
            raise RuntimeError("worker closed stdout (no response)")
        return json.loads(line)

    def eval(self, code, rid=None):
        rid = rid or ("e%d" % int(time.time() * 1e6))
        return self._send({"id": rid, "code": code})

    def symbols(self, rid=None):
        rid = rid or ("s%d" % int(time.time() * 1e6))
        return self._send({"id": rid, "op": "symbols"})

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


# The symbol-table kind vocabulary: the V0.3 result kinds plus the four
# symbol-table-only kinds the worker adds.
RESULT_KINDS = {
    "integer", "rational", "real", "complex", "symbolic", "relation",
    "list", "matrix", "plot", "text", "boolean", "none", "error", "unknown",
}
SYMBOL_KINDS = RESULT_KINDS | {
    "symbolic variable", "symbolic function", "module", "function",
}

MAX_SUMMARY = 200  # mirrors worker._MAX_SUMMARY; summaries must be <= cap + " …"


def by_name(resp):
    """Index a symbols response by symbol name -> entry dict."""
    return {s["name"]: s for s in resp.get("symbols", [])}


def names(resp):
    return {s["name"] for s in resp.get("symbols", [])}


def shape_ok(resp):
    """Every symbols response must carry the documented shape."""
    if resp.get("op") != "symbols":
        return False, "op != symbols"
    if resp.get("ok") is not True:
        return False, "ok != true"
    if not isinstance(resp.get("symbols"), list):
        return False, "symbols not a list"
    for s in resp["symbols"]:
        if set(s.keys()) != {"name", "kind", "summary"}:
            return False, f"entry keys {sorted(s.keys())} != name/kind/summary"
        if not isinstance(s["name"], str):
            return False, "name not a string"
        if s["kind"] not in SYMBOL_KINDS:
            return False, f"kind {s['kind']!r} not in vocabulary"
        if not isinstance(s["summary"], str):
            return False, "summary not a string"
        if len(s["summary"]) > MAX_SUMMARY + 4:  # + " …" slack
            return False, f"summary len {len(s['summary'])} exceeds cap"
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

    def show(resp, label=""):
        if args.json:
            print(f"    {label}: " + json.dumps(resp.get("symbols", resp)))

    try:
        # -- 1. Pristine namespace: NO symbols before any user code. ----------
        r0 = w.symbols("s-empty")
        ok, why = shape_ok(r0)
        check("symbols response has the documented shape (empty case)", ok, why)
        check("No symbols before user code (Sage junk fully filtered)",
              r0["symbols"] == [], f"got {names(r0)}")
        show(r0, "pristine")

        # Assert specific Sage builtins / imports / plumbing never leak.
        junk_probe = {"x", "pi", "var", "matrix", "factor", "SR", "ZZ", "QQ",
                      "sqrt", "sin", "I", "e", "__builtins__", "NS",
                      "preparse", "latex"}
        leaked = names(r0) & junk_probe
        check("No Sage builtins/imports/worker plumbing leak", not leaked,
              f"leaked {leaked}" if leaked else "none of the probe names present")

        # -- 2. The spec sequence. --------------------------------------------
        w.eval('x = var("x")', "c-x")
        w.eval('A = matrix([[1,2],[3,4]])', "c-A")
        w.eval('f(x) = sin(x)/x', "c-f")
        w.eval('n = 104729', "c-n")

        r1 = w.symbols("s-spec")
        ok, why = shape_ok(r1)
        check("symbols response has the documented shape (spec case)", ok, why)
        show(r1, "after spec")
        idx = by_name(r1)

        check("User-created symbols appear (x, A, f, n)",
              {"x", "A", "f", "n"}.issubset(names(r1)),
              f"got {sorted(names(r1))}")

        # x -> symbolic variable, summary "x"
        check("x is a symbolic variable, summary 'x'",
              idx.get("x", {}).get("kind") == "symbolic variable"
              and idx.get("x", {}).get("summary") == "x",
              f"got {idx.get('x')}")

        # A -> matrix, summary "2×2 over Integer Ring"
        check("A is a matrix, summary '2×2 over Integer Ring'",
              idx.get("A", {}).get("kind") == "matrix"
              and idx.get("A", {}).get("summary") == "2×2 over Integer Ring",
              f"got {idx.get('A')}")

        # f(x) = sin(x)/x -> symbolic function (preparsed to a callable expr)
        check("f(x)=sin(x)/x is a symbolic function",
              idx.get("f", {}).get("kind") == "symbolic function",
              f"got {idx.get('f')}")
        check("f summary is its compact callable form (x |--> sin(x)/x)",
              "|-->" in idx.get("f", {}).get("summary", ""),
              f"got {idx.get('f', {}).get('summary')!r}")

        # n = 104729 -> integer, summary "104729"
        check("n is an integer, summary '104729'",
              idx.get("n", {}).get("kind") == "integer"
              and idx.get("n", {}).get("summary") == "104729",
              f"got {idx.get('n')}")

        # -- 3. Deletion: del n removes n. ------------------------------------
        w.eval("del n", "c-del")
        r2 = w.symbols("s-del")
        check("Deleted symbol disappears (del n)",
              "n" not in names(r2) and {"x", "A", "f"}.issubset(names(r2)),
              f"got {sorted(names(r2))}")
        show(r2, "after del n")

        # -- 4. Reassignment re-classifies + re-summarizes. -------------------
        w.eval("n = 5", "c-n5")
        ra = by_name(w.symbols("s-n5"))
        check("Reassigned n=5 is integer, summary '5'",
              ra.get("n", {}).get("kind") == "integer"
              and ra.get("n", {}).get("summary") == "5",
              f"got {ra.get('n')}")
        w.eval('n = "hello"', "c-nh")
        rb = by_name(w.symbols("s-nh"))
        check("Reassigned n='hello' updates kind->text, summary 'hello'",
              rb.get("n", {}).get("kind") == "text"
              and rb.get("n", {}).get("summary") == "hello",
              f"got {rb.get('n')}")

        # -- 5. SAFETY: huge objects, bounded summaries, TIMED. ---------------
        # Build a massive matrix and a million-item list, then time the symbols
        # op to prove inspection never triggers a big computation / huge output.
        w.eval("M = matrix(ZZ, 200, 200, range(40000))", "c-M")
        w.eval("big_list = list(range(10**6))", "c-big")

        t0 = time.time()
        rh = w.symbols("s-huge")
        dt = time.time() - t0
        hidx = by_name(rh)

        check("Huge-object symbols op returns quickly (< 0.5s)", dt < 0.5,
              f"took {dt*1000:.1f} ms")
        print(f"       [timing] symbols op over M(200×200)+big_list(10^6): "
              f"{dt*1000:.2f} ms")

        check("M summary is bounded & structural ('200×200 over Integer Ring')",
              hidx.get("M", {}).get("kind") == "matrix"
              and hidx.get("M", {}).get("summary") == "200×200 over Integer Ring",
              f"got {hidx.get('M')}")
        check("big_list summary is bounded ('list of 1000000 items'), not 7.9 MB",
              hidx.get("big_list", {}).get("summary") == "list of 1000000 items",
              f"got {hidx.get('big_list')}")
        # Hard bound: no summary in the whole response exceeds the cap.
        longest = max((len(s["summary"]) for s in rh["symbols"]), default=0)
        check("Every summary is bounded (<= cap)", longest <= MAX_SUMMARY + 4,
              f"longest summary = {longest} chars")

        # -- 6. Graceful degradation: a value whose __repr__/__str__ raises. --
        w.eval(
            "class Boom:\n"
            "    def __repr__(self): raise RuntimeError('boom repr')\n"
            "    def __str__(self): raise RuntimeError('boom str')\n"
            "boom = Boom()",
            "c-boom")
        rboom = w.symbols("s-boom")
        ok, why = shape_ok(rboom)
        check("symbols op survives a raising __repr__/__str__ (no crash)",
              ok, why)
        bidx = by_name(rboom)
        check("Raising-repr object degrades to a placeholder summary",
              "boom" in bidx
              and bidx["boom"]["summary"].startswith("<unprintable:"),
              f"got {bidx.get('boom')}")
        show(rboom, "after Boom")
        # The class binding `Boom` itself is a user symbol too (a type).
        check("User-defined class Boom appears as a symbol",
              "Boom" in names(rboom),
              f"got {sorted(names(rboom))}")

        # -- 7. User import + def surface as module / function. ---------------
        w.eval("import numpy", "c-np")
        w.eval("def g(y):\n    return y + 1", "c-g")
        rmod = by_name(w.symbols("s-mod"))
        check("User `import numpy` surfaces as a module",
              rmod.get("numpy", {}).get("kind") == "module"
              and rmod.get("numpy", {}).get("summary") == "numpy",
              f"got {rmod.get('numpy')}")
        check("User `def g` surfaces as a function (summary 'g()')",
              rmod.get("g", {}).get("kind") == "function"
              and rmod.get("g", {}).get("summary") == "g()",
              f"got {rmod.get('g')}")

        # -- 8. Wire still intact after all that (eval works). ----------------
        r11 = w.eval("1 + 1", "c-11")
        check("Wire intact after symbols ops (1+1 -> 2)",
              r11.get("ok") is True and r11.get("plain") == "2",
              f"got plain={r11.get('plain')!r}")

    finally:
        w.shutdown()

    # ------------------------------------------------------------------ summary
    n_fail = sum(1 for _, st, _ in results if st == FAIL)
    n_pass = sum(1 for _, st, _ in results if st == PASS)
    print(f"\n{n_pass}/{n_pass + n_fail} checks passed.")
    if n_fail:
        print("FAILURES:")
        for name, st, detail in results:
            if st == FAIL:
                print(f"  - {name}  ({detail})")
    sys.exit(1 if n_fail else 0)


if __name__ == "__main__":
    main()
