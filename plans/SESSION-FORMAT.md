# Casette Session File Format & Persistence (V0.10)

The on-disk session tape format and the persistence/replay semantics proven in
`v0/10-persistence/`. This is the prototype of **V1.2's session model** and
**V1.9's persistence**. The Codable types in `Sources/SessionStore/` are designed
to migrate into the app **verbatim**.

> Goal (V0.10 / V1.9): make the app feel persistent — restore the last session on
> launch, survive a crash, optionally replay — **without becoming
> document-oriented.** There is exactly ONE "last session" file the app rewrites
> in place; the user never opens/saves/names documents.

---

## Storage location policy

| Context | Path |
| --- | --- |
| **V1 (app)** | `~/Library/Application Support/Casette/sessions/last-session.json` |
| **Hermetic override** | `$CASETTE_CONFIG_DIR/sessions/last-session.json` |

`SessionStore.defaultSessionsDirectory()` resolves `CASETTE_CONFIG_DIR` first
(consistent with v0/09's Sage Doctor config), else Application Support. The
proof always sets `CASETTE_CONFIG_DIR` to a scratch dir, so it never touches the
real location. One file, rewritten in place — not a document store.

---

## File shape (schema version 1)

Pretty-printed JSON (`.prettyPrinted, .sortedKeys, .withoutEscapingSlashes`,
ISO-8601 dates) so it is **human-inspectable** (the spec demands "simple and
inspectable") and diff-stable. A real recorded file:

```json
{
  "schemaVersion" : 1,
  "created" : "2026-06-11T21:26:19Z",
  "updated" : "2026-06-11T21:26:22Z",
  "sageVersion" : "9.5",
  "precisionDigits" : 10,
  "rows" : [
    {
      "id" : "8922C500-FAB7-447E-8759-FAE6D3BC3308",
      "input" : "factor x^4 - 1",
      "sage" : "factor(x^4 - 1)",
      "status" : "ok",
      "timestamp" : "2026-06-11T21:26:22Z",
      "durationSeconds" : 0.00109,
      "expanded" : false,
      "provenance" : { "kind" : "cached", "cachedAt" : "2026-06-11T21:26:22Z" },
      "result" : {
        "kind" : "symbolic",
        "plain" : "(x^2 + 1)*(x + 1)*(x - 1)",
        "latex" : "{\\left(x^{2} + 1\\right)} {\\left(x + 1\\right)} {\\left(x - 1\\right)}",
        "repr" : "(x^2 + 1)*(x + 1)*(x - 1)",
        "exact" : true,
        "primaryIsApprox" : false,
        "actions" : ["simplify","factor","expand","approx","diff","integrate"],
        "artifacts" : [],
        "truncated" : false
      }
    }
  ]
}
```

### Session header

| Field | Type | Why |
| --- | --- | --- |
| `schemaVersion` | int | **First-class, load-bearing.** Restore refuses an unknown version politely (see Robustness). Currently `1`. |
| `created` / `updated` | ISO-8601 | `updated` is bumped on every atomic save. |
| `sageVersion` | string? | The Sage that produced the cached results (informational; a replay against a different Sage is allowed but visible). |
| `precisionDigits` | int | The worker `config` precision the cached `approx` values used; a replay restores the same precision. |
| `rows` | array | The ordered tape. **Order is load-bearing for replay.** |

### Session row (the V1.2 "Session Row Fields")

| Field | Type | Maps to V1.2 |
| --- | --- | --- |
| `id` | UUID | stable identity (survives save/restore) |
| `input` | string | **raw user input** (`factor x^4 - 1`) |
| `sage` | string | **compiled/bypassed Sage actually evaluated** (`factor(x^4 - 1)`) — what replay re-sends |
| `status` | enum | `ok` / `error` / `interrupted` / `running` |
| `result` | object? | the persisted envelope (below); optional → a `running` row persisted mid-eval is representable (crash-safety) |
| `timestamp` | ISO-8601 | when evaluated |
| `durationSeconds` | double? | wall-clock eval time |
| `provenance` | object | cached vs replayed (below) |
| `supersededCache` | object? | a differing replay's retained old envelope (below) |
| `expanded` | bool | UI state (`expanded/collapsed`) |
| `numeric` | bool? | the row was evaluated FORCE-NUMERIC (the V0.8 per-request `numeric:true`) — see the V1.8 note below |

> **V1.8 additive change (same pattern as V1.5's `truncation` and V1.7's
> artifact `error`):** a row gains the optional `numeric` flag, `true` only
> when it was submitted in numeric mode (decimal primary; the exact form
> preserved in the envelope's `exactValue`). Recorded on the REQUEST side
> because the envelope alone can't always tell (a numeric eval of a statement
> or error carries no `exact_value`), and because V1.9's **replay must re-send
> the request shape, not just the `sage`** — a numeric row replays with
> `numeric:true` so the restored display matches what the user saw. Optional
> and omitted-when-nil (a normal row's JSON is byte-unchanged), so schema
> **v1** files with or without it round-trip and old readers ignore it — no
> schema bump. The app's rerun already honors it (a numeric row reruns
> numeric, regardless of the toggle's current state).
>
> Relatedly, the session header's `precisionDigits` (present since V0.10) is
> now LIVE: the V1.8 precision control writes it, the boot/restart path
> re-applies it to the worker (`config` op) whenever it differs from the
> worker default 10, and V1.9 restores it with the session.

The **input vs sage** distinction is exactly the FRIENDLY-COMPILER.md split: a
friendly input (`factor x^4 - 1`) stores both the raw text and the compiled Sage;
a raw-Sage bypass (`1/3 + 1/5`, `A = matrix(...)`) stores the same string in both.

### Persisted result envelope (a render-ready SUBSET of the worker envelope)

The worker envelope (WORKER-PROTOCOL.md) carries transient framing (`id`, `op`,
`value`) and large optional payloads. The persisted subset is **only what the UI
needs to render a row with NO worker**:

| Persisted | From worker | Kept because |
| --- | --- | --- |
| `kind` | `kind` | which renderer / which actions |
| `plain` | `plain` | primary text (always) |
| `latex` | `latex` | math rendering (V0.4) |
| `repr` | `repr` | unambiguous fallback / degrade target |
| `approx` / `approxDigits` | `approx` / `approx_digits` | the `≈` secondary line (V0.8) |
| `exact` / `primaryIsApprox` / `exactValue` | same | exact/numeric display (V0.8) |
| `actions` | `actions` | the V1.11 actions menu |
| `artifacts` | `artifacts` | plots, **as path refs + liveness** (below) |
| `truncated` | `truncated` | "N of M chars" affordance |
| `truncation` | `truncation` | the sizes behind that affordance — `{plainLength, reprLength, plainCap, reprCap}`, optional, present only when `truncated` (**V1.5 additive**; see note below) |
| `stdout` / `stderr` | same | captured user output (display); empty folds to nil |
| `error` | `error` | error/interrupted detail |

**Dropped:** `id` (the row has its own UUID), `op` (framing), `value` (status
covers it). All additive — re-evaluating restores the full worker envelope.

> **V1.5 additive change (the one deviation from the V0.10 lift):** the
> optional `truncation` object was originally dropped ("`truncated` boolean is
> enough for restore"), but V1.5's result cards render the honest "showing N of
> M characters" note, which needs the original sizes. The field is optional and
> omitted-when-nil, so schema **v1** files with or without it round-trip
> unchanged and old readers ignore it — no schema bump.

`PersistedEnvelope(workerResponse:)` is the single mapping boundary from the raw
`[String: Any]` wire object to the model; it is **tolerant** (missing fields →
nil) so a future additive worker field never breaks restore.

---

## Artifacts: path refs + liveness (graceful degradation)

Artifacts are persisted as **path + format + recorded byte size + a liveness
status**, never as bytes. Liveness is resolved against the filesystem at restore
time:

```json
"artifacts" : [
  { "type":"image", "format":"svg", "path":"/tmp/sagecalc/session-…/plot-00001.svg", "bytes":20587, "status":"missing" },
  { "type":"image", "format":"png", "path":"/tmp/sagecalc/session-…/plot-00001.png", "bytes":18896, "status":"missing" }
]
```

**Why `missing` is the EXPECTED case, not an error (PROBLEMS.md V0.5):** the
worker writes artifacts into a session-scoped `/tmp/sagecalc/session-<pid>-<rand>/`
dir that is **removed when the worker session ends** (clean shutdown rmtrees it;
a crash leaves it for OS reaping). So on a real relaunch the worker that made the
plot is gone and its dir with it — a restored plot artifact is **essentially
always stale**. Policy:

1. **Restore degrades gracefully.** `SessionStore.load()` re-resolves every
   artifact's liveness; a gone file flips `present → missing`. The row **still
   restores** with its `plain` text (`"Graphics object consisting of 1 graphics
   primitive"`) and `kind:"plot"` intact — it does not fail.
2. **Replay regenerates.** Re-sending the plot's `sage` into a fresh worker
   produces **fresh, present** artifacts at new `/tmp` paths.

(A nil `path` — a format that failed to save originally — also resolves to
`missing`.)

> **V1.7 additive change (same pattern as V1.5's `truncation`):** an artifact
> gains the optional `error` field — the worker's per-format save error
> (`"<ExcType>: <msg>"`, WORKER-PROTOCOL.md "Plot failures are structured"),
> present only when that format failed to save (then `path` is nil). V1.7's
> plot cards and the Inspector surface it as the honest "couldn't be saved"
> note. Optional + omitted-when-nil, so schema **v1** files with or without it
> round-trip unchanged and old readers ignore it — no schema bump.

---

## Provenance: cached vs replayed (and the supersede policy)

Every row's CURRENT result carries where it came from:

```json
"provenance" : { "kind" : "cached",   "cachedAt" : "…" }          // loaded from disk
"provenance" : { "kind" : "replayed", "cachedAt" : "…", "replayedAt" : "…" }
```

- A freshly **restored** tape is entirely `cached` (the worker was not involved).
- After a **replay**, each replayed row flips to `replayed` with a fresh
  `replayedAt`, while **retaining its original `cachedAt`** — so both timestamps
  are visible.

### Supersede policy (decided + documented)

When a replayed result **differs** from the cached one, the policy is
**REPLACE the current result with the replayed value, but RETAIN the cached
envelope** in `supersededCache` (with a short `reason`):

```json
"result" : { "kind":"integer", "plain":"2", … },          // the replayed value (current)
"supersededCache" : {
  "envelope" : { "kind":"integer", "plain":"999", … },    // the old cached value, kept
  "cachedAt" : "…",
  "reason" : "plain changed"
}
```

So both the difference AND the policy are visible in the data model (the spec's
requirement). **Difference detection ignores artifact PATHS** (a fresh worker
writes new `/tmp` paths every run, so a path diff is not meaningful) but catches
a changed `kind` / `plain` / `latex` / `approx` / artifact-format-set. A
deterministic tape (e.g. `1/3+1/5` → `8/15`) therefore shows **no spurious
supersession** — only the provenance flips.

---

## Save / restore / replay semantics

- **Save is atomic and incremental.** `SessionStore.save()` writes to a temp file
  then renames over `last-session.json` (atomic on one filesystem), bumping
  `updated`. The recorder saves **after every row**, so a crash mid-session
  leaves a complete, valid file up to the last completed row — crash-safety is
  the point. No `.tmp` files are left behind.
- **Restore needs NO worker.** `load()` reads + decodes + re-resolves artifact
  liveness. The proof restores the tape and renders `plain`/`latex`/`approx`
  with **Sage genuinely not spawned** (the worker process is never started in
  Phase 2). A restored row's `plain`/`latex` match exactly what was saved.
- **Replay is order-preserved and state-dependent.** `replay()` spawns a **fresh**
  worker and re-sends each row's `sage` **in tape order**. Because order is
  preserved, a row that assigns (`A = matrix(...)`) runs before a row that uses it
  (`A.eigenvalues()`), so state-dependent replay succeeds. Required-variable
  preludes (V0.7 `var('x')` policy) are re-emitted per row since a fresh worker
  has an empty namespace.

---

## Robustness (the failure modes)

| Input | Outcome |
| --- | --- |
| **Missing file** (first launch) | `.fresh` — start a new session |
| **Empty file** | `.fresh` (not quarantined — an empty isn't "corrupt") |
| **Corrupt JSON** | `.corruptQuarantined` — the bad file is moved aside to `last-session.corrupt-<ts>.json`, the app starts fresh, never crashes |
| **Unknown schema version** | `.refusedSchema(found, supported)` — polite refusal; the file is **left intact** so a newer app version can still read it (don't quarantine the future) |

Schema is **peeked** (via `JSONSerialization`) before the strict `Codable`
decode, so a forward-incompatible shape is refused (not mis-quarantined) even if
strict decoding would also fail.

---

## V1.2 / V1.9 integration notes

- **V1.2 (Session Model):** lift `Session` / `SessionRow` / `PersistedEnvelope` /
  `PersistedArtifact` / `Provenance` / `RowStatus` verbatim as the in-app model.
  They already satisfy the V1.2 exit criteria: rows append, have stable identity
  (`UUID`), represent `running`/`error` rows, and the result data
  (`PersistedEnvelope`) is **independent of UI rendering** (it is pure Codable
  data; the SwiftUI layer reads `plain`/`latex`/`actions`). `Evaluation` /
  `CompiledInput` / `SymbolSnapshot` / `KernelState` from the V1.2 list are not
  yet modeled here (they belong with the live kernel, not the persisted tape) —
  add them in-app; the persisted row only needs `input`/`sage`/`result`.
- **V1.9 (Persistence & Recovery):** `SessionStore` is the recovery engine. Wire
  it: save after every appended/completed row (incremental), `load()` on launch
  (restore the visible tape — quit/relaunch criterion; crash-recovery is the same
  path since saves are atomic+incremental), and expose the optional
  "replay session" command via `WorkerDriver.replay`. "Missing Sage path opens
  Sage Doctor" is the v0/09 boundary, not this one.

  > **V1.9 landed (2026-06-12) — how the lift actually integrated** (schema
  > untouched, still v1; the three additive fields needed zero store changes
  > because they're omitted-when-nil Codable):
  > - `SessionStore` lives at `Sources/Casette/Persistence/SessionStore.swift`,
  >   near-verbatim. ONE deviation: `defaultSessionsDirectory(environment:)`
  >   takes the environment as a parameter (production call site passes the
  >   process env) so app tests inject the `CASETTE_CONFIG_DIR` override
  >   instead of racing `setenv` (PROBLEMS.md parallel-test rule).
  > - `ShellModel` saves synchronously after every `append`/`complete`/
  >   `edit`/`toggleExpanded`/`setPrecision`/replayed row. There is NO
  >   quit-time save — the per-row saves ARE crash recovery (proven by
  >   kill -9 + relaunch).
  > - **`refusedSchema` also disables SAVING for the run** (not just loading):
  >   a session written by a newer app must never be clobbered by this one's
  >   first row.
  > - A restored `running` row (persisted mid-eval — the crash case) flips to
  >   `interrupted` with a synthetic "Casette quit before this evaluation
  >   finished" envelope at restore: nothing will ever complete it, and an
  >   eternal spinner would be a lie. The flip is re-persisted.
  > - **Replay** (`ShellModel.replaySession`, Sage ▸ Replay Session) restarts
  >   the worker (fresh namespace, V0.10 semantics) and re-sends the whole
  >   tape in order as ONE serial-queue item; preludes are recompiled per row
  >   (`SessionReplay.preludes` — ambiguous inputs use their recorded
  >   resolution); a **numeric row replays with `numeric:true`** (the V1.8
  >   note honored — the request shape, not just the `sage`); the supersede
  >   policy is `SessionReplay.difference`, ported verbatim (paths never
  >   compared).
  > - **Cached-vs-replayed marking is transient presentation:** the persisted
  >   `Provenance` records a fresh eval as `cached` (that's what a restore
  >   loads), so "restored this run" lives in a transient
  >   `ShellModel.restoredRowIDs` set; the quiet per-row tag
  >   (`RowProvenanceMark`) derives from membership + provenance kind. Fresh
  >   rows show nothing.
  > - `sageVersion` stays nil in app-written files for now: the worker's
  >   ready banner carries only the pid, and the field is informational. A
  >   future phase (V1.10 has the version handy) can start filling it —
  >   additive, no schema change.
- **Unify the duplicated worker driver.** `WorkerProcess.swift` + `LineReader.swift`
  here are **copied verbatim** from `v0/09-sage-doctor` (frozen evidence — do not
  refactor v0/09). V1 should pull these into **one** `SageKernel` that both the
  Doctor (V1.10) and the session replay (V1.9) use. The copies are byte-identical,
  so unification is a move, not a merge.
- **Worker contract is frozen.** The `PersistedEnvelope(workerResponse:)` mapping
  depends only on the WORKER-PROTOCOL.md envelope, which is frozen for V1 — so the
  mapping is stable. New worker fields are additive and map to nil until added
  here.
```

