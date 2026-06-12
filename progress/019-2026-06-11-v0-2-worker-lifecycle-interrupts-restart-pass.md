## 2026-06-11 — V0.2: Worker lifecycle, interrupts & restart — PASS

**Did.** Built the parent-side `SessionController` and proved the app can stay in
command when Sage misbehaves. Under `v0/02-lifecycle/`. **35/35 checks**, stable
across repeated runs; no stray Sage processes left.

- `controller.py` (`SessionController`, prototype of V1.3's controller) — owns one
  worker + a **reader thread** draining stdout into a queue (parent never blocks),
  the eight-state machine (idle/running/completed/error/interrupted/timed_out/
  crashed/restarting), and the command surface `evaluate / request_cancel / kill /
  restart / poll_health`. `evaluate` enforces a timeout and escalates **SIGINT →
  hard process-group kill** if the worker won't yield.
- Extended the **one canonical worker** (`v0/01-worker-protocol/worker.py`, not a
  copy): it now reports its **real pid** in the ready banner (so the parent can
  SIGINT the actual worker, not the `sage` bash wrapper) and returns a distinct
  `kind:"interrupted"` envelope on `KeyboardInterrupt`. V0.1 harness still 18/18 —
  changes are backward-compatible.
- `harness.py` — runs every exit criterion against the spec's hostile cases for
  real. `README.md` — full evidence + the honest interrupt story.

**Exit criteria — all PASS (evidence in README):** parent stays responsive during
a 5s eval (state reads <50ms, max measured 0.0ms; RUNNING observed live);
`while True: pass` interrupted in 0.02s; `sleep(30)` timed out in 2.03s;
`factorial(10^8)` (runs >60s) aborted mid-C in ~2s by SIGINT and the worker
**survived**; a SIGINT-ignoring runaway hard-killed (rc -9) and recovered by
restart; restart yields a fresh namespace (`secret` → `NameError`); crash detected
both mid-eval and idle (rc -9); all eight states observed.

**Learned / surprised.**
- **cysignals is what makes Sage interruptible — and it owns SIGINT.** The worker's
  SIGINT handler is `cysignals.python_check_interrupt`, NOT the one I installed:
  `from sage.all import *` makes cysignals install its handler on top. cysignals
  wraps Sage C/Cython in `sig_on()/sig_off()` and longjmps out at an interrupt
  check, so **SIGINT promptly aborts mid-flight C computation** (`factorial(10^8)`
  interrupted at +3.00s vs >60s to run). My own handler is a harmless fallback.
- **The contradiction that taught it.** A standalone probe that installed a plain
  Python SIGINT handler *after* the Sage import (clobbering cysignals) deferred the
  interrupt **23s** — until the GMP call returned — because plain-Python handlers
  only run between bytecodes and a C call doesn't yield. Same code, different
  handler, 23s vs prompt. Don't overwrite cysignals' handler.
- **SIGINT is still not guaranteed** (unwrapped C, `SIG_IGN`, tight pure-C loop) —
  so the controller always escalates SIGINT → hard process-group kill. Proved both
  halves.
- **Restart had a sneaky race:** a stale reader thread hitting EOF on the dead
  worker's pipe tripped a *shared* EOF flag and made the fresh worker look
  crash-on-boot. Fix: each worker generation owns its own queue + EOF event,
  captured by that generation's reader thread.
- **Two threads draining one response queue is a bug.** First cut had `interrupt()`
  and `evaluate()` both reading the queue → the interrupt response got consumed by
  the wrong reader and `interrupt()` looked like it timed out. Fix: `evaluate` is
  the sole consumer; cancel/timeout only *signal*.
- `integrate(sin(x^x), x)` doesn't hang — Sage 9.5 returns it unevaluated (no
  closed form) in ~1.5s.

**Next.** V0.3 — result envelope / classification refinement. (Lifecycle + state
machine are now a clean base for V1.3's `SessionController`.)

---
