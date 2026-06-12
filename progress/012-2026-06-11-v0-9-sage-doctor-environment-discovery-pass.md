## 2026-06-11 — V0.9: Sage Doctor / environment discovery — PASS (and **Swift can drive the worker — V1.3 risk retired**)

**Did.** Built the Sage Doctor as a Swift SwiftPM package
(`v0/09-sage-doctor/`): a `SageDoctor` **library** (the surviving artifact,
migrates into the app at V1.10) + a `sage-doctor` **CLI** + **32 swift-testing**
pure-logic units. It discovers a user-installed Sage, detects its version against
a 9.5 floor, drives the canonical worker end-to-end, and reports each check
`ok`/`FAIL`/`skipped` with actionable detail (human report + `--json` contract).

**Headline: this is the first proof that Swift — not Python — can spawn, drive,
interrupt, and orphan-free hard-kill `sage -python worker.py`.** All seven
worker checks pass against real Sage 9.5 *from Swift*: boot, eval (`2+2→4`),
state-persistence, LaTeX (`sqrt(2)→\sqrt{2}`), plot (artifacts on disk),
**interrupt (SIGINT to the real banner pid → `interrupted` envelope)**, and
**restart (process-group kill → respawn → fresh namespace `NameError`)**.
**`pgrep` clean after every run, including interrupt/restart and the deliberate
hang-at-boot fixture.** => **The V1.3 `SageKernel` risk is retired.**

**Swift process-control story (the V1.3 dry run).** `Foundation.Process` exposes
no `start_new_session` knob, so `WorkerProcess` drops to **`posix_spawn` with
`POSIX_SPAWN_SETSID`** (the Swift equivalent), wiring stdin/stdout via
`posix_spawn_file_actions`. Hard-kill is `killpg(getpgid(pid), SIGKILL)` (wrapper
+ worker together); interrupt is `kill(realPID, SIGINT)` to the banner pid;
cysignals is left in charge (never reinstall the handler). A dedicated
`LineReader` thread drains stdout (raw `read()` → JSONL → locked queue), with the
control thread the sole consumer (mirrors `controller.py`). Boot-failure
`hardKill()`s before throwing, so a hung wrapper + its children never leak.

**Discovery & config.** Priority search: `--sage` override → stored path →
well-known paths (Homebrew arm/intel, `/usr/local`, **globbed `SageMath*.app`
bundles**, conda prefixes) → `which sage`; all candidates reported, first
existing selected, pure/injectable so it's unit-tested with no Sage. Config is a
JSON file at `~/Library/Application Support/Casette/sage-doctor.json` (`--use`
stores, `--forget` clears; `CASETTE_CONFIG_DIR` keeps the proof hermetic).

**Failure diagnostics — proven by testing broken setups** (each an actionable
one-liner, no stack trace, no orphan): nonexistent `--sage` path (**fails loud**,
doesn't fall through), a non-sage executable (`/bin/ls`), a sage-like script that
hangs at boot, a missing `worker.py`, and a below-floor (9.2) version warning.

**Exit criteria — all met:** manual binary selection ✓ · common paths searched ✓
· version detected ✓ · `sage -python worker.py` works **from Swift** ✓ · useful
failure diagnostics ✓ · configured path stored ✓. No worker regression — V0.9
doesn't touch the worker. `pgrep` clean.

**Learned / surprised.**
- **`Foundation.Process` can't put a child in its own process group** — no
  `setsid`, no pre-exec hook. You must drop to `posix_spawn` +
  `POSIX_SPAWN_SETSID` to get the group-kill semantics the orphan-avoidance
  strategy depends on. (PROBLEMS.md.)
- **An explicit override that doesn't exist will silently fall through** if you
  treat it as just another candidate — `--sage /typo` ran the *real* Sage and
  hid the typo. An explicit override must fail loud. (PROBLEMS.md.)
- **The macOS SageMath app layout is not where you'd guess** — the binary is at
  `Contents/Resources/sage/sage` (plus a top-level `sage` symlink), and the
  `SageMath-9-5.app` here ships **no** `sage` binary at all — a real
  searched-but-empty candidate the discovery report shows honestly.

Frozen in plans/SAGE-DOCTOR.md; Swift process lessons in PROBLEMS.md; full
transcripts in `v0/09-sage-doctor/README.md` (reproduce via `run-proof.sh`).
**Next: V0.10** — session tape persistence-lite.

---
