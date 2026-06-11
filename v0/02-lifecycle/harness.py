#!/usr/bin/env python3
"""Parent-side test harness for Casette worker lifecycle (V0.2).

Drives `SessionController` through every V0.2 exit criterion with the spec's
real, hostile test cases — and actually runs them (no untested claims):

  * `while True: pass`        -> interrupt a Python-level hot loop (SIGINT works)
  * `sleep(30)`               -> blow a timeout, escalate to kill
  * `factorial(10^8)`         -> interrupt a C-level GMP loop (SIGINT deferred)
  * `integrate(sin(x^x), x)`  -> a long symbolic attempt (interrupt/timeout)

Plus: responsiveness during a long eval, restart proving a fresh namespace,
crash detection both mid-eval and while idle, and the full state machine.

Runs under plain Python 3. Usage::

    python3 harness.py
    python3 harness.py --sage /path/to/sage
    python3 harness.py --json   # dump worker envelopes

Exit status is 0 iff every criterion passes. Each scenario rebuilds a worker so
a hard kill in one test doesn't poison the next.
"""

import argparse
import atexit
import json
import os
import signal
import subprocess
import sys
import threading
import time

from controller import SessionController, State


PASS, FAIL = "PASS", "FAIL"
results = []
SAGE = "/usr/local/bin/sage"
DUMP = False


def check(name, ok, detail=""):
    results.append((name, PASS if ok else FAIL))
    mark = "  ok " if ok else " FAIL"
    print(f"[{mark}] {name}" + (f"  — {detail}" if detail else ""))
    return ok


def show(outcome):
    if DUMP and outcome is not None and outcome.response is not None:
        print("    " + json.dumps(outcome.response))


def new_controller():
    c = SessionController(sage=SAGE)
    c.start()
    return c


# ---------------------------------------------------------------------------
# Scenarios.
# ---------------------------------------------------------------------------

def s_sanity():
    """Basic eval round-trips and the happy-path states still work."""
    c = new_controller()
    try:
        check("controller boots worker, state IDLE", c.state is State.IDLE,
              f"state={c.state.value}")
        check("controller learned worker real pid", isinstance(c.real_pid, int),
              f"real_pid={c.real_pid}")
        o = c.evaluate("2 + 2", timeout=10)
        show(o)
        check("eval 2+2 -> COMPLETED, plain=4",
              o.state is State.COMPLETED and o.response["plain"] == "4",
              f"state={o.state.value} plain={o.response['plain']!r}")
        o = c.evaluate("1/0", timeout=10)
        show(o)
        check("eval 1/0 -> ERROR (structured)",
              o.state is State.ERROR
              and o.response["error"]["type"] == "ZeroDivisionError",
              f"state={o.state.value}")
        # Worker survives the error and stays usable.
        o = c.evaluate("3 + 4", timeout=10)
        check("worker usable after error -> COMPLETED 7",
              o.state is State.COMPLETED and o.response["plain"] == "7",
              f"state={o.state.value}")
    finally:
        c.shutdown()


def s_responsiveness():
    """Parent stays responsive (can query state / send commands) while a long
    eval is in flight — proves the reader thread keeps the control thread free."""
    c = new_controller()
    try:
        # Kick off a 5s sleep on a background thread so this thread can poke the
        # controller meanwhile. (Mirrors the app: UI thread free during eval.)
        box = {}

        def run():
            box["o"] = c.evaluate("import time; time.sleep(5); 99",
                                  timeout=20)
        th = threading.Thread(target=run)
        t0 = time.time()
        th.start()

        # While it runs, repeatedly read state with low latency. If the parent
        # were blocked on a readline this loop would stall.
        samples = []
        for _ in range(8):
            t = time.time()
            st = c.state
            latency = time.time() - t
            samples.append((st, latency))
            time.sleep(0.25)
        running_seen = any(st is State.RUNNING for st, _ in samples)
        max_latency = max(l for _, l in samples)
        # We sampled within the first 2s; the eval needs 5s, so we MUST have
        # observed RUNNING while the worker was busy.
        elapsed_during_sampling = time.time() - t0
        check("parent observes RUNNING during a long eval",
              running_seen, f"saw running in {elapsed_during_sampling:.2f}s window")
        check("state queries stay low-latency during eval (<50ms)",
              max_latency < 0.05, f"max_latency={max_latency*1000:.1f}ms")

        th.join()
        o = box["o"]
        show(o)
        check("long eval eventually COMPLETED with its value",
              o.state is State.COMPLETED and o.response["plain"] == "99",
              f"state={o.state.value} elapsed={o.elapsed:.2f}s")
    finally:
        c.shutdown()


