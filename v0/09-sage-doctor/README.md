# V0.9 — Sage Doctor / Environment Discovery

Proves **V1 can use a user-installed Sage without bundling it**: a diagnostic
that finds Sage, drives the canonical worker end-to-end, and reports status —
each check `ok`/`FAIL`/`skipped` with actionable detail.

It is **also the first proof that Swift (not Python) can spawn, drive, interrupt,
and hard-kill `sage -python worker.py`** — the V1.3 `SageKernel` dry run. The
PROBLEMS.md process lessons are re-proven in Swift: new session / process group
(`POSIX_SPAWN_SETSID`), hard-kill the **group** (`killpg`), SIGINT the **real
worker pid** from the ready banner, dedicated stdout reader.

Full design: [`../../plans/SAGE-DOCTOR.md`](../../plans/SAGE-DOCTOR.md).

## Layout

```
Sources/SageDoctor/        the SURVIVING library (migrates into the app at V1.10)
  SageDiscovery.swift      priority path search (pure; injectable probes)
  SageVersion.swift        version parse + the 9.5-floor support policy
  SageConfigStore.swift    JSON config at ~/Library/Application Support/Casette/
  WorkerProcess.swift      Swift spawn/drive/interrupt/kill of the worker
  LineReader.swift         dedicated stdout reader (JSONL -> queue, EOF)
  WorkerCheckRunner.swift  the end-to-end checks (boot/eval/state/latex/plot/
                           interrupt/restart)
  DoctorReport.swift       the V1.10 JSON contract structs
  ReportFormatter.swift    human report + --json (pure)
  SageDoctor.swift         orchestrator: discover -> version -> checks -> report
Sources/sage-doctor/       the CLI
Tests/SageDoctorTests/     32 swift-testing units (pure logic only)
fixtures/                  broken-config fixtures (hang-at-boot, old-version)
run-proof.sh               reproducible full proof driver (transcripts below)
```

## Run

```bash
swift test                       # 32 pure-logic units
swift run sage-doctor            # full diagnostic, human report
swift run sage-doctor --json     # the V1.10 JSON contract
swift run sage-doctor --sage /path/to/sage   # test a specific binary
swift run sage-doctor --use /path/to/sage    # store it, then run
swift run sage-doctor --forget   # clear the stored path
./run-proof.sh                   # everything below, reproducibly
```

---

## Transcript — full doctor against real Sage (all checks ok)

```text
Sage path: /usr/local/bin/sage
Sage version: 9.5
Worker boot: ok  (ready, worker pid 27778)
Eval test: ok  (2 + 2 = 4)
State persistence: ok  (assign then read back == 42)
LaTeX extraction: ok  (sqrt(2) -> \sqrt{2})
Plot generation: ok  (2 artifact(s), e.g. /tmp/sagecalc/session-27778-fc9d0122/plot-00001.svg)
Interrupt: ok  (SIGINT to real pid honored -> interrupted envelope)
Restart: ok  (group-killed, respawned, fresh namespace (NameError as expected))

All checks passed.
```

`--json` (the V1.10 contract; abridged — see `run-proof.sh` for the full dump):

```json
{
  "schemaVersion" : 1,
  "sagePath" : "/usr/local/bin/sage",
  "versionRaw" : "SageMath version 9.5, Release Date: 2022-01-30",
  "versionMajorMinor" : "9.5",
  "versionStanding" : "supported",
  "overallOK" : true,
  "candidates" : [
    { "path":"/opt/homebrew/bin/sage", "source":"knownPath", "exists":false, "selected":false },
    { "path":"/usr/local/bin/sage",    "source":"knownPath", "exists":true,  "selected":true  },
    { "path":"/Applications/SageMath-9.2.app/Contents/Resources/sage/sage", "source":"knownPath", "exists":true, "selected":false },
    ...
  ],
  "checks" : [
    { "id":"version",     "name":"Sage version",       "status":"ok", "detail":"9.5" },
    { "id":"worker_boot", "name":"Worker boot",        "status":"ok", "detail":"ready, worker pid 28862", "durationMillis":2230.4 },
    { "id":"eval",        "name":"Eval test",          "status":"ok", "detail":"2 + 2 = 4" },
    { "id":"state",       "name":"State persistence",  "status":"ok", "detail":"assign then read back == 42" },
    { "id":"latex",       "name":"LaTeX extraction",   "status":"ok", "detail":"sqrt(2) -> \\sqrt{2}" },
    { "id":"plot",        "name":"Plot generation",    "status":"ok", "detail":"2 artifact(s), e.g. /tmp/.../plot-00001.svg" },
    { "id":"interrupt",   "name":"Interrupt",          "status":"ok", "detail":"SIGINT to real pid honored -> interrupted envelope" },
    { "id":"restart",     "name":"Restart",            "status":"ok", "detail":"group-killed, respawned, fresh namespace (NameError as expected)" }
  ]
}
```

