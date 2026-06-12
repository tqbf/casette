## Protocol stdout must use a *private dup'd fd*, and capture must redirect fd 1/2 (not just `sys.stdout`)

**Hazard (called out in the V0.1 spec).** If the worker writes protocol JSON to
the same stdout that user code prints to, `print("hello")` — or worse, a
Cython/C library writing straight to fd 1 — corrupts the JSONL stream and
desyncs the parser.

**Fix that works (`worker.py`).**
1. At startup, **before** importing Sage or running anything, dup the real
   stdout/stderr to private fds (`os.dup(1)`, `os.dup(2)`) and write *all*
   protocol output there. Nothing user code does can reach those fds by name.
2. During each eval, redirect **both** layers into capture buffers:
   - Python level: `contextlib.redirect_stdout/redirect_stderr` (catches
     `print`).
   - **OS level: `os.dup2(pipe_w, 1)` / `os.dup2(pipe_w, 2)`** (catches raw
     `os.write(1, …)` and Cython/C writes). Drain the pipes non-blocking after
     restoring the fds and fold the text into `stdout`/`stderr`.

`contextlib.redirect_stdout` alone is **not** enough — it only swaps the
Python `sys.stdout` object; C-level writes to fd 1 sail right past it. Verified
with `os.write(1, b"RAW1\n")`: captured into the envelope, framing intact.

---
