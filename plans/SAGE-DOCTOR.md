# Sage Doctor — Discovery, Checks, JSON Contract, Config (V0.9)

The diagnostic that lets V1 run against a **user-installed** Sage without
bundling it. It discovers Sage, detects its version, drives the canonical worker
end-to-end, and reports status. Built in Swift as a SwiftPM package at
`v0/09-sage-doctor/`: a `SageDoctor` **library** (the surviving artifact, migrates
into the app at V1.10) + a `sage-doctor` **CLI** + swift-testing units for the
pure logic.

This package is **also the first proof that Swift can spawn, drive, interrupt,
and hard-kill `sage -python worker.py`** — a deliberate dry run for V1.3's
`SageKernel`. See PROBLEMS.md ("Swift process control") for the lessons.

---

## Discovery order (priority, highest first)

`SageDiscovery.discover(override:storedPath:)` builds the candidate list in this
fixed order; the **first existing, executable** candidate is selected. Every
candidate (including non-existent ones) is reported so the user sees the full
searched set.

1. **`--sage PATH` override** (`source: override`) — the user explicitly picked a
   binary. An override that **does not exist fails loudly** (it never silently
   falls through to a discovered Sage).
2. **Stored path** (`source: stored`) — a path previously saved via `--use`
   (what the app persists).
3. **Well-known absolute paths** (`source: knownPath`), in this sub-order:
   - `/opt/homebrew/bin/sage` (Apple-Silicon Homebrew — the V1 happy path)
   - `/usr/local/bin/sage` (Intel Homebrew / manual)
   - `/Applications/SageMath.app/Contents/Resources/sage/sage` and `.../sage`
   - conda/mamba prefixes: `~/anaconda3`, `~/miniconda3`, `~/miniforge3`,
     `/opt/anaconda3`, `/opt/miniconda3` (each `.../bin/sage`)
   - **globbed** `/Applications/SageMath*.app` bundles → both
     `Contents/Resources/sage/sage` and the top-level `sage` symlink (the macOS
     installer names bundles `SageMath-9-5.app`, `SageMath-9.2.app`, …).
4. **`which sage`** via the inherited `PATH` (`source: pathLookup`) — last resort.

Duplicates are de-duplicated by expanded path, keeping the **highest-priority**
source. The ordering logic is **pure**: filesystem existence and the `which`
lookup are injected, so it is unit-tested without a real Sage (10 ordering tests).

> Found on this machine: `/usr/local/bin/sage` (live 9.5) is selected;
> `SageMath-9.2.app`'s binaries exist but rank lower (reported, not selected);
> `SageMath-9-5.app` is a known path that contains **no** `sage` binary
> (`exists:false`) — a real searched-but-empty candidate.

---

## Version policy

`sage --version` → `SageMath version 9.5, Release Date: 2022-01-30`. We parse the
first `MAJOR.MINOR` token (tolerant of banner variations), bounded by a 60s
timeout so a hung `--version` can't wedge the doctor.

