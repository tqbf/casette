## 2026-06-12 — V1.9: Session persistence and recovery — PASS (live gate PASSED, all 11 checks)

**Live gate (opus verifier, computer-use) — PASS, all 11.** On screen:
quit/relaunch restores all rows with original timestamps + quiet cached tags,
window frame, and the persisted History tab; the restored plot row shows the
honest missing box + Rerun; "Sage ready" then fresh evals work with a fresh
namespace (Symbols has `t x y z`, NOT `A`); Inspector Source: Cached →
Replay Session → `A.eigenvalues()` = `[3, 2]` again (order preserved), plot
re-renders, numeric row keeps decimal + "= 1/3 exactly", tags flip to
replayed, ZERO superseded sections; Inspector Source: Replayed + timestamp;
kill -9 → relaunch restores everything incl. `n * 2 → 209458`, no stray
workers; kill -9 mid-`sleep(60)` → restored row reads honest "Interrupted —
Casette quit before this evaluation finished", no eternal spinner; ⌘B-hidden
sidebar persists; last-session.json pretty/sorted/ISO and human-readable;
final quit `pgrep` clean. **Two polish notes for later phases:** (1) kill -9
orphans an in-flight worker until its computation ends (inherent to SIGKILL;
consider reaping stale worker pids at next launch — V1.14 candidate);
(2) `/tmp/sagecalc/session-*` dirs survive a clean ⌘Q (the reaper group-kills
instead of a graceful `shutdown` op, so the worker never removes its dir —
stale-temp accumulation; cleanup-on-launch is a V1.14 candidate).

**The app feels persistent without becoming document-oriented.** Quit and
relaunch restores the visible tape from ONE pretty-printed
`~/Library/Application Support/Casette/sessions/last-session.json`
(`$CASETTE_CONFIG_DIR` override); a kill -9 crash loses nothing up to the
last completed row (proven live); a restored tape renders with **Sage
genuinely not involved** (missing plots show V1.7's honest box — its real
moment); an optional **Sage ▸ Replay Session** re-evaluates the whole tape
in order in a fresh worker; rows that didn't come from a fresh eval carry a
**quiet provenance tag** (`cached` / `replayed`, timestamp styling); and the
UI layout (sidebar visible/hidden + selected tab + window frame) survives
relaunch.

### What was built (and the decisions)

- **`SessionStore` lifted from v0/10** into
  `Sources/Casette/Persistence/SessionStore.swift`, near-verbatim — the
  V1.2 model types were lifted for exactly this moment, and the three
  post-lift additive fields (`truncation` V1.5, artifact `error` V1.7,
  `SessionRow.numeric` V1.8) are omitted-when-nil Codable, so the store
  needed zero changes and the schema stays **v1**. ONE deviation:
  `defaultSessionsDirectory(environment:)` takes the environment as a
  parameter so tests inject the override — no `setenv` (the documented
  v0/10 parallel-test race stays in v0).
- **Save = synchronous atomic temp-write+rename after EVERY mutation**
  (`append` / `complete` / `edit` / `toggleExpanded` / `setPrecision` /
  each replayed row), via one `ShellModel.persist()` funnel. There is NO
  quit-time save — the per-row saves ARE crash recovery. A save failure
  logs and never takes the calculator down.
- **Restore before connect** (`RootView.task`:
  `restoreLastSession(from:)` then `connectKernel()`): the tape is back
  even when discovery fails — the existing honest banner stands over a
  fully readable session (the V1.10 Doctor hook point is that banner).
  Robust-load outcomes per SESSION-FORMAT.md: corrupt → quarantine +
  fresh; **refused (newer) schema → fresh AND saving disabled for the run**
  (loading politely but saving naively would clobber the future — new
  PROBLEMS.md entry); restored `running` rows (the crash case) flip to
  `interrupted` with a synthetic "Casette quit before this evaluation
  finished" envelope (an eternal spinner would lie). Restored inputs seed
  Up/Down history; a restored non-standard precision lands in the menu
  (V1.8's injected choices) and is re-applied to the worker at boot (the
  existing `precisionNeedingReapply` path, now driven from disk).