def s_interrupt_python_loop():
    """`while True: pass` — interrupt a Python-level hot loop. SIGINT should
    land promptly (bytecode boundaries) and yield an INTERRUPTED result."""
    c = new_controller()
    try:
        box = {}

        def run():
            box["o"] = c.evaluate("while True:\n    pass\n", timeout=30,
                                  interrupt_grace=5)
        th = threading.Thread(target=run)
        th.start()
        time.sleep(1.0)
        check("hot Python loop -> state RUNNING", c.state is State.RUNNING,
              f"state={c.state.value}")
        t = time.time()
        c.request_cancel()      # UI 'Stop': trips the cancel event
        th.join(timeout=10)
        dt = time.time() - t
        o = box["o"]
        show(o)
        check("SIGINT interrupts `while True: pass` promptly",
              o is not None and o.state is State.INTERRUPTED
              and "honored" in o.detail and dt < 5,
              f"state={(o.state.value if o else None)} ack={dt:.2f}s detail={(o.detail if o else '')!r}")
        # Worker is still alive and usable after a Python-level interrupt.
        o2 = c.evaluate("5 + 5", timeout=10)
        check("worker survives a Python-level interrupt (still evals)",
              o2.state is State.COMPLETED and o2.response["plain"] == "10",
              f"state={o2.state.value}")
    finally:
        c.shutdown()


def s_timeout_sleep():
    """`sleep(30)` — blow a short timeout. `sleep` is interruptible at the
    Python level, so the timeout's SIGINT escalation should be honored."""
    c = new_controller()
    try:
        o = c.evaluate("sleep(30)", timeout=2.0, interrupt_grace=5)
        show(o)
        check("sleep(30) with 2s timeout -> TIMED_OUT",
              o.state is State.TIMED_OUT,
              f"state={o.state.value} detail={o.detail!r} elapsed={o.elapsed:.2f}s")
        check("timeout fired near the deadline, not after 30s",
              o.elapsed < 12, f"elapsed={o.elapsed:.2f}s")
        # Whether SIGINT was honored or we hard-killed, the controller must be
        # in a sane state. If killed, restart; if interrupted, worker lives.
        if "honored" in o.detail:
            o2 = c.evaluate("1 + 2", timeout=10)
            check("after honored-SIGINT timeout, worker still usable",
                  o2.state is State.COMPLETED, f"state={o2.state.value}")
        else:
            c.restart()
            o2 = c.evaluate("1 + 2", timeout=10)
            check("after hard-kill timeout, restart -> worker usable",
                  o2.state is State.COMPLETED, f"state={o2.state.value}")
    finally:
        c.shutdown()


def s_factorial_C_loop():
    """`factorial(10^8)` — a genuinely hot C/GMP loop (>60s to run uninterrupted).

    THE honest finding: in the real worker, `from sage.all import *` installs
    cysignals' SIGINT handler, which wraps Sage C/Cython in sig_on()/sig_off()
    and longjmps out at an interrupt check — so SIGINT *promptly aborts* the
    mid-flight C computation (verified ~3s, not 60s+). So the timeout's SIGINT
    is HONORED here; the worker survives and reports `interrupted`."""
    c = new_controller()
    try:
        # Confirm it really doesn't finish on its own in our window: 2s timeout
        # vs >60s runtime. The deadline fires; SIGINT is sent; cysignals aborts.
        t0 = time.time()
        o = c.evaluate("factorial(10^8)", timeout=2.0, interrupt_grace=4)
        dt = time.time() - t0
        show(o)
        check("factorial(10^8) short timeout -> TIMED_OUT",
              o.state is State.TIMED_OUT,
              f"state={o.state.value} detail={o.detail!r}")
        check("SIGINT (via cysignals) aborts mid-C factorial — honored, no kill",
              "honored" in o.detail and dt < 7,
              f"detail={o.detail!r} elapsed={dt:.2f}s")
        # Because the interrupt was honored, the SAME worker is still alive.
        check("worker survived the C-loop interrupt (proc still running)",
              c.proc.poll() is None, f"poll={c.proc.poll()}")
        o2 = c.evaluate("2 ^ 10", timeout=10)
        check("worker usable after C-loop interrupt (2^10=1024)",
              o2.state is State.COMPLETED and o2.response["plain"] == "1024",
              f"state={o2.state.value}")
    finally:
        c.shutdown()


