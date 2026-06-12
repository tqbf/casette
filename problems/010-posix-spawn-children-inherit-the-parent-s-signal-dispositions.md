## `posix_spawn` children INHERIT the parent's signal dispositions — spawn the worker with `POSIX_SPAWN_SETSIGDEF` + `SETSIGMASK` or interrupts silently die

**The symptom (V1.3).** The app's `SageKernel` — a faithful unification of
v0/09's proven `WorkerProcess`/`LineReader` — failed the integration tests:
SIGINT to the worker's real banner pid did **nothing**, every interrupt and
timeout escalated to the hard process-group kill, and `while True: pass` was
never answered with an `interrupted` envelope. Yet the *identical* spawn code
in `sage-doctor` (v0/09) interrupted fine on the same machine, and a Python
control (`os.kill(pid, SIGINT)` from a plain `python3` parent) interrupted in
0.00s. Same worker, same signal, same pid discipline — different parent.

**The cause.** A `posix_spawn`/`exec` child **inherits the parent's signal
mask and its ignored-signal dispositions** (`SIG_IGN` survives exec; handlers
reset to default). The swift-testing runner runs tests with SIGINT
ignored/masked, so the worker's Python started life with SIGINT ignored —
and **CPython does not install its `KeyboardInterrupt` handler (and cysignals
does not take ownership of SIGINT) when the signal arrives ignored from the
parent.** The SIGINT was delivered and discarded. v0/09 never saw this
because its parent was a plain CLI with default dispositions — the proof was
correct but the *parent context* was an untested variable. A GUI app parent
can have its own non-default dispositions too, so this is not just a
test-runner quirk.

**The fix — reset the child's signal world at spawn,** alongside
`POSIX_SPAWN_SETSID`:

```swift
var defaultSignals = sigset_t(); sigfillset(&defaultSignals)
posix_spawnattr_setsigdefault(&attributes, &defaultSignals)   // un-ignore all
var emptyMask = sigset_t(); sigemptyset(&emptyMask)
posix_spawnattr_setsigmask(&attributes, &emptyMask)           // unblock all
posix_spawnattr_setflags(&attributes,
    Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
```

With that, the full interrupt story works from inside the test runner AND the
app: SIGINT honored promptly (`interrupted` envelope), escalation still in
place for genuinely hostile code (`SIG_IGN` installed *by user code* is still
hard-killed). **Rule: any process-spawning code whose child must receive
signals resets dispositions and mask at spawn — never assume the parent's
signal state is default.** (Python's `start_new_session=True` path never hit
this because the harnesses' parents were vanilla `python3`.)

---
