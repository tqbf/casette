## 2026-06-11 — V0.1: Sage worker protocol (the first real gate) — PASS

**Did.** Built and proved the Sage worker bridge under
`v0/01-worker-protocol/`. The first hard V0 gate is green: **18/18 checks**.

- `worker.py` (real app code, survives into V1) — `sage -python worker.py`.
  Reads JSONL requests on stdin, writes JSONL responses on stdout. One
  persistent Sage namespace (`exec("from sage.all import *", NS)`) reused for
  every eval. Runs user code through `sage.repl.preparse.preparse`, then uses
  `ast` to exec leading statements and `eval` the trailing expression for a
  REPL-style value echo. Envelope: `id, ok, kind, plain, latex, stdout,
  stderr, artifacts, value` + `error{type,message,traceback}` on failure.
  `kind` is a rough classifier (V0.3 refines it).
- `harness.py` (test scaffold, plain Python 3) — boots ONE worker, drives all
  spec test cases sequentially (proving namespace persistence), then kills it
  to prove death detection. Exit 0 iff all criteria pass. `--json` dumps each
  envelope.
- `README.md` — run instructions + the full exit-criteria evidence table.

**Exit criteria — all PASS (evidence in README):** Sage boots from parent;
multiple evals in one persistent namespace; assignment state survives
(`x=var("x")`→`factor(x^4-1)`, `A=matrix(...)`→`A.eigenvalues()`, `A.det()` even
after an exception); `1/0` → structured `ZeroDivisionError` with traceback;
`print("hello")` captured into `stdout` (`value:false`); raw `os.write(1,…)`
(the Cython hazard) also captured, framing intact; parent detects worker death.

**Learned / surprised.**
- **`sage -python` is a bash wrapper** that fork-execs the real Python worker
  as a *child*. SIGKILL to the Popen PID kills only the wrapper and orphans the
  worker, which keeps answering on the inherited stdout pipe. Fix:
  `start_new_session=True` + `os.killpg`. This bit me directly and is a
  must-carry into V0.2 lifecycle and V1.3 `SageKernel`. → PROBLEMS.md.
- **`contextlib.redirect_stdout` is not enough.** It only swaps the Python
  `sys.stdout` object; C/Cython writes to fd 1 sail past it. Had to also
  `os.dup2` fds 1/2 into pipes during eval and drain them. Protocol output goes
  to a *private dup'd fd* established before Sage even imports. → PROBLEMS.md.
- A bare `print(...)` returns `None`; my first cut echoed `plain:"None"`.
  Suppressing `None` results (like the REPL) fixed it.
- Sage 9.5 orders `factor(x^4-1)` as `(x^2 + 1)*(x + 1)*(x - 1)` — fine,
  just don't string-compare factor output against the spec's illustrative order.

**Next.** V0.2 — worker lifecycle: timeouts, interrupt/cancel, hard kill,
restart, crash detection, and the idle/running/…/crashed state machine. The
process-group kill pattern is already proven and ready to reuse.

---
