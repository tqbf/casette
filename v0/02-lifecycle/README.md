# V0.2 — Worker Lifecycle, Interrupts & Restart

**Status: PASS (35/35 checks, 2026-06-11).** Proves the parent stays in command
when Sage misbehaves: long evals don't freeze the parent, an in-flight eval can
be interrupted or killed, the session can be restarted from a clean slate, and an
unexpected worker death is noticed and reported. Built on the V0.1 worker.

## Files

| File | Role | Survives into app? |
| --- | --- | --- |
| `controller.py` | **`SessionController`** — the parent-side kernel controller. Owns one Sage worker, a reader thread, the state machine, and the `evaluate` / `request_cancel` / `kill` / `restart` surface. A prototype of V1.3's `SessionController`. | **Yes** (as a design — the app's is Swift). |
| `harness.py` | Parent-side test driver (plain Python 3). Runs every exit criterion against the spec's real, hostile test cases. | No (test scaffold). |
| `../01-worker-protocol/worker.py` | The **one canonical worker**, extended in place for V0.2: reports its real pid in the ready banner, and reports a distinct `interrupted` envelope on `KeyboardInterrupt`. | **Yes** — real app code. |

## Run it

```bash
cd v0/02-lifecycle
python3 harness.py            # all lifecycle scenarios
python3 harness.py --json     # also dump worker envelopes
python3 harness.py --sage /path/to/sage
```

Exit status is 0 iff every criterion passes. Verified against **SageMath 9.5** at
`/usr/local/bin/sage`. (The V0.1 protocol harness still passes 18/18 against the
extended worker — the changes are backward-compatible.)

## The state machine

`SessionController.state` is one of (V0.2 exit criterion):

```
idle · running · completed · error · interrupted · timed_out · crashed · restarting
```

Transitions: `idle → running` on `evaluate`; `running → {completed, error}` on a
worker response; `running → interrupted` on an honored cancel; `running →
timed_out` on a blown deadline (SIGINT honored *or* escalated to a kill);
`running → crashed` on EOF mid-eval; any → `crashed` via idle `poll_health()`;
`* → restarting → idle` via `restart()`.

## How it works (the load-bearing decisions)

1. **Responsiveness = a reader thread + a queue.** The worker's stdout is drained
   by a dedicated daemon thread that parses JSONL into a queue and sets an EOF
   event when the pipe closes. The control thread never blocks on a worker
   `readline`, so a 60-second eval never freezes the parent: state can be read,
   a cancel sent, the deadline enforced — all while the worker is busy.
   (Mirrors the app keeping the UI thread free during an eval.)

2. **One queue consumer.** `evaluate` is the *sole* consumer of the response
   queue; the reader thread is the sole producer. Cancellation/timeout influence
   an in-flight eval only by **sending a signal** (via a `threading.Event` the
   eval loop watches) — never by reading the queue. Two threads racing to dequeue
   the worker's single response was a real bug; this is the fix, and it's what
   the app's single-actor controller will also guarantee.

3. **Interrupt = SIGINT to the worker's *real* pid.** The worker reports its true
   pid in the ready banner (`{"op":"ready","pid":…}`) because `sage -python` is a
   bash wrapper whose Popen pid is *not* the worker. The controller `os.kill`s
   that real pid with SIGINT.

4. **Escalation: SIGINT → hard kill.** If the worker doesn't acknowledge the
   interrupt within a grace window, the controller hard-kills the whole **process
   group** (`os.killpg`, SIGKILL) — wrapper + worker together. (V0.1 lesson:
   killing only the Popen pid orphans the worker.) Spec policy: brutal restart is
   acceptable.

