# V0.1 — Sage Worker Protocol

**Status: PASS (18/18 checks, 2026-06-11).** Proves Casette can boot Sage from a
parent process, drive it over a JSONL protocol, keep namespace state across
evals, and get structured responses — without user code ever corrupting the
wire.

## Files

| File | Role | Survives into app? |
| --- | --- | --- |
| `worker.py` | The Sage worker. Reads JSONL requests on stdin, writes JSONL responses on stdout. Run as `sage -python worker.py`. | **Yes** — this is real app code. |
| `harness.py` | Parent-side test driver (plain Python 3). Boots one worker, runs all spec test cases sequentially, kills it, checks every exit criterion. | No (test scaffold). |

## Run it

```bash
cd v0/01-worker-protocol
python3 harness.py            # boots `sage -python worker.py`, runs all checks
python3 harness.py --json     # also dumps each full response envelope
python3 harness.py --sage /path/to/sage   # override Sage binary
```

Exit status is 0 iff every exit criterion passes. Verified against **SageMath
9.5** at `/usr/local/bin/sage`.

## Protocol

Line-delimited JSON. One request object per line in, one response object per
line out. On startup the worker emits a banner: `{"op":"ready","ok":true}`.

**Request** (default op is eval):

```json
{"id": "req-1", "code": "factor(x^4 - 1)"}
```

Other ops: `{"op":"ping"}` → `{"ok":true,"pong":true}`,
`{"op":"shutdown"}` → graceful exit.

**Response (value):**

```json
{
  "id": "req-1", "ok": true, "kind": "symbolic",
  "plain": "(x^2 + 1)*(x + 1)*(x - 1)",
  "latex": "{\\left(x^{2} + 1\\right)} {\\left(x + 1\\right)} {\\left(x - 1\\right)}",
  "stdout": "", "stderr": "", "artifacts": [], "value": true
}
```

**Response (statement / no echoed value):** `kind:"none"`, `value:false`,
`plain:""`. Assignments and any expression returning `None` (e.g. a bare
`print(...)`) report this, matching REPL behavior.

**Response (error):**

```json
{
  "id": "req-8", "ok": false, "kind": "error",
  "error": {"type": "ZeroDivisionError",
            "message": "rational division by zero",
            "traceback": "Traceback (most recent call last): ..."},
  "stdout": "", "stderr": "", "artifacts": []
}
```

### Envelope fields (V0.1)

`id`, `ok`, `kind`, `plain`, `latex` (nullable), `stdout`, `stderr`,
`artifacts` (always `[]` in V0.1 — V0.5 fills it), `value` (bool: did the eval
produce an echoed value), and `error` `{type,message,traceback}` when `ok` is
false. `kind` is a **rough** classification (`integer`, `rational`, `real`,
`complex`, `symbolic`, `relation`, `matrix`, `list`, `plot`, `text`, `boolean`,
`none`, `error`, `unknown`) — V0.3 refines it.

## How it works (the load-bearing decisions)

1. **Namespace persistence.** One dict `NS`, seeded with
   `exec("from sage.all import *", NS)`, reused for every request. Assignments
   in one eval are visible in the next.

2. **Preparser.** User code runs through `sage.repl.preparse.preparse` before
   `exec`, so `x^4` and `factor(x^4 - 1)` work as written.

3. **Value vs statement.** The preparsed source is parsed with `ast`. If the
   final node is an expression, leading statements are `exec`'d and the final
   expression is `eval`'d to capture its value (REPL-style echo). Pure
   statements run for side effects with no echoed value. A `None` result is
   suppressed (so `print(...)` echoes nothing).

4. **Protocol can't be corrupted by user output (the critical hazard).** At
   startup the worker dups the *real* stdout/stderr to private fds and writes
   all protocol JSON there. During each eval it redirects **both** Python-level
   `sys.stdout`/`sys.stderr` **and** OS-level fds 1/2 (into pipes), then folds
   the captured text into the response's `stdout`/`stderr`. Proven against both
   `print("hello")` and raw `os.write(1, b"...")` (the Cython-level hazard).

## Exit criteria — evidence

All from a single worker process driven by `harness.py`:

| Criterion | Result | Evidence |
| --- | --- | --- |
| Sage starts from a parent process | PASS | `{"op":"ready","ok":true}` banner |
| Multiple evals in one persistent namespace | PASS | 11 evals, one process |
| Assignment state survives between evals | PASS | `x=var("x")` → later `factor(x^4-1)` = `(x^2 + 1)*(x + 1)*(x - 1)`; `A=matrix(...)` → `A.eigenvalues()` = `[-0.372…?, 5.372…?]`; `A.det()` = `-2` even *after* an exception |
| Python/Sage exceptions return structured errors | PASS | `1/0` → `ok:false`, `error.type:"ZeroDivisionError"`, `message:"rational division by zero"`, full traceback |
| `stdout`/`stderr` captured in the envelope | PASS | `print("hello")` → `stdout:"hello\n"`, `value:false` |
| Protocol never corrupted by user printing | PASS | raw `os.write(1,b"RAW1\n")` → captured in `stdout`, response framing intact, next request unaffected |
| Parent detects worker death | PASS | SIGKILL the process group → write/readline yields EOF; `returncode = -9` |

### Gotcha worth carrying to V0.2

`sage -python worker.py` is a **bash wrapper** that fork-execs the real Python
worker as a *child*. SIGKILL to the Popen PID kills only the wrapper and
orphans the worker (which keeps answering on its inherited stdout pipe). The
fix — used here and required for the app's `SageKernel` — is to launch with
`start_new_session=True` and signal the whole **process group**
(`os.killpg`). See `PROBLEMS.md`.
