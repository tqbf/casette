# V0.10 — Session Tape Persistence-Lite

Proves the app can **restore recent session history without becoming
document-oriented**: a JSON tape on disk, atomic+incremental save, restore with
Sage genuinely not involved, optional replay into a fresh worker, cached-vs-
replayed provenance, and graceful artifact degradation.

This SwiftPM package is the prototype of **V1.2's session model** and **V1.9's
persistence**. `SessionStore` (the library) is the surviving artifact — its
Codable types migrate into the app verbatim. Full schema/policy reference:
[../../plans/SESSION-FORMAT.md](../../plans/SESSION-FORMAT.md).

## Layout

- `Sources/SessionStore/` — the surviving library:
  - `SessionModel.swift` — `Session` / `SessionRow` / `Provenance` / `RowStatus`.
  - `PersistedEnvelope.swift` — the render-ready envelope subset + `PersistedArtifact` + liveness.
  - `EnvelopeMapping.swift` — raw worker JSON → `PersistedEnvelope` (the wire→model boundary).
  - `SessionStore.swift` — atomic/incremental save, robust load, storage-location policy.
  - `WorkerDriver.swift` — record an original tape; replay a restored one (provenance + supersede policy).
  - `WorkerProcess.swift` / `LineReader.swift` — **copied verbatim** from `v0/09-sage-doctor` (frozen). V1 unifies these into one `SageKernel`.
- `Sources/casette-tape/` — the proof harness CLI.
- `Tests/SessionStoreTests/` — 21 swift-testing pure-logic units (codec, robustness, provenance, liveness; no Sage).

## Reproduce

```sh
cd v0/10-persistence
swift test                 # 21/21 pure-logic units (no Sage)
swift run casette-tape all # the full worker-dependent proof — 22/22 checks
```

`casette-tape all` is hermetic (it sets `CASETTE_CONFIG_DIR` to a scratch dir).
To capture an inspectable session file:

```sh
CASETTE_CONFIG_DIR=/tmp/casette-example swift run casette-tape record-example
cat /tmp/casette-example/sessions/last-session.json
```

## Exit criteria — all PASS (real Sage 9.5)

`swift run casette-tape all` → **22 passed, 0 failed**, `pgrep` clean.

| Exit criterion | Evidence (harness phase) |
| --- | --- |
| **Last session tape can be restored** | Phase 2: `load()` → `.restored`, 5 rows, no worker spawned. |
| **Inputs + rendered results survive restart** | Phase 2: restored row 0 `plain`/`latex` == saved; row 1 renders `8/15` + `≈ 0.5333333333`, `exact=true` with no worker. |
| **Optional replay into a fresh Sage worker** | Phase 3: fresh worker, each `sage` re-sent in order; state-dependent `A.eigenvalues()` → `[3, 2]` because `A = matrix(...)` ran first. |
| **Replayed vs cached distinguishable** | Phase 3/4: every row flips `cached → replayed` with a `replayedAt` (keeps `cachedAt`); a differing replay retains the old envelope in `supersededCache` (`999` kept, `2` current, reason "plain changed"). |
| **Missing artifacts degrade gracefully** | Phase 5: plot row's artifact files deleted → restore marks them `missing`, row keeps `plain`+`kind:plot`; replay regenerates fresh present artifacts. |
| **Robustness** (bonus) | Phase 6: corrupt JSON → quarantined + fresh; unknown schema (9999) → polite refusal, file intact; empty → fresh; missing → fresh. |

The recorded `last-session.json` is pretty-printed and human-inspectable — see
the `record-example` output above and SESSION-FORMAT.md for the annotated shape.