Discovery found `/usr/local/bin/sage` (the live Sage 9.5) plus the
`SageMath-9.2.app` bundle binaries — which **exist but rank lower**, so they are
reported and not selected. The `SageMath-9-5.app` bundle is a known path that
**does not** contain a `sage` binary (`exists:false`) — a real-world example of a
searched-but-empty candidate.

**Orphan check after the full run (incl. interrupt + restart): clean.**

```text
$ pgrep -fl "sage -python" ; pgrep -fl worker.py ; pgrep -fl /usr/local/bin/sage
(no sage -python)
(no worker.py)
(no sage wrapper)
```

---

## Transcript — broken-config diagnostics (proven by testing broken setups)

Each produces a **clear, actionable message — never a stack trace** — and leaves
**no orphans**. (Broken cases run with `CASETTE_READY_TIMEOUT=4` so the boot-hang
fails fast.)

**A — nonexistent `--sage` path** (fails loud, does NOT silently fall through to
a discovered Sage — the user asked for that binary):

```text
Sage path: (none found)
Sage version: (unknown)  [WARNING: version unrecognized]
Discovery: FAIL — the --sage path you gave (/no/such/sage) does not exist or is not executable. Check the path, or omit --sage to auto-discover
```

**B — a non-Sage executable (`/bin/ls`)**:

```text
Sage path: /bin/ls
Sage version: ls: unrecognized option `--version' ...  [WARNING: version unrecognized]
Worker boot: FAIL — worker never sent its ready banner within 4.0s
Eval test: skipped — skipped: worker did not boot
...
```

**C — a sage-like script that hangs at boot** (`fixtures/hang-sage.sh`: answers
`--version`, then `sleep 100000` instead of emitting the ready banner — and forks
a child to mirror the wrapper→worker tree):

```text
Sage path: .../fixtures/hang-sage.sh
Sage version: 9.5
Worker boot: FAIL — worker never sent its ready banner within 4.0s
...
orphan check: clean (no sage/worker/fixture processes)
```

The boot-timeout path **process-group-kills** the hung wrapper *and* its
`sleep 100000` child together — the exact orphan trap from PROBLEMS.md, proven
solved in Swift.

**D — a `worker.py` path that doesn't exist** (`CASETTE_WORKER=/no/such/worker.py`):

```text
Worker boot: FAIL — worker script not found at /no/such/worker.py (set CASETTE_WORKER to its path)
Eval test: skipped — skipped: worker script missing
...
```

**E — a below-floor version (9.2)** — the version warning band:

```text
Sage version: 9.2  [WARNING: below tested floor 9.5]
```

---

## Transcript — config persistence

```text
$ sage-doctor --use /usr/local/bin/sage
Stored Sage path: /usr/local/bin/sage
  (file: ~/Library/Application Support/Casette/sage-doctor.json -> {"sagePath":"/usr/local/bin/sage"})

$ sage-doctor --json | jq '.sagePath, (.candidates[] | select(.selected) | .source)'
"/usr/local/bin/sage"
"stored"                # subsequent run prefers the stored path

$ sage-doctor --forget
Forgot stored Sage path (...).   # file removed
```

(The proof uses `CASETTE_CONFIG_DIR` to keep the config hermetic; the real app
uses `~/Library/Application Support/Casette/sage-doctor.json`.)

---

## Exit criteria — all met

| Criterion | Evidence |
| --- | --- |
| User can select Sage binary manually | `--sage PATH` override (highest priority); `--use PATH` stores it |
| Common install paths searched | Homebrew (arm/intel), `/usr/local`, `SageMath*.app` bundles (globbed), conda prefixes, `which sage` — in documented priority order; all reported |
| Version detected | `sage --version` parsed to `9.5`; 9.5 floor with a below-floor warning band |
| `sage -python worker.py` works (**from Swift!**) | boot/eval/state/latex/plot/interrupt/restart all `ok` driving the real worker |
| Failure diagnostics useful | the five broken cases above, each an actionable one-liner, no stack trace |
| Configured path can be stored | `--use` / `--forget`, JSON at Application Support, subsequent run prefers stored |
| No orphaned Sage processes | `pgrep` clean after every run, incl. interrupt/restart and the hang-at-boot case |