- **Floor: 9.5** — the version Casette develops and tests against.
- **`supported`**: `>= 9.5` → version check `ok`.
- **`belowFloor`**: `< 9.5` → version check `ok` **with a warning** ("may work,
  untested"). We don't hard-block; the end-to-end worker checks are the real
  fitness test.
- **`unknown`**: no `MAJOR.MINOR` parsed (not a Sage binary, or no output) →
  version check **`fail`** with the captured output as the diagnostic.

---

## The checks (each independent, timed, actionable on failure)

Run by `WorkerCheckRunner` against the canonical worker
(`v0/01-worker-protocol/worker.py`; overridable via `CASETTE_WORKER`). A worker
that won't boot **fails** the boot check and the eval-dependent checks are
reported **`skipped`** (not failed) — the doctor never crashes.

| id | name | what it proves |
| --- | --- | --- |
| `version` | Sage version | `sage --version` parses; standing vs the 9.5 floor |
| `worker_boot` | Worker boot | `sage -python worker.py` spawns and emits the ready banner within the timeout |
| `eval` | Eval test | `2 + 2` → envelope `kind:integer plain:"4"` |
| `state` | State persistence | assign `casette_probe = 42`, read it back across evals |
| `latex` | LaTeX extraction | `sqrt(2)` envelope carries a non-empty `latex` (`\sqrt{2}`) |
| `plot` | Plot generation | `x = var('x')` then `plot(sin(x),(x,-1,1))` → non-empty `artifacts` whose file exists and is non-empty on disk (the `var('x')` prelude is mandatory — PROBLEMS.md) |
| `interrupt` | Interrupt | start `while True: pass`, **SIGINT the real worker pid**, expect an `interrupted` envelope (cysignals). If SIGINT is swallowed, **escalate to a process-group kill** and report that honestly |
| `restart` | Restart | set a var, **hard-kill the process group**, respawn, prove the fresh namespace doesn't know the var (`NameError`) |

`worker_boot` uses a 120s ready timeout for real Sage (cold boot ~2–3s);
`CASETTE_READY_TIMEOUT` shortens it so broken-config proofs fail fast.

---

## JSON report contract (the V1.10 integration boundary)

`sage-doctor --json` emits a `DoctorReport`; V1.10's in-app Sage Doctor pane
decodes **exactly this shape** (or builds it in-process from the library). Fields
are additive going forward; existing fields keep their meaning. `schemaVersion`
gates evolution.

```jsonc
{
  "schemaVersion": 1,
  "sagePath": "/usr/local/bin/sage",          // selected binary, or null
  "versionRaw": "SageMath version 9.5, ...",  // raw --version line, or null
  "versionMajorMinor": "9.5",                 // parsed, or null
  "versionStanding": "supported",             // supported | belowFloor | unknown
  "overallOK": true,                          // selected AND no check failed
  "candidates": [                             // every candidate, priority order
    { "path": "...", "source": "knownPath",   // override|stored|knownPath|pathLookup
      "exists": true, "selected": true }
  ],
  "checks": [
    { "id": "worker_boot", "name": "Worker boot",
      "status": "ok",                         // ok | fail | skipped
      "durationMillis": 2230.4,
      "detail": "ready, worker pid 28862" }   // on FAIL: the actionable message
  ]
}
```

Stable identifiers (`id`) are what V1.10 keys UI off — not the display `name`.
On failure, `detail` is the **actionable one-liner** (what to do), never a stack
trace.

---

## Config storage decision

**A JSON file at `~/Library/Application Support/Casette/sage-doctor.json`** —
not `UserDefaults`.

```json
{ "sagePath": "/usr/local/bin/sage" }
```

Rationale (macos-design conventions): the selected Sage path is **app-managed
state that benefits from being an inspectable, portable, hand-editable file** — a
power user can point Casette at a custom Sage by editing one line; support can ask
"what's in your `sage-doctor.json`?". Application Support is Apple's documented
home for non-document app data. The `SageConfig` is a struct, so V1.10 can add
fields (last-known version, last-verified date) without breaking the format. A
corrupt file degrades to empty (re-discover), never fatal.

- `--use PATH` stores; subsequent runs prefer the stored path (`source: stored`).
- `--forget` removes the file.
- `CASETTE_CONFIG_DIR` relocates the directory — used to keep the V0.9 proof and
  tests hermetic; the app ignores it.

---

## Swift process control (the V1.3 dry run)

`WorkerProcess` + `LineReader` re-prove `controller.py`'s lifecycle in Swift,
applying every PROBLEMS.md process lesson:

- **New session / process group:** `posix_spawn` with `POSIX_SPAWN_SETSID` (the
  Swift equivalent of Python's `start_new_session=True`). `Foundation.Process`
  cannot do this, so we drop to `posix_spawn` with explicit
  `posix_spawn_file_actions` for the stdin/stdout/stderr wiring.
- **Hard-kill the GROUP:** `killpg(getpgid(wrapperPID), SIGKILL)` takes down the
  `sage` bash wrapper *and* the real Python worker it fork-execs, together.
  Killing only the spawned pid (the wrapper) would orphan the worker.
- **SIGINT the REAL worker pid:** the interrupt target is the `pid` in the ready
  banner (the Python worker), not the wrapper. We never reinstall a SIGINT
  handler in the worker, so cysignals stays in charge and the interrupt is prompt.
- **Dedicated reader, single consumer:** `LineReader` drains the worker's stdout
  fd on its own thread into a locked queue; the caller is the sole consumer.
  Each `WorkerProcess` owns exactly one reader, so a killed generation's reader
  can never disturb a fresh worker (the restart-race lesson).
- **Boot-failure teardown:** if the ready banner never arrives (hang at boot), we
  `hardKill()` before returning — so even a never-ready wrapper and its children
  are reaped (proven: the `hang-sage.sh` + `sleep 100000` child leave no orphan).

**Verdict: the V1.3 `SageKernel` risk is retired.** Swift can spawn, drive,
interrupt, and orphan-free kill the worker.

---

## V1.10 integration

- The in-app **Sage Doctor settings pane** decodes the JSON contract above (or
  calls the `SageDoctor` library directly) and renders each check as a row with
  its `ok`/`FAIL`/`skipped` status, duration, and (on failure) actionable detail.
- It reads/writes the selected binary via `SageConfigStore` at the real
  Application Support path — the same store V0.9 uses.
- A "Choose Sage…" file picker writes the chosen path via `--use`/`store`; the
  rest of the app then resolves Sage through the stored config (with the discovery
  fallback if unset).
- V1.3's `SageKernel` reuses the `WorkerProcess`/`LineReader` process-control
  pattern proven here.
