## 2026-06-11 — V0.10: Session tape persistence-lite — PASS · **V0 COMPLETE (gate passed)**

**Did.** Built session persistence as a Swift SwiftPM package
(`v0/10-persistence/`): a `SessionStore` **library** (the surviving artifact — the
prototype of V1.2's session model + V1.9's persistence), a `casette-tape`
**CLI/harness**, and **21 swift-testing** pure-logic units. The Codable types
(`Session` / `SessionRow` / `PersistedEnvelope` / `PersistedArtifact` /
`Provenance` / `RowStatus`) mirror the V1.2 core-types list and the frozen
WORKER-PROTOCOL.md envelope, and are written to migrate into the app **verbatim**.
`WorkerProcess.swift` + `LineReader.swift` are **copied verbatim** from
`v0/09-sage-doctor` (frozen evidence — not refactored); V1 should unify them into
one `SageKernel`. **`swift test` 21/21 · `casette-tape all` 22/22** against real
Sage 9.5. `pgrep -fl "sage -python|worker.py"` clean.

**Exit criteria — all PASS (executed evidence in README):**
- **Last session tape restored** — record a real 5-row worker session
  (friendly-compiled `factor x^4 - 1` + raw-Sage bypasses incl. a
  state-dependent `A = matrix(...)` then `A.eigenvalues()`), persisted
  **incrementally + atomically** after every row; `load()` reconstructs it.
- **Inputs + rendered results survive restart, Sage NOT involved** — Phase 2
  restores with the worker **genuinely never spawned**; restored row 0's
  `plain`/`latex` match what was saved, row 1 renders `8/15` + `≈ 0.5333333333`
  with `exact=true` from one persisted envelope, no round-trip.
- **Optional replay into a fresh worker** — re-send each row's `sage` in tape
  order into a fresh worker; the state-dependent `A.eigenvalues()` → `[3, 2]`
  **because order is preserved** (A established first).
- **Replayed vs cached distinguishable** — provenance flips `cached → replayed`
  with a fresh `replayedAt` (keeping the original `cachedAt`); a deterministic
  row's value is unchanged (only provenance flips). A **differing** replay
  retains the cached envelope in `supersededCache` (policy: replace current, keep
  old + reason) — proven by forcing a wrong cache (`999`) and replaying `1+1`→`2`.
- **Missing artifacts degrade gracefully** — persist a plot row, delete the
  artifact files (the V0.5 `/tmp` session-dir-dies-with-worker case, which is the
  EXPECTED case on restore), restore → artifacts marked `missing`, row still
  renders with `plain` + `kind:plot`; replay regenerates fresh present artifacts.
- **Robustness** — corrupt JSON → quarantined aside + fresh start (no crash);
  unknown schema (9999) → polite refusal, file left intact; empty/missing → fresh.

**Storage policy.** One `last-session.json` rewritten in place (NOT
document-oriented): `~/Library/Application Support/Casette/sessions/` in V1,
`$CASETTE_CONFIG_DIR/sessions/` for the hermetic proof. Pretty-printed, sorted
keys, unescaped slashes, ISO-8601 dates → human-inspectable. Frozen in
plans/SESSION-FORMAT.md (schema, field choices, provenance/supersede policy,
replay semantics, V1.2/V1.9 integration notes).

**Learned / surprised.**
- **A "missing artifact" is the normal case, not an error.** PROBLEMS.md V0.5
  said the worker's `/tmp/sagecalc/session-<pid>-<rand>/` dir dies with the
  worker — so on a real relaunch a plot artifact is **essentially always stale**.
  Modeling `missing` as expected (row restores with plain text; replay
  regenerates) rather than as a failure is what makes restore robust.
- **Difference detection must ignore artifact PATHS.** A fresh worker writes new
  `/tmp` paths every replay, so a naive envelope `==` would flag every plot row as
  "superseded." The supersede check compares kind/plain/latex/approx and the
  artifact FORMAT set, never paths — so a deterministic tape shows zero spurious
  supersession.
- **Schema version must be PEEKED before the strict decode.** A
  forward-incompatible future shape would fail strict `Codable` decoding and get
  mis-quarantined as "corrupt." Reading just `schemaVersion` via
  `JSONSerialization` first lets restore refuse the future **politely** and leave
  the file intact for a newer app. (PROBLEMS.md.)
- **`FileManager` isn't `Sendable`** — a struct holding one can't be `Sendable`
  under Swift 6 strict concurrency. Dropped the conformance (the store doesn't
  need it); a top-level CLI `let` is `@MainActor`-isolated, so free helper
  functions take the checklist as a parameter rather than referencing a global.

### V0 COMPLETION GATE — **PASSED** (all prior harnesses re-run this date, clean)

Every gate criterion from INITIAL.md is covered by an executed proof, re-run one
final time today with **zero failures and `pgrep` clean**:

| Gate criterion (INITIAL.md) | Proof | Result |
| --- | --- | --- |
| Sage worker protocol is reliable | v0/01 harness | **18/18** |
| Worker can be killed and restarted | v0/02 harness (+ v0/09 restart, from Swift) | **35/35** (+ ok) |
| Common Sage results can be classified | v0/03 harness | **97/97** |
| LaTeX renders in SwiftUI | v0/04 (on-screen, prior) + v0/08 latex fields | verified (SwiftMath) |
| Plots can render as artifacts | v0/05 harness (+ on-screen PNG verdict, prior) | **88/88** |
| Live symbols can populate a sidebar | v0/06 harness | **24/24** |
| Friendly command compiler proves the interaction model | v0/07 swift test + e2e | **69/69 + 19/19** |
| (V0.8 exact/numeric policy) | v0/08 harness | **95/95** |
| (V0.9 Sage Doctor — Swift drives the worker; V1.3 risk retired) | v0/09 swift test + real doctor run | **32/32 + all checks ok** |
| (V0.10 session persistence) | v0/10 swift test + casette-tape all | **21/21 + 22/22** |

**Verdict: V0 COMPLETE.** The kernel bridge is proven end-to-end; the project
risk now shifts from "can this work?" to "can this become a good macOS app?"
**Next frontier: V1.1** — app skeleton & layout.
