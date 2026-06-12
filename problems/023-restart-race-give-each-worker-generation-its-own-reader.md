## Restart race: give each worker generation its own reader queue + EOF event

**Symptom.** Right after a hard-kill + `restart()`, the *fresh* worker raised
"worker never became ready" in ~0.2s — far too fast to be a real boot failure. A
clean standalone boot took ~3s and worked.

**Cause.** The controller shared one `self._eof` event and reader thread across
worker generations. On restart, the **old** reader thread (still draining the dead
worker's pipe) hit EOF and ran `self._eof.set()` — tripping the flag the **new**
worker's startup was watching. The new worker looked like it crashed on boot.

**Fix.** Make the reader thread a `@staticmethod` that takes *its* queue and *its*
EOF event as arguments, created fresh in `start()` for each generation. A stale
reader can then only set its own (now-ignored) event.

```python
self._q = queue.Queue(); self._eof = threading.Event()
threading.Thread(target=self._read_loop,
                 args=(self.proc.stdout, self._q, self._eof), daemon=True).start()
```

**Related:** never let two threads drain the one response queue. First cut had
`interrupt()` and `evaluate()` both calling the queue reader, so the interrupt
response got consumed by the wrong waiter and `interrupt()` spuriously "timed out."
Make `evaluate` the **sole** queue consumer; cancel/timeout only *signal* (set a
`threading.Event` the eval loop watches), never read.

---
