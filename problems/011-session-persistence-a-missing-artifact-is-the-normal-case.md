## Session persistence: a missing artifact is the NORMAL case, paths aren't identity, and peek the schema before decoding

**Three traps from V0.10 (session tape persistence-lite).**

**1. A restored plot artifact is essentially ALWAYS missing — model it as
expected, not as an error.** The worker saves plots into a session-scoped
`/tmp/sagecalc/session-<pid>-<rand>/` dir that **dies with the worker** (clean
shutdown rmtrees it; a crash leaves it for OS reaping — PROBLEMS.md V0.5). So on
the next app launch the worker that made the plot is gone and its dir with it: a
persisted artifact path almost never still exists. If restore treats a gone file
as a failure, **every** restored session with a plot looks broken. The fix is to
make `missing` a first-class liveness status resolved at load time: the row still
restores with its `plain` text and `kind:"plot"`, and an optional **replay
regenerates** fresh artifacts. Don't persist bytes; persist `{path, format, bytes,
status}` and re-resolve `status` against the filesystem on every load.

**2. Artifact PATHS are not result identity — a fresh worker writes new paths
every run.** To decide "did a replayed result differ from the cached one?" (the
supersede policy), the obvious move is to compare the two persisted envelopes for
equality. **Wrong for any plot:** replay spawns a fresh worker whose
`/tmp/sagecalc/session-<newpid>-<newrand>/` dir gives **every** artifact a new
path, so a path-sensitive `==` flags every plot row as "superseded" on every
replay. The difference check must compare what's *semantically* the result —
`kind` / `plain` / `latex` / `approx` and the artifact **format set** — and
explicitly **ignore paths**. Then a deterministic tape (`1/3+1/5`→`8/15`) shows
zero spurious supersession; only the provenance flips `cached → replayed`.

**3. Peek `schemaVersion` BEFORE the strict `Codable` decode, or a future file
gets mis-quarantined as "corrupt."** Robust load has three failure modes: corrupt
JSON (quarantine + start fresh), unknown/newer schema (refuse politely, leave the
file intact for a newer app), empty/missing (fresh). But a forward-incompatible
*future* shape would **also fail strict decoding** — so if you decide
corrupt-vs-version-mismatch by "did `JSONDecoder` throw?", a newer file is wrongly
quarantined and lost. Fix: read just the top-level `schemaVersion` with
`JSONSerialization` *first*; if it isn't the supported version, return
`.refusedSchema` (file untouched) and never reach the strict decode. Only a file
that parses as JSON-with-a-known-version but then fails `Codable` is truly
corrupt. (Also: don't quarantine an **empty** file — an empty isn't corrupt, it's
"no session yet" → fresh.)

**Corollary — `FileManager` is not `Sendable` (Swift 6).** A `struct` that stores
a `FileManager` can't conform to `Sendable` under strict concurrency. The
`SessionStore` doesn't need `Sendable`, so drop the conformance rather than fight
it. And a top-level CLI `let` is `@MainActor`-isolated, so free helper functions
that touch it must take it as a parameter, not reference it as a global.
