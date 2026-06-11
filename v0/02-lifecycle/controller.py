#!/usr/bin/env python3
"""Casette session controller — V0.2 worker lifecycle, interrupts, restart.

This is the parent-side controller that owns the Sage worker process and proves
the app can stay in command when Sage misbehaves: long evals don't freeze the
parent, an in-flight eval can be interrupted or killed, the session can be
restarted from scratch, and an unexpected worker death is noticed and reported.

It is a deliberate prototype of V1.3's `SessionController` (Swift), so the shape
is meant to translate: one explicit state machine, one worker, non-blocking IO,
and a small command surface (`evaluate` / `interrupt` / `kill` / `restart`).

Runs under plain Python 3 (the parent app's runtime), NOT under Sage. It launches
the *canonical* worker — `v0/01-worker-protocol/worker.py` — via `sage -python`.

Design notes (the load-bearing decisions)
------------------------------------------
* **Responsiveness.** stdout is drained by a dedicated *reader thread* into a
  queue. The control thread never does a blocking `readline` on the worker, so a
  60-second eval never freezes the parent: state can be queried, an interrupt can
  be sent, the deadline can be enforced — all while the worker is busy.

* **Interrupt.** SIGINT is sent to the worker's *real* pid (from the ready
  banner), turning into a `KeyboardInterrupt` inside the worker's eval. This is
  prompt for Python-level loops. It is NOT reliable for C/Cython/GMP Sage calls
  (e.g. `factorial(10^8)`): the signal is deferred until the C call returns. The
  controller therefore *escalates* — if an interrupt isn't acknowledged within a
  grace window, it hard-kills. See PROBLEMS.md.

* **Hard kill.** SIGKILL to the whole *process group* (`os.killpg`), because
  `sage -python` is a bash wrapper that fork-execs the real worker as a child;
  killing only the Popen pid orphans the worker. (V0.1 lesson.)

* **Crash detection.** The reader thread sets an EOF flag when the worker's
  stdout closes. Both `evaluate` (waiting for a result) and an idle poll notice
  it and move to `crashed`.
"""

from __future__ import annotations

import enum
import json
import os
import queue
import signal
import subprocess
import threading
import time


HERE = os.path.dirname(os.path.abspath(__file__))
# One canonical worker, owned by V0.1 and extended in place for V0.2.
WORKER = os.path.normpath(os.path.join(HERE, "..", "01-worker-protocol", "worker.py"))
DEFAULT_SAGE = "/usr/local/bin/sage"


class State(enum.Enum):
    """The UI-facing kernel state machine (V0.2 exit criterion)."""

    IDLE = "idle"               # worker up, no eval in flight
    RUNNING = "running"         # an eval is in flight
    COMPLETED = "completed"     # last eval returned ok
    ERROR = "error"             # last eval raised (structured error)
    INTERRUPTED = "interrupted" # last eval was cancelled via SIGINT
    TIMED_OUT = "timed_out"     # last eval blew its deadline; worker killed
    CRASHED = "crashed"         # worker died unexpectedly
    RESTARTING = "restarting"   # a fresh worker is being brought up


class EvalOutcome:
    """Result of a (possibly failed/interrupted/killed) evaluate() call."""

    def __init__(self, state, response=None, elapsed=0.0, detail=""):
        self.state = state            # the terminal State for this eval
        self.response = response      # the worker's JSON envelope, or None
        self.elapsed = elapsed        # wall-clock seconds
        self.detail = detail

    def __repr__(self):
        return "EvalOutcome(state=%s, elapsed=%.2fs, detail=%r)" % (
            self.state.value, self.elapsed, self.detail)


