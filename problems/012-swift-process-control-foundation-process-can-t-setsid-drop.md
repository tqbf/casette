## Swift process control: `Foundation.Process` can't `setsid` — drop to `posix_spawn`, and an explicit override must fail loud

**The context (V0.9).** Sage Doctor is the first time the **parent side** is
written in Swift (the V1.3 `SageKernel` dry run), so every PROBLEMS.md process
lesson learned in Python (`controller.py`) had to be re-proven in Swift. Three
Swift-specific traps.

**1. `Foundation.Process` has no `start_new_session` equivalent — use
`posix_spawn` with `POSIX_SPAWN_SETSID`.** The whole orphan-avoidance strategy
(kill the *group*, because `sage` is a bash wrapper that fork-execs the real
worker) depends on putting the child in its **own session / process group** so
`killpg` reaps the wrapper AND the worker together. Python does this with
`subprocess.Popen(..., start_new_session=True)`. Swift's `Process` **exposes no
such knob** (no `setsid`, no pre-exec hook). The fix is to skip `Process`
entirely and call `posix_spawn` directly:

```swift
var attributes = posix_spawnattr_t(nil as OpaquePointer?)
posix_spawnattr_init(&attributes)
posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))  // == start_new_session
// ... posix_spawn_file_actions_adddup2 for stdin/stdout, addopen /dev/null for stderr ...
posix_spawn(&pid, sagePath, &fileActions, &attributes, argv, environ)
```

Then hard-kill is `killpg(getpgid(pid), SIGKILL)` and interrupt is
`kill(realPID, SIGINT)` to the banner pid — identical semantics to the Python
controller. **Proven:** after the full doctor run (incl. interrupt + restart) and
after a deliberate hang-at-boot fixture (`hang-sage.sh` that `sleep`s instead of
emitting the ready banner, *and* forks a child to mirror the wrapper→worker tree),
`pgrep -fl "sage -python|worker.py|sleep 100000"` is **clean**. Killing only the
spawned (wrapper) pid would have orphaned the worker — the V0.1 trap, now also
closed in Swift.

**2. Boot-failure must hard-kill before returning, or a hung wrapper leaks.** The
`start()` path waits for the ready banner with a timeout. On timeout (hang at
boot) the natural thing is to `throw` — but the wrapper + its children are still
alive. The fix: `hardKill()` (process-group SIGKILL) in the failure branch
*before* throwing. This is what makes the hang-at-boot case orphan-clean.

**3. SIGINT delivery + pipe draining: one reader thread, single consumer.** A
dedicated reader thread (`LineReader`) drains the worker's stdout fd with raw
`read()` into a lock-guarded queue, splitting on `\n` and parsing JSONL; the
control thread is the **sole consumer** via an `NSCondition` wait-with-deadline.
This mirrors `controller.py`'s "evaluate is the sole queue consumer; cancel only
signals" rule — so a SIGINT/await never races the response off the queue. Each
`WorkerProcess` owns exactly one `LineReader`, so a killed generation's reader
can't trip a fresh worker's state (the restart-race lesson). The interrupt is
prompt because we **never reinstall a SIGINT handler** in the worker — cysignals
stays in charge (the V0.2 lesson) — and Swift just `kill(realPID, SIGINT)`s the
banner pid. Verified: `while True: pass` interrupted → `interrupted` envelope;
escalation-to-killpg path is in place for a swallowed SIGINT.

**4. An explicit `--sage PATH` that doesn't exist must fail LOUDLY.** First cut:
discovery records the non-existent override as a candidate and falls through to
the next existing one — so `--sage /no/such/sage` *silently ran the real Sage*,
masking the user's typo. Wrong: an explicit override is the user asking for *that*
binary. The fix is a guard in `SageDoctor.run`: if an override is given and it
doesn't exist, return a `Discovery: FAIL` with an actionable message, never fall
through. (Auto-discovery with *no* override still falls through normally.)

---
