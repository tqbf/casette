## Restart re-init must CHAIN on the serial kernel queue — only the kill/boot itself may run un-chained, or the next submission races the fresh worker's preludes

**The symptom (V1.8 gate).** The pre-existing real-Sage test "x, y, z, t are
predefined at boot and after restart" — green at every prior gate — failed
during the V1.8 run: after `restartKernel()`, `expand((x+1)^2)` came back
`NameError: name 'x' is not defined`. The fresh worker existed, but the eval
beat the boot prelude to it. V1.8 didn't introduce the race; it widened the
window's *visibility* (a third parallel real-Sage suite raised machine load,
and V1.8 added a second post-restart re-init step — the session-precision
`config` op — to lose).

**The mechanism.** `restartKernel()` ran the WHOLE pipeline in one un-chained
`Task { restart(); evaluate(prelude); refreshSymbols() }` — un-chained
deliberately, because restart must preempt a stuck eval (chaining `restart()`
behind the kernel queue would deadlock behind the very eval it kills). But
user submissions enqueue on the serial `kernelQueue`, which knows nothing of
that Task: a submission typed right after ⌘⇧R could evaluate between the
fresh worker's boot and its prelude. Any "session state the worker holds"
(predefined variables, the V0.8 `precision_digits`) was silently absent for
that one eval — the kind of bug that looks like a flake forever.

**The fix — split the pipeline at the preemption boundary:**

```swift
let restart = Task { await controller.restart() }   // un-chained: preempts
enqueueKernelWork {                                  // chained: orders
    await restart.value
    _ = await controller.evaluate(Self.bootPrelude)
    if let digits = precisionNeedingReapply { _ = await controller.configure(...) }
    await refreshSymbols()
}
```

Only the kill/boot runs outside the queue (it signals; it never consumes the
wire). The RE-INIT rides the queue and awaits the restart first, so the next
submission deterministically evaluates after the fresh worker has its
calculator variables and session precision.

**Rules.**
1. Anything that must PREEMPT in-flight work runs un-chained; anything that
   must ORDER against future work runs on the queue. A restart pipeline is
   both — split it, don't pick one.
2. Worker-held session state (predefined vars, precision) must be re-applied
   on a path subsequent submissions are ordered BEHIND, or the first
   post-restart eval sees a half-initialized session.
3. A test for "after restart, X works" must first prove the restart pipeline
   COMPLETED via an observable that only the pipeline's LAST step changes
   (e.g. a sentinel symbol vanishing from the refreshed symbol table) —
   waiting on `kernelState` alone races, because the state was already
   `completed` before the restart began.

---