class SessionController:
    """Owns one Sage worker and its lifecycle. Not thread-safe across callers;
    one control thread drives it (mirrors the app's main-actor ownership)."""

    def __init__(self, sage=DEFAULT_SAGE, worker=WORKER):
        self._sage = sage
        self._worker = worker
        self.proc = None
        self.real_pid = None        # worker's true pid (for SIGINT), from banner
        self.state = State.IDLE
        self.restarts = 0

        # Reader-thread plumbing.
        self._q = queue.Queue()     # parsed JSON objects from the worker
        self._eof = threading.Event()
        self._reader = None
        self._cancel = threading.Event()  # tripped to cancel the in-flight eval

    # -- lifecycle --------------------------------------------------------

    def start(self, ready_timeout=120):
        """Launch the worker and block until its ready banner (or fail).

        Each worker *generation* gets its own queue and EOF event, captured by
        that generation's reader thread. This is critical for restart: an old
        reader thread hitting EOF on the dead worker's pipe must NOT trip the new
        worker's EOF flag (a race that otherwise makes the fresh worker look
        crash-on-boot)."""
        self.proc = subprocess.Popen(
            [self._sage, "-python", self._worker],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,   # worker logs to a private fd; ignore
            text=True,
            bufsize=1,
            start_new_session=True,      # own process group -> killpg later
        )
        # Fresh per-generation plumbing.
        self._q = queue.Queue()
        self._eof = threading.Event()
        self._reader = threading.Thread(
            target=self._read_loop,
            args=(self.proc.stdout, self._q, self._eof),
            daemon=True)
        self._reader.start()

        banner = self._await({"op": "ready"}, timeout=ready_timeout)
        if banner is None:
            self.state = State.CRASHED
            raise RuntimeError("worker never became ready")
        self.real_pid = banner.get("pid")
        self.state = State.IDLE
        return banner

    @staticmethod
    def _read_loop(stdout, q, eof):
        """Drain one worker's stdout forever, parsing JSONL into *its* queue.
        Sets *its* EOF event when the pipe closes. Bound to a single generation
        via args so a stale reader can't disturb a newer worker."""
        try:
            for raw in stdout:
                line = raw.strip()
                if not line:
                    continue
                try:
                    q.put(json.loads(line))
                except json.JSONDecodeError:
                    # Non-JSON on the wire shouldn't happen (worker uses a
                    # private protocol fd), but never crash the reader.
                    continue
        finally:
            eof.set()

    def _await(self, match, timeout):
        """Pull objects off the queue until one matches `match` (a dict of
        key->value all of which must be present) or timeout/EOF. Returns the
        object or None."""
        deadline = time.time() + timeout
        while True:
            if self._eof.is_set() and self._q.empty():
                return None
            remaining = deadline - time.time()
            if remaining <= 0:
                return None
            try:
                obj = self._q.get(timeout=min(remaining, 0.2))
            except queue.Empty:
                continue
            if all(obj.get(k) == v for k, v in match.items()):
                return obj

    # -- evaluation -------------------------------------------------------
    #
    # Threading model (load-bearing): `evaluate` is the *sole* consumer of the
    # response queue. The reader thread is the sole producer. Another thread
    # (or the timeout machinery) influences an in-flight eval ONLY by sending a
    # signal via `interrupt()` / `request_cancel()` — it never reads the queue.
    # This avoids two threads racing to dequeue the worker's one response, which
    # is what the app's single-actor SessionController will also guarantee.

    def evaluate(self, code, rid=None, timeout=10.0, interrupt_grace=3.0,
                 cancel_event=None):
        """Run `code`, enforcing `timeout`. Returns an EvalOutcome and leaves
        `self.state` at the terminal state.

        While waiting we also watch `cancel_event` (and the internal one set by
        `interrupt()`): if it fires we SIGINT the worker and keep waiting up to
        `interrupt_grace` for the worker to acknowledge. If it never does (a
        C-level loop ignoring SIGINT), we hard-kill. Timeout follows the same
        escalation. Spec policy: brutal restart is acceptable."""
        if self.state in (State.CRASHED,):
            raise RuntimeError("worker is dead; restart() first")
        rid = rid or ("e%d" % int(time.time() * 1000))
        self._cancel = cancel_event or threading.Event()
        self.state = State.RUNNING
        t0 = time.time()

        try:
            self.proc.stdin.write(json.dumps({"id": rid, "code": code}) + "\n")
            self.proc.stdin.flush()
        except (BrokenPipeError, ValueError) as exc:
            self.state = State.CRASHED
            return EvalOutcome(State.CRASHED, elapsed=time.time() - t0,
                               detail="stdin closed: %s" % exc)

        deadline = t0 + timeout
        sigint_sent_at = None       # when we first SIGINT'd
        cause = None                # "cancel" or "timeout" once we escalate

        while True:
            # 1) crash?
            if self._eof.is_set() and self._q.empty():
                self.state = State.CRASHED
                try:
                    self.proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    pass
                return EvalOutcome(State.CRASHED, elapsed=time.time() - t0,
                                   detail="worker died mid-eval (EOF)")

            # 2) response?
            try:
                obj = self._q.get(timeout=0.05)
                if obj.get("id") == rid:
                    return self._finish(obj, t0, cause)
                continue  # stray/unrelated line; keep draining
            except queue.Empty:
                pass

            now = time.time()
            # 3) escalation triggers: explicit cancel, or deadline.
            if cause is None and self._cancel.is_set():
                cause = "cancel"
                self._send_sigint()
                sigint_sent_at = now
            elif cause is None and now >= deadline:
                cause = "timeout"
                self._send_sigint()
                sigint_sent_at = now

            # 4) SIGINT ignored past the grace window -> brutal kill.
            if sigint_sent_at is not None and (now - sigint_sent_at) >= interrupt_grace:
                self.kill()
                self.state = State.TIMED_OUT if cause == "timeout" else State.INTERRUPTED
                detail = ("deadline exceeded; SIGINT ignored, hard-killed"
                          if cause == "timeout"
                          else "cancel requested; SIGINT ignored, hard-killed")
                return EvalOutcome(self.state, elapsed=time.time() - t0,
                                   detail=detail)

    def _finish(self, resp, t0, cause):
        """A response arrived for our rid. Map worker envelope + cause -> state."""
        elapsed = time.time() - t0
        if resp.get("ok"):
            self.state = State.COMPLETED
            return EvalOutcome(State.COMPLETED, response=resp, elapsed=elapsed)
        if resp.get("kind") == "interrupted":
            if cause == "timeout":
                self.state = State.TIMED_OUT
                return EvalOutcome(State.TIMED_OUT, response=resp, elapsed=elapsed,
                                   detail="deadline exceeded; SIGINT honored")
            self.state = State.INTERRUPTED
            return EvalOutcome(State.INTERRUPTED, response=resp, elapsed=elapsed,
                               detail="cancel requested; SIGINT honored")
        self.state = State.ERROR
        return EvalOutcome(State.ERROR, response=resp, elapsed=elapsed,
                           detail=(resp.get("error") or {}).get("type", "error"))

    def _send_sigint(self):
        if self.real_pid is None:
            return
        try:
            os.kill(self.real_pid, signal.SIGINT)
        except ProcessLookupError:
            pass

    def request_cancel(self):
        """Ask the in-flight eval to cancel. Non-blocking: sets the cancel event
        the running `evaluate` is watching. The eval loop does the SIGINT +
        escalation. (This is what a UI 'Stop' button calls.)"""
        ev = getattr(self, "_cancel", None)
        if ev is not None:
            ev.set()

    # Backwards-compatible direct interrupt used by tests that drive evaluate on
    # a background thread: just trip the cancel event.
    def interrupt(self):
        self.request_cancel()

    def kill(self):
        """Hard-kill the whole process group (bash wrapper + real worker).
        After this the controller has no live worker; call restart()."""
        if self.proc is None:
            return
        try:
            os.killpg(os.getpgid(self.proc.pid), signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            self.proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            pass
        self._eof.set()

    def restart(self):
        """Tear down the current worker (if any) and bring up a fresh one with a
        brand-new namespace. Proves old state is gone (see harness)."""
        self.state = State.RESTARTING
        self.kill()
        self.real_pid = None
        self.restarts += 1
        return self.start()

    # -- introspection ----------------------------------------------------

    def poll_health(self):
        """Cheap idle-time crash check. If the worker died while idle, flip to
        CRASHED. Returns the current state."""
        if self.state in (State.CRASHED, State.RESTARTING):
            return self.state
        if self._eof.is_set() and (self.proc is None or self.proc.poll() is not None):
            self.state = State.CRASHED
        return self.state

    def returncode(self):
        return None if self.proc is None else self.proc.poll()

    # -- internals --------------------------------------------------------

    def shutdown(self):
        """Best-effort clean teardown (used by tests/atexit)."""
        if self.proc is None:
            return
        if self.proc.poll() is None:
            try:
                self.proc.stdin.write(json.dumps({"op": "shutdown"}) + "\n")
                self.proc.stdin.flush()
                self.proc.wait(timeout=3)
            except (BrokenPipeError, ValueError, subprocess.TimeoutExpired):
                self.kill()
        # Make sure nothing is left.
        if self.proc.poll() is None:
            self.kill()
