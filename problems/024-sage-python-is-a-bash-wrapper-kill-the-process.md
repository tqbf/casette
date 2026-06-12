## `sage -python` is a bash wrapper — kill the process *group*, not the PID

**Symptom.** Sent `SIGKILL` to the `subprocess.Popen` PID of
`sage -python worker.py`, then the "worker is dead" check kept failing: the
worker still returned a valid response to the next request.

**Cause.** `/usr/local/bin/sage` is a **bash script**. `sage -python …`
fork-execs the real Python worker as a *child* of that bash wrapper. The
Popen PID is the wrapper; the worker is its child and **inherited the same
stdin/stdout pipe fds**. Killing the wrapper orphans the worker (reparented to
launchd/init) and it keeps reading/writing the pipe, so the parent sees no EOF.

Observed tree:

```
51932  bash /usr/local/bin/sage -python …/worker.py   <- Popen PID
51933    python3 …/worker.py                            <- real worker (child)
```

**Fix.** Launch the worker in its own session/process group and signal the
whole group:

```python
proc = subprocess.Popen([...], start_new_session=True, ...)
os.killpg(os.getpgid(proc.pid), signal.SIGKILL)   # wrapper + worker together
```

The real app's `SageKernel` (V1.3) and the lifecycle work (V0.2) **must** do
this; killing only the PID will leak orphaned Sage workers.

---
