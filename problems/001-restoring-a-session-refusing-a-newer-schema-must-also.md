## Restoring a session: refusing a newer schema must also disable SAVING, "restored" is not a persisted fact, and a restored `running` row must not spin

**Three design traps closed while wiring V1.9 (cheap now, data-loss or
lying-UI later).**

**1. A polite schema refusal that only affects LOAD still destroys the file —
the first SAVE clobbers it.** The V0.10 contract refuses an unknown
`schemaVersion` and leaves the file intact "so a newer app can still read
it." But the app saves after EVERY row — so if the run continues with a
fresh in-memory session and the store still attached, the user's first
keystroke overwrites the future file with a v1 one. The refusal has to
propagate to the write path: on `.refusedSchema` the model detaches the
store entirely (persistence off for the run, logged). Loading honestly and
saving naively is a data-loss bug with a polite face.

**2. "Cached vs fresh" cannot be read off the persisted `Provenance` —
a fresh eval IS recorded as `cached`.** The V0.10 recorder (and the app's
`SessionRow.apply`) deliberately stamp a freshly completed row
`provenance.kind == .cached`, because that's what a later restore loads.
So at runtime, "this row was loaded from disk" vs "this row was just
evaluated" is **transient UI state**, not model state: `ShellModel` keeps a
`restoredRowIDs` set filled at restore (cleared per row on edit), and the
quiet tape tag derives from membership + the persisted kind. Trying to
persist this distinction would be wrong twice over — it would change schema
for something only meaningful within one run, and after the next restore
every row is cached again anyway.

**3. A row persisted mid-eval restores as `running` — flip it to
`interrupted` at restore or it spins forever.** Crash-safety persists the
pending row before its result exists. On restore with a CONNECTED kernel,
the V1.5 card renders `.running` as "Evaluating…" with a live spinner — but
nothing will ever complete a restored row (its evaluation died with the old
process). Restore flips stale `running` → `interrupted` with a synthetic
"Casette quit before this evaluation finished" envelope (the same shape the
controller uses for restart-preempted evals) and re-persists. The data
stays honest and the UI stops promising work that isn't happening.

(Bonus fact from the kill -9 gate: SIGKILLing the app does NOT leak the
worker even though `applicationWillTerminate`/`KernelReaper` never run —
the worker's `for raw in sys.stdin` loop sees EOF when the app's pipe end
dies, and the process exits on its own. The reaper is still needed for the
clean-quit path where the app outlives the read loop's natural end.)

---