def s_hardkill_escalation():
    """The other half of the honest story: when SIGINT genuinely CANNOT stop the
    eval (user code ignores it / unwrapped C), the controller MUST escalate to a
    hard process-group kill. We force the case with `signal.SIG_IGN` + a hot
    loop. This is the spec's 'brutal restart is acceptable' guarantee."""
    c = new_controller()
    try:
        code = ("import signal\n"
                "signal.signal(signal.SIGINT, signal.SIG_IGN)\n"
                "while True:\n    pass\n")
        t0 = time.time()
        o = c.evaluate(code, timeout=1.5, interrupt_grace=2.0)
        dt = time.time() - t0
        show(o)
        check("SIGINT-ignoring runaway -> TIMED_OUT via hard kill",
              o.state is State.TIMED_OUT and "hard-killed" in o.detail,
              f"state={o.state.value} detail={o.detail!r}")
        check("hard kill stopped it (proc returncode = -SIGKILL)",
              c.returncode() == -signal.SIGKILL, f"returncode={c.returncode()}")
        check("escalation happened near deadline+grace, not hung forever",
              dt < 6, f"elapsed={dt:.2f}s")
        # Worker is dead; restart recovers.
        c.restart()
        o2 = c.evaluate("8 * 8", timeout=10)
        check("restart after hard-kill escalation -> worker usable (64)",
              o2.state is State.COMPLETED and o2.response["plain"] == "64",
              f"state={o2.state.value}")
    finally:
        c.shutdown()


def s_integrate_symbolic():
    """`integrate(sin(x^x), x)` — a long symbolic attempt. Characterize: does it
    finish, error, or hang? Whatever it does, our timeout must bound it."""
    c = new_controller()
    try:
        # Ensure x is a symbol in this fresh namespace.
        c.evaluate("x = var('x')", timeout=10)
        t0 = time.time()
        o = c.evaluate("integrate(sin(x^x), x)", timeout=8.0, interrupt_grace=3)
        dt = time.time() - t0
        show(o)
        terminal = o.state in (State.COMPLETED, State.ERROR,
                               State.INTERRUPTED, State.TIMED_OUT)
        check("integrate(sin(x^x), x) reaches a terminal state under timeout",
              terminal, f"state={o.state.value} elapsed={dt:.2f}s detail={o.detail!r}")
        check("symbolic attempt was bounded by the deadline",
              dt < 14, f"elapsed={dt:.2f}s")
        # Recover if it had to be killed.
        if o.state is State.TIMED_OUT and "hard-killed" in o.detail:
            c.restart()
        elif c.poll_health() is State.CRASHED:
            c.restart()
        o2 = c.evaluate("6 * 7", timeout=10)
        check("worker usable after the symbolic attempt",
              o2.state is State.COMPLETED and o2.response["plain"] == "42",
              f"state={o2.state.value}")
    finally:
        c.shutdown()


