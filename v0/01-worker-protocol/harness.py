#!/usr/bin/env python3
"""Parent-side test harness for the Casette Sage worker (V0.1).

Boots the worker once via `sage -python worker.py`, drives the spec's test cases
through it *sequentially in a single process* (proving namespace persistence),
checks each response, captures the actual response JSON as evidence, and finally
kills the worker to prove parent-side death detection.

Runs under plain Python 3 (the parent app's runtime), NOT under Sage. Usage::

    python3 harness.py
    python3 harness.py --sage /usr/local/bin/sage   # override Sage path
    python3 harness.py --json                        # dump full response JSON

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
WORKER = os.path.join(HERE, "worker.py")


class Worker:
    """Thin parent-side wrapper around the worker subprocess."""

    def __init__(self, sage):
        # `sage -python` is a *bash wrapper* that fork-execs the real Python
        # worker as a child. Killing the wrapper PID alone orphans the worker,
        # which keeps running on the inherited stdout pipe. So we put the whole
        # thing in its own process group (start_new_session=True) and later
        # signal the group, killing wrapper + worker together. The real app's
        # SageKernel must do the same. (V0.2 lesson, surfaced here.)
        self.proc = subprocess.Popen(
            [sage, "-python", WORKER],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            start_new_session=True,
        )

    def _readline(self, timeout=60):
        # Simple blocking readline; the worker is prompt and single-threaded so
        # a plain readline is fine for V0.1. (V0.2 adds real timeouts.)
        line = self.proc.stdout.readline()
        return line

    def await_ready(self):
        """Read lines until the worker emits its `ready` banner."""
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
        try:
            self.proc.stdin.write(json.dumps(req) + "\n")
            self.proc.stdin.flush()
        except (BrokenPipeError, ValueError) as exc:
            # Worker's stdin is gone -> it died. Surface as the same signal a
            # missing response gives, so callers detect death uniformly.
            raise RuntimeError("worker closed stdin (no response): %s" % exc)
        line = self._readline()
        if not line:
            raise RuntimeError("worker closed stdout (no response)")
        return json.loads(line)

    def is_alive(self):
        return self.proc.poll() is None

    def kill(self):
        try:
            self.proc.kill()
        except ProcessLookupError:
            pass
        self.proc.wait()


# ---------------------------------------------------------------------------
# Assertions / reporting.
# ---------------------------------------------------------------------------

PASS, FAIL = "PASS", "FAIL"
results = []   # (name, status, detail)


def check(name, ok, detail=""):
    results.append((name, PASS if ok else FAIL, detail))
    mark = "  ok " if ok else " FAIL"
    print(f"[{mark}] {name}" + (f"  — {detail}" if detail else ""))
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sage", default="/usr/local/bin/sage")
    ap.add_argument("--json", action="store_true", help="print full response JSON")
    args = ap.parse_args()

    print(f"Booting worker: {args.sage} -python {WORKER}\n")
    w = Worker(args.sage)
    ready = w.await_ready()
    check("Sage starts from a parent process", ready.get("ok") is True,
          "ready banner received")

    def show(resp):
        if args.json:
            print("    " + json.dumps(resp))

    # --- Spec test cases, run sequentially in ONE process. ----------------

    # 2 + 2
    r = w.request({"id": "t1", "code": "2 + 2"})
    show(r)
    check("eval 2 + 2 == 4",
          r["ok"] and r["plain"] == "4" and r["kind"] == "integer",
          f'plain={r["plain"]!r} kind={r["kind"]!r}')

    # x = var("x")   -- assignment, no echoed value
    r = w.request({"id": "t2", "code": 'x = var("x")'})
    show(r)
    check('x = var("x") is a statement (no value)',
          r["ok"] and r["value"] is False and r["kind"] == "none",
          f'value={r["value"]}')

    # factor(x^4 - 1)  -- proves preparser (^) AND that x persisted from t2
    r = w.request({"id": "t3", "code": "factor(x^4 - 1)"})
    show(r)
    factored_ok = r["ok"] and "(x - 1)" in r["plain"] and "(x + 1)" in r["plain"] \
        and "(x^2 + 1)" in r["plain"]
    check("factor(x^4 - 1) [preparser ^ + persisted x]",
          factored_ok, f'plain={r["plain"]!r}')
    check("factor result carries LaTeX",
          bool(r["latex"]) and "left" in r["latex"],
          f'latex={r["latex"]!r}')

    # integrate(sin(x)^3, x)
    r = w.request({"id": "t4", "code": "integrate(sin(x)^3, x)"})
    show(r)
    check("integrate(sin(x)^3, x)",
          r["ok"] and "cos(x)" in r["plain"] and r["kind"] == "symbolic",
          f'plain={r["plain"]!r}')

    # A = matrix([[1,2],[3,4]])  -- assignment
    r = w.request({"id": "t5", "code": "A = matrix([[1,2],[3,4]])"})
    show(r)
    check("A = matrix(...) is a statement",
          r["ok"] and r["value"] is False,
          f'value={r["value"]}')

    # A.eigenvalues()  -- proves A persisted
    r = w.request({"id": "t6", "code": "A.eigenvalues()"})
    show(r)
    check("A.eigenvalues() [persisted matrix A]",
          r["ok"] and r["kind"] == "list" and "?" in r["plain"],
          f'plain={r["plain"]!r} kind={r["kind"]!r}')

    # print("hello")  -- THE protocol-corruption hazard.
    r = w.request({"id": "t7", "code": 'print("hello")'})
    show(r)
    check('print("hello") captured in stdout (protocol intact)',
          r["ok"] and r["stdout"] == "hello\n" and r["value"] is False,
          f'stdout={r["stdout"]!r}')

    # Raw fd-level writes (the Cython hazard): os.write(1/2, ...) bypasses
    # Python's sys.stdout. Must still be captured, framing intact.
    r = w.request({"id": "t7b",
                   "code": "import os\nos.write(1, b'RAW1\\n')\n"
                           "os.write(2, b'RAW2\\n')\n42"})
    show(r)
    check("raw os.write(1/2) captured, framing intact",
          (r["ok"] and r["id"] == "t7b" and r["plain"] == "42"
           and "RAW1" in r["stdout"] and "RAW2" in r["stderr"]),
          f'stdout={r["stdout"]!r} stderr={r["stderr"]!r}')

    # 1 / 0  -- structured error.
    r = w.request({"id": "t8", "code": "1 / 0"})
    show(r)
    check("1 / 0 returns structured error",
          (r["ok"] is False and r["kind"] == "error"
           and r["error"]["type"] == "ZeroDivisionError"
           and "division by zero" in r["error"]["message"]
           and "Traceback" in r["error"]["traceback"]),
          f'error={r.get("error", {}).get("type")!r}: '
          f'{r.get("error", {}).get("message")!r}')

    # Worker still healthy after the exception?
    r = w.request({"id": "t9", "code": "1 + 1"})
    show(r)
    check("worker survives an exception (still evaluates)",
          r["ok"] and r["plain"] == "2",
          f'plain={r["plain"]!r}')

    # State STILL persists after the exception (x and A from earlier).
    r = w.request({"id": "t10", "code": "A.det()"})
    show(r)
    check("state persists across the whole session (A.det() == -2)",
          r["ok"] and r["plain"] == "-2",
          f'plain={r["plain"]!r}')

    # Print does not corrupt a following request's framing.
    r = w.request({"id": "t11", "code": '7 * 6'})
    show(r)
    check("framing intact after a print earlier in session",
          r["ok"] and r["id"] == "t11" and r["plain"] == "42",
          f'id={r["id"]!r} plain={r["plain"]!r}')

    # --- Worker death detection. ------------------------------------------
    check("worker alive before kill", w.is_alive())
    # Kill the whole process group (bash wrapper + real Python worker child).
    # Killing only w.proc.pid would orphan the worker on its inherited pipe.
    pgid = os.getpgid(w.proc.pid)
    os.killpg(pgid, signal.SIGKILL)
    time.sleep(0.3)  # let the OS tear down the pipe before we probe it
    # Now prove the parent detects EOF + exit.
    eof_detected = False
    try:
        resp = w.request({"id": "dead", "code": "1"})
        # If we somehow got a response, the worker is not dead — fail.
        eof_detected = False
    except RuntimeError as exc:
        eof_detected = "no response" in str(exc)
    w.proc.wait(timeout=10)
    rc = w.proc.returncode
    check("parent detects worker death (EOF on stdout)", eof_detected,
          f"caught EOF on write-after-kill")
    check("parent observes worker exit code", rc is not None,
          f"returncode={rc} (negative = killed by signal {-rc if rc and rc < 0 else rc})")
    check("worker no longer alive", not w.is_alive())

    # --- Summary. ----------------------------------------------------------
    print()
    npass = sum(1 for _, s, _ in results if s == PASS)
    nfail = sum(1 for _, s, _ in results if s == FAIL)
    print(f"SUMMARY: {npass} passed, {nfail} failed, {len(results)} total")
    return 0 if nfail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