5. **Restart = fresh process, fresh namespace.** `restart()` kills the current
   worker and `start()`s a new one. **Each worker generation owns its own queue
   and EOF event** (captured by that generation's reader thread) — otherwise a
   stale reader hitting EOF on the dead pipe trips the *new* worker's EOF flag and
   makes it look crash-on-boot. (This was a real restart bug; see PROBLEMS.md.)

6. **Crash detection.** The reader thread's EOF event is checked both while
   `evaluate` waits (→ `crashed` mid-eval) and by `poll_health()` when idle
   (→ `crashed` while idle).

## The honest interrupt story (this is the important finding)

**Does SIGINT reach mid-computation Sage? Does it abort C-level loops?**

**Yes — promptly — in the real worker, because of cysignals.** When the worker
runs `from sage.all import *`, **cysignals installs its own SIGINT handler**
(`cysignals.python_check_interrupt`), overriding the plain Python handler the
worker set. cysignals wraps Sage's C/Cython in `sig_on()/sig_off()` and longjmps
out at the next interrupt check, so SIGINT **aborts a mid-flight C/GMP computation
like `factorial(10^8)`** — verified interrupted at **+3.00s** against a run that
takes **>60s** uninterrupted.

This contradicts the naive expectation (and a standalone probe where a
hand-installed Python SIGINT handler — set *after* the Sage import, clobbering
cysignals — deferred the interrupt **23s**, until the GMP call returned). The
lesson: *cysignals is what makes Sage interruptible; don't overwrite its handler,
and don't assume plain-Python signal semantics.*

**But do not assume SIGINT always lands.** Sage code not wrapped in
`sig_on/sig_off`, or user code that ignores SIGINT (`signal.SIG_IGN`), or a tight
pure-C loop that never reaches a check, will swallow it. The controller proves
both halves:

- `factorial(10^8)` (timeout 2s) → SIGINT **honored** via cysignals → `timed_out`,
  worker **survives**, still usable.
- `signal.SIG_IGN` + `while True: pass` → SIGINT **ignored** → escalated to a
  **hard process-group kill** (returncode `-9`) → `timed_out`, recovered by
  `restart()`.

## Exit criteria — evidence (all executed by `harness.py`)

| Criterion | Result | Evidence |
| --- | --- | --- |
| Parent stays responsive during long evals | PASS | During a 5s eval, `state` reads stay <50ms latency (measured max **0.0ms**) and `RUNNING` is observed live; reads happen off a reader thread. |
| Current eval can be interrupted | PASS | `while True: pass` → `request_cancel()` → `interrupted` in **0.02s**, worker survives. `factorial(10^8)` → SIGINT (cysignals) → aborted mid-C in **~2s**, worker survives. |
| Current eval can be killed | PASS | SIGINT-ignoring runaway → hard process-group kill, `returncode=-9`. |
| Eval timeout | PASS | `sleep(30)` with a 2s deadline → `timed_out` in **2.03s** (not 30s). |
| Worker restarts after a hard kill | PASS | After a hard-kill, `restart()` brings up a fresh worker (new pid) that evaluates correctly. |
| Restart gives a fresh namespace | PASS | `secret=1234567` set, then `restart()`, then `secret` → `NameError` (old state gone). |
| Crash detection (mid-eval) | PASS | Process group killed during a 20s sleep → `crashed`, `returncode=-9`, recovered by restart. |
| Crash detection (idle) | PASS | Idle worker killed → `poll_health()` flips to `crashed`. |
| State machine (idle/running/completed/error/interrupted/timed_out/crashed/restarting) | PASS | All eight states observed across the scenarios. |

### Test-case outcomes (the spec's hostile cases, as actually run)

| Case | Outcome | Notes |
| --- | --- | --- |
| `while True: pass` | **interrupted in 0.02s** | Python-level loop; SIGINT prompt. |
| `sleep(30)` | **timed_out in 2.03s** | `sleep` is interruptible; SIGINT honored at the deadline. |
| `factorial(10^8)` | **interrupted/timed_out in ~2s** | Runs >60s uninterrupted; cysignals SIGINT aborts it mid-C. Worker survives. |
| `integrate(sin(x^x), x)` | **completed in ~1.5s** | Sage 9.5 finds no closed form and returns the unevaluated `integrate(sin(x^x), x)` (kind `symbolic`) — fast, not a hang. |

## Gotchas carried to V0.3 / V1.3

- **Don't clobber cysignals' SIGINT handler.** It is what makes Sage C code
  interruptible. The worker's own handler is a harmless fallback cysignals
  supersedes.
- **SIGINT is not guaranteed** — always have the SIGINT → hard-kill escalation.
- **Per-generation reader plumbing on restart** — a stale reader's EOF must not
  poison the new worker.
- **Target SIGINT at the worker's real pid** (from the banner), but **hard-kill
  the process group** (`os.killpg`).