def s_restart_fresh_namespace():
    """Restart must give a fresh namespace — old state is gone."""
    c = new_controller()
    try:
        c.evaluate("secret = 1234567", timeout=10)
        o = c.evaluate("secret", timeout=10)
        check("state present before restart (secret=1234567)",
              o.state is State.COMPLETED and o.response["plain"] == "1234567",
              f"plain={o.response['plain']!r}")
        old_pid = c.real_pid
        c.restart()
        check("restart -> new worker pid (fresh process)",
              c.real_pid != old_pid and isinstance(c.real_pid, int),
              f"old={old_pid} new={c.real_pid}")
        check("restart leaves state IDLE", c.state is State.IDLE,
              f"state={c.state.value}, restarts={c.restarts}")
        o = c.evaluate("secret", timeout=10)
        show(o)
        check("old namespace is GONE after restart (NameError on `secret`)",
              o.state is State.ERROR and o.response["error"]["type"] == "NameError",
              f"state={o.state.value} err={(o.response.get('error') or {}).get('type')}")
    finally:
        c.shutdown()


def s_crash_mid_eval():
    """Worker dies mid-eval (external kill) -> controller reports CRASHED."""
    c = new_controller()
    try:
        box = {}

        def run():
            box["o"] = c.evaluate("import time; time.sleep(20)", timeout=30)
        th = threading.Thread(target=run)
        th.start()
        time.sleep(1.0)
        check("eval in flight -> RUNNING before crash", c.state is State.RUNNING,
              f"state={c.state.value}")
        # Simulate an unexpected crash: kill the process group out from under it.
        os.killpg(os.getpgid(c.proc.pid), signal.SIGKILL)
        th.join(timeout=15)
        o = box["o"]
        check("worker death mid-eval -> CRASHED",
              o is not None and o.state is State.CRASHED,
              f"state={(o.state.value if o else None)} detail={(o.detail if o else '')!r}")
        check("controller observes a non-None return code after crash",
              c.returncode() is not None, f"returncode={c.returncode()}")
        # And we can recover.
        c.restart()
        o2 = c.evaluate("1 + 1", timeout=10)
        check("restart after mid-eval crash -> usable", o2.state is State.COMPLETED,
              f"state={o2.state.value}")
    finally:
        c.shutdown()


def s_crash_while_idle():
    """Worker dies while idle -> poll_health() notices CRASHED."""
    c = new_controller()
    try:
        c.evaluate("1 + 1", timeout=10)  # back to IDLE/COMPLETED
        check("idle health is not CRASHED before kill",
              c.poll_health() is not State.CRASHED, f"state={c.state.value}")
        os.killpg(os.getpgid(c.proc.pid), signal.SIGKILL)
        # Give the reader thread time to see EOF.
        deadline = time.time() + 5
        while time.time() < deadline and c.poll_health() is not State.CRASHED:
            time.sleep(0.1)
        check("idle worker death detected by poll_health() -> CRASHED",
              c.poll_health() is State.CRASHED, f"state={c.state.value}")
    finally:
        c.shutdown()


SCENARIOS = [
    ("sanity / happy-path states", s_sanity),
    ("responsiveness during long eval", s_responsiveness),
    ("interrupt `while True: pass` (Python loop)", s_interrupt_python_loop),
    ("timeout `sleep(30)`", s_timeout_sleep),
    ("interrupt `factorial(10^8)` (C loop, SIGINT honored)", s_factorial_C_loop),
    ("hard-kill escalation (SIGINT ignored)", s_hardkill_escalation),
    ("`integrate(sin(x^x), x)` (long symbolic)", s_integrate_symbolic),
    ("restart -> fresh namespace", s_restart_fresh_namespace),
    ("crash detection mid-eval", s_crash_mid_eval),
    ("crash detection while idle", s_crash_while_idle),
]


def main():
    global SAGE, DUMP
    ap = argparse.ArgumentParser()
    ap.add_argument("--sage", default="/usr/local/bin/sage")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    SAGE = args.sage
    DUMP = args.json

    print(f"V0.2 lifecycle harness — sage={SAGE}\n")
    for title, fn in SCENARIOS:
        print(f"=== {title} ===")
        try:
            fn()
        except Exception as exc:  # a scenario blowing up is itself a failure
            import traceback
            traceback.print_exc()
            check(f"scenario '{title}' completed without harness error", False,
                  repr(exc))
        print()

    npass = sum(1 for _, s in results if s == PASS)
    nfail = sum(1 for _, s in results if s == FAIL)
    print(f"SUMMARY: {npass} passed, {nfail} failed, {len(results)} total")
    return 0 if nfail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
