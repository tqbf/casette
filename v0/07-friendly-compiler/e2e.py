#!/usr/bin/env python3
"""V0.7 end-to-end driver: friendly input -> Sage -> real worker.

The third test layer. For each friendly input we:

  1. compile it with the Swift CLI (`sagecalc-compile --json`), getting the
     generated Sage *and* its `requiredVariables`;
  2. apply the VARIABLE POLICY exactly as V1.4 will — declare each required
     variable with `var('x')` in the session before evaluating (a prelude eval),
     then evaluate the generated Sage;
  3. assert the worker returns `ok:true` and a sensible `kind`
     (solve -> list, eigenvalues -> list, plot -> plot with artifacts, ...).

This proves the *whole* pipeline the app will run: compile-without-eval, show the
Sage, declare vars, eval. Runs under plain Python 3 (the app's runtime), boots the
ONE canonical worker (`../01-worker-protocol/worker.py`) once, persistent session.

    python3 e2e.py            # build CLI if needed, run, exit 0 iff all pass
    python3 e2e.py --json     # also dump each worker envelope
    python3 e2e.py --sage /usr/local/bin/sage

We declare each fresh variable in its OWN prelude so a redeclaration never clobbers
prior bindings unexpectedly; the worker session is persistent across cases, which
also proves declarations accumulate harmlessly.
"""

import argparse
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
WORKER = os.path.normpath(os.path.join(HERE, "..", "01-worker-protocol", "worker.py"))
CLI = os.path.join(HERE, ".build", "debug", "sagecalc-compile")


class Worker:
    def __init__(self, sage):
        self.proc = subprocess.Popen(
            [sage, "-python", WORKER],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, text=True, bufsize=1,
            start_new_session=True,
        )

    def await_ready(self):
        deadline = time.time() + 180
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
            raise RuntimeError("worker closed stdout")
        return json.loads(line)

    def eval(self, code, rid=None):
        rid = rid or ("e%d" % int(time.time() * 1e6))
        return self._send({"id": rid, "code": code})

    def shutdown(self):
        try:
            self.proc.stdin.write(json.dumps({"op": "shutdown"}) + "\n")
            self.proc.stdin.flush()
            self.proc.wait(timeout=5)
        except Exception:
            try:
                import signal
                os.killpg(os.getpgid(self.proc.pid), signal.SIGKILL)
            except Exception:
                pass


def compile_input(text):
    """Run the Swift CLI in --json mode. Returns the parsed result dict."""
    out = subprocess.run([CLI, "--json", text], capture_output=True, text=True)
    # success/bypass exit 0; error exit 2; ambiguous exit 3 — all print JSON.
    payload = out.stdout.strip() or out.stderr.strip()
    return json.loads(payload)


# (friendly input, expected worker kind(s), expects artifacts?)
# These are the spec's friendly forms — every one must round-trip to a healthy
# worker result. `expected_kinds` is a set; some forms can land in >1 kind.
CASES = [
    ("factor x^4 - 1",                        {"symbolic"},            False),
    ("expand (x + 1)^5",                      {"symbolic"},            False),
    ("simplify sin(x)^2 + cos(x)^2",          {"integer", "symbolic"}, False),
    ("solve x^2 + 5*x + 6 = 0",               {"list"},                False),
    ("solve x^2 + 5*x + 6 = 0 for x",         {"list"},                False),
    ("derivative sin(x^2)",                   {"symbolic"},            False),
    ("derivative sin(x^2) wrt x",             {"symbolic"},            False),
    ("integral x^2",                          {"symbolic"},            False),
    # A definite integral / limit comes back as a Sage SYMBOLIC-ring element
    # whose `plain` is the exact value (e.g. `1/8`, `1`) — kind `symbolic`, not a
    # Python rational. (Value correctness is asserted separately below.)
    ("integral x^2, x=0..1",                  {"symbolic", "rational", "real"},    False),
    ("double integral x*y, x=0..1, y=0..x",   {"symbolic", "rational", "real"},    False),
    ("limit sin(x)/x, x->0",                  {"symbolic", "integer", "rational", "real"}, False),
    ("taylor sin(x), x=0, order=7",           {"symbolic"},            False),
    ("plot sin(x), x=-pi..pi",                {"plot"},                True),
    ("matrix [[1,2],[3,4]]",                  {"matrix"},              False),
    ("eigenvalues [[1,2],[3,4]]",             {"list"},                False),
    ("rref [[1,2],[3,4]]",                    {"matrix"},              False),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sage", default="sage")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    if not os.path.exists(CLI):
        print("building sagecalc-compile ...", flush=True)
        subprocess.run(["swift", "build"], cwd=HERE, check=True)

    checks = []  # (name, ok, detail)

    def check(name, ok, detail=""):
        checks.append((name, ok, detail))
        mark = "PASS" if ok else "FAIL"
        print(f"  [{mark}] {name}" + (f"  -- {detail}" if detail else ""))

    w = Worker(args.sage)
    try:
        ready = w.await_ready()
        print(f"worker ready (pid {ready.get('pid')})\n")

        for text, expected_kinds, wants_artifacts in CASES:
            comp = compile_input(text)
            if comp.get("status") != "success":
                check(text, False, f"compile status={comp.get('status')}")
                continue
            sage = comp["sage"]
            req = comp.get("requiredVariables", [])

            # VARIABLE POLICY (exactly what V1.4 does): declare each required var.
            for v in req:
                pre = w.eval(f"var('{v}')")
                if not pre.get("ok"):
                    check(text, False, f"var('{v}') prelude failed")
                    break

            env = w.eval(sage)
            if args.json:
                print("    " + json.dumps(env))

            ok = bool(env.get("ok"))
            kind = env.get("kind")
            kind_ok = kind in expected_kinds
            arts = env.get("artifacts") or []
            art_ok = (len(arts) > 0) if wants_artifacts else True

            detail = f"sage=`{sage}` -> ok={ok} kind={kind}"
            if wants_artifacts:
                detail += f" artifacts={len(arts)}"
            check(text, ok and kind_ok and art_ok, detail)

        # Bonus: prove a BYPASS string also evaluates fine (raw Sage untouched).
        comp = compile_input("2+2")
        bypass_eval = w.eval(comp["sage"])
        check("bypass `2+2` evaluates",
              comp.get("status") == "bypass" and bypass_eval.get("ok") and bypass_eval.get("plain") == "4",
              f"status={comp.get('status')} plain={bypass_eval.get('plain')}")

        # Bonus: the double integral's numeric answer is correct (1/8).
        di = compile_input("double integral x*y, x=0..1, y=0..x")
        for v in di.get("requiredVariables", []):
            w.eval(f"var('{v}')")
        di_eval = w.eval(di["sage"])
        check("double integral value == 1/8",
              di_eval.get("ok") and di_eval.get("plain") == "1/8",
              f"plain={di_eval.get('plain')}")

        # Bonus: wire intact after everything (1+1 -> 2).
        tail = w.eval("1+1")
        check("wire intact after all evals", tail.get("ok") and tail.get("plain") == "2",
              f"plain={tail.get('plain')}")

    finally:
        w.shutdown()

    passed = sum(1 for _, ok, _ in checks if ok)
    total = len(checks)
    print(f"\n{passed}/{total} checks passed")
    sys.exit(0 if passed == total else 1)


if __name__ == "__main__":
    main()