- **Cached vs replayed is marked QUIETLY (V0.10's call) and derived, not
  persisted:** the persisted `Provenance` records a fresh eval as `cached`
  (that's what a restore loads), so "loaded from disk this run" lives in a
  transient `ShellModel.restoredRowIDs` set; `RowProvenanceMark` derives
  the tag (membership + provenance kind) and `TapeRowView` renders it next
  to the timestamp at the meta scale in tertiary — with a `.help` tooltip
  and a spoken full-sentence `accessibilityLabel` (swiftui-pro finding).
  The Inspector gains a **Source** field (cached/replayed), a **Replayed**
  timestamp, and a **Superseded Result** section (reason + previous plain +
  cached-at) when a replay differed.
- **Replay Session** (`ShellModel.replaySession`, menu item beside Restart
  Sage, no shortcut — V1.12 certifies keys): restarts the worker (replay is
  defined against a fresh namespace, V0.10 semantics), then re-sends every
  row's `sage` in tape order as ONE serial-queue item (a submission typed
  mid-replay queues after it). Per row: preludes recompiled from the
  recorded input (`SessionReplay.preludes` — ambiguous inputs reuse their
  RECORDED resolution, never re-ask), **numeric rows replay with
  `numeric:true`** (the request shape, not just the sage — the V1.8
  SESSION-FORMAT note honored; the replayed `1/3` still shows
  `≈ 0.3333333333` + `= 1/3 exactly`), provenance flips
  `cached → replayed` retaining `cachedAt`, and a differing result
  supersedes via `SessionReplay.difference` (ported verbatim: kind / plain
  / latex / approx / artifact FORMAT SET — **paths never compared**, so a
  deterministic tape incl. plots shows zero spurious supersession; proven
  on screen and against real Sage). `canReplaySession` honestly disables
  the command with no kernel, no rows, or a replay in flight.
- **Remember Sage path — confirmed, not rebuilt:** the V1.3
  `discoveringTransportFactory` already feeds `SageConfigStore.storedPath()`
  into discovery (stored beats known paths); a new test pins the full
  round trip (store → re-read on "relaunch" → discovery selects it).
- **Remember UI layout:** sidebar visibility + selected tab via
  `@AppStorage` (`UILayout` centralizes the keys; the V1.1 "don't persist
  tab" call is REVISITED per the V1.9 spec — the spec wins). The window
  frame needed nothing: SwiftUI `WindowGroup` autosaves it
  (`NSWindow Frame Casette.RootView-…` in defaults — verified live:
  moved/resized → quit → relaunch restores position exactly).

### Gate (all PASS; live verifier round pending)

- `make check` ✓ · **`make test` 278/278** (44 suites; was 249 — +29:
  `SessionStoreTests` ×10 (the v0/10 equivalents against the APP's store:
  save/load round trip incl. all three additive fields, pretty/sorted/
  inspectable file shape + omitted-when-nil `numeric`, missing→fresh,
  empty→fresh, corrupt→quarantine+recover, refused schema leaves the
  future file byte-intact, incremental rewrite leaves no temp files,
  liveness re-resolution (gone → missing, nil path missing, real file
  present), env-injected default directory ×2);
  `SessionReplayTests` ×5 (difference: identical, plain/kind/approx,
  paths-ignored-but-format-set-caught; preludes: friendly `var('t')`,
  bypass none, ambiguous uses the recorded resolution);
  `SessionPersistenceFlowTests` ×9 over fakes (incremental save after
  each completion + relaunch-restores = crash recovery; stale running →
  interrupted on disk; **restore-without-Sage: tape render-ready, all
  marks cached, plot artifacts missing, factory-throw banner, ZERO
  spawns**; restored precision 20 → `config` on the boot wire; header +
  expanded changes reach the file; marks transient incl. edit; replay
  wire order `[bootPrelude, A=…, A.eigenvalues(), var('t'),
  integrate(…), 1/3]` with numeric on exactly the recorded row +
  provenance flips retaining cachedAt + zero supersession + persisted;
  differing replay supersedes keeping the cached envelope + reason;
  refused schema never clobbers through a working session);
  `UILayoutPersistenceTests` ×3 (raw-value vocabulary pinned, fallback,
  defaults round-trip under the production keys);
  KernelSetupTests +1 (sage-doctor.json round trip → discovery selects);
  `PersistenceIntegrationTests` ×1 against REAL Sage 9.5 (record
  `A = matrix([[2,0],[0,3]])` → `A.eigenvalues()` → plot → numeric `1/3`
  with incremental saves; artifacts deleted to model the /tmp-reaped
  relaunch; fresh model restores with Sage not involved — `[3, 2]`
  cached, plot missing, all marks cached; replay in a fresh worker →
  state-dependent row works, marks flip, fresh artifacts at NEW paths
  with NO supersession, numeric display reproduced)).
- **Full V0 regression:** V0.1 **18/18** · V0.2 **35/35** · V0.3 **97/97**
  · V0.5 **88/88** · V0.6 **24/24** · V0.8 **95/95** · V0.7 swift
  **69/69** + e2e **19/19** · V0.9 swift **32/32** · V0.10 swift **21/21**
  (`--no-parallel` per the documented setenv race).
  `pgrep -fl "sage -python|worker.py"` clean.
- **Skills:** swiftui-pro — the provenance tag is plain `Text` (no
  control typography fought), structural conditional with no transition
  (§1.1 precedent), one finding applied: the bare word "cached" is
  cryptic to VoiceOver → full-sentence `accessibilityLabel`; `@AppStorage`
  bindings drive `.inspector`/commands unchanged (no `Binding(get:set:)`);
  no NSView changes (AttributeGraph invariants untouched); no new
  non-scrolling wrapping text (min-height-bomb check). macos-design —
  the tag reads as metadata (timestamp voice), restored tape deliberately
  does NOT shout (V0.10's "quiet" call); Replay Session sits with Restart
  Sage (it IS a restart plus the tape), Title Case, no ellipsis, honest
  disabled states; layout memory via AppStorage + system frame autosave
  (no Settings window, no custom restoration machinery). typography — no
  new tokens; the tag reuses `meta` + tertiary.
- `make build` ✓ (bundled worker.py `cmp` byte-identical) · **scripted
  live gate (osascript keystrokes + menu clicks + `screencapture`, NO
  computer-use):** seeded matrix → eigenvalues → plot → numeric 1/3 (menu
  toggle); file inspected by eye (pretty, sorted, ISO dates, exactly one
  `numeric` key); quit (`pgrep` clean) → deleted the /tmp plot dirs →
  relaunch → **on screen:** all four rows with quiet `cached` tags,
  typeset `[3, 2]`, the plot's honest "Plot image missing — rerun to
  regenerate it" box, History tab + window position restored, Sage ready,
  fresh `2 + 2` evaluates; **Replay Session** → tags flip to `replayed` on
  screen, the sine plot RENDERS again (fresh artifacts), disk shows
  all-replayed with zero supersessions and `numeric:true` intact;
  **kill -9 mid-session** (after `n = 104729`, `n * 2`) → no stray
  processes (worker exits on stdin EOF — PROBLEMS.md bonus note) →
  relaunch restores all 7 rows incl. `n * 2 → 209458`; fresh eval after
  crash-restore works; ⌘B hide → quit → relaunch → sidebar stays hidden,
  tab still History when re-shown; final quit
  `pgrep -fl "Casette|sage -python|worker.py"` clean.

### Known gaps (deliberate)

- `sageVersion` in the header stays nil (the ready banner carries only the
  pid); informational field, additive to fill later (V1.10 has it handy).
- Saves are synchronous on the main actor — right for a calculator tape
  (a few KB; strict ordering for free). If a giant session ever measures
  slow, move encoding off-main then — not before.
- Replay replays the WHOLE tape including rows added this run (it is
  "re-evaluate the session", not "re-evaluate the restored prefix") and
  error rows replay as themselves — honest.
- The quiet tag truncates before the timestamp at extreme narrowness;
  acceptable at the supported min width.
- A restored session whose plot files still exist (same-day relaunch
  before /tmp reaping) renders the actual images — better than the box;
  the liveness re-resolution decides.

### On-screen verifier checklist (V1.9 — pending)

In `build/Casette.app` (real Sage). **Seed:** evaluate
`A = matrix([[2, 0], [0, 3]])` · `A.eigenvalues()` (→ `[3, 2]`) ·
`plot(sin(x), (x, -pi, pi))` (image renders) · toggle **≈ Numeric** ON,
evaluate `1/3` (→ `≈ 0.3333333333` + `= 1/3 exactly`), toggle OFF. Switch
the sidebar to **History**, then move/resize the window memorably.

1. **Quit/relaunch restores the tape:** ⌘Q (then
   `pgrep -fl "Casette|sage -python|worker.py"` → empty; optionally
   `rm -rf /tmp/sagecalc/session-*` to model an aged session). Relaunch →
   all four rows render with their ORIGINAL timestamps: typeset `[3, 2]`,
   the numeric row's `≈` + `= 1/3 exactly`, and each row carries a quiet
   gray `cached` tag beside its timestamp (hover → explanatory tooltip).
2. **Missing plot is honest, not broken:** the plot row shows the quiet
   "Plot image missing — rerun to regenerate it" box with a Rerun button
   (if /tmp was cleared; otherwise the image still renders — also
   correct). Inspector → Artifacts reads Missing.
3. **Restored ≠ frozen:** evaluate `2 + 2` → fresh row, NO tag, Sage
   ready; Symbols shows `t x y z` (boot prelude) but NOT `A` (the
   namespace is honestly fresh — only replay brings state back).
4. **Inspector source:** select a cached row → Evaluation section shows
   "Source: Cached (restored from the last session)".
5. **Replay Session:** Sage ▸ Replay Session → rows re-evaluate top to
   bottom; when done, `A.eigenvalues()` still reads `[3, 2]` (the
   state-dependent row WORKED — A was re-assigned first), every tag flips
   to `replayed`, the plot renders a REAL sine image again, the numeric
   row still shows `≈ 0.3333333333` + `= 1/3 exactly`, and no row shows a
   "Superseded Result" section in the Inspector (deterministic tape — no
   spurious supersession). Symbols now lists `A` again.
6. **Replay marks in the Inspector:** select a replayed row → "Source:
   Replayed (recomputed this session)" + a Replayed timestamp.
7. **Crash recovery:** evaluate `n = 104729` then `n * 2` (→ `209458`);
   in Terminal `kill -9 $(pgrep -x Casette)` → relaunch → EVERYTHING up
   to `n * 2` is back (cached tags), no stray processes before or after.
8. **Mid-eval crash honesty:** evaluate `sleep(60)` and kill -9 while it
   spins → relaunch → that row reads as an orange Interrupted "Casette
   quit before this evaluation finished" — not a spinner.
9. **Layout memory:** hide the sidebar (⌘B), quit, relaunch → window
   frame and the hidden sidebar are back; ⌘B shows it still on History.
10. **The file itself:** open
    `~/Library/Application Support/Casette/sessions/last-session.json` in
    a text editor → pretty-printed, sorted keys, readable
    input/sage/plain per row — a human can audit their session.
11. **Missing Sage still restores (optional):** temporarily rename the
    sage binary; launch → the honest banner shows, but the tape IS
    restored and readable (read-only usefulness), Replay Session is
    disabled. Restore sage afterwards.
12. Quit ⌘Q → `pgrep -fl "Casette|sage -python|worker.py"` → empty.

**Next.** V1.10 — Sage Doctor in app (after the V1.9 live gate passes).

---
