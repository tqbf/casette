## 2026-06-11 — V1.3: Kernel integration — PASS (live gate PASSED, all 12 checks)

**Live gate (opus verifier, computer-use) — PASS, all 12 checks.** On screen:
boot → "Sage ready" in ~2–4s (worker pids confirmed via pgrep); `2 + 2`→4 with
full Inspector detail (54 ms duration); `1/3 + 1/5`→`8/15` + `≈ 0.5333333333`;
`x = 5` statement then `x + 1`→6 with Symbols showing `x · integer · 5`; `1/0`
→ readable red ZeroDivisionError and status returns to ready; matrix renders +
Actions lists det/rank/rref/…; **interrupt**: `sleep(30)` spinner → ⌘. →
orange KeyboardInterrupt in ~2s, same worker pids survive, `1 + 1`→2;
**restart** ⌘⇧R: Symbols empties, new pids, `x`→NameError, `2*3`→6;
**crash**: `kill -9` the worker → yellow "Sage stopped unexpectedly" banner →
Restart button recovers, `7*7`→49; dark mode legible across
result/error/interrupted rows; worker log has session headers with matching
pids; ⌘Q → `pgrep -fl "sage -python|worker.py"` EMPTY (no orphans).
**Non-blocking polish:** Actions-tab preview footnote truncates at panel
width (wrap it); first click on a sidebar tab occasionally needs a second
click (possible focus/timing artifact — watch in V1.6).

**The app now actually talks to Sage.** Typing raw Sage and pressing Return
boots, evaluates, persists state across evals, renders real envelopes on the
tape, refreshes the live Symbols sidebar, survives crashes visibly, and
restarts intentionally — all proven by 64 swift-testing tests including three
end-to-end suites against real Sage 9.5, plus a real `.app` launch/quit with
zero orphaned workers. **On-screen verification is still pending** (checklist
at the end of this entry).

**Architecture (what got built).**
- **`SageKernel`** (`Sources/Casette/Kernel/`) — the process wrapper, unifying
  v0/09's proven `WorkerProcess` + `LineReader` into one type. `posix_spawn`
  with `POSIX_SPAWN_SETSID` (own process group → orphan-free `killpg`) **plus
  `POSIX_SPAWN_SETSIGDEF`/`SETSIGMASK`** (see the new PROBLEMS.md entry — the
  one genuine new trap this phase). Banner-pid capture (`noteRealPID`) for
  SIGINT targeting; a dedicated reader thread drains stdout into a
  **`WireQueue`** (the extracted, unit-tested JSONL framing + single-consumer
  queue both the real kernel and the test fake share); child stderr appends to
  `~/Library/Application Support/Casette/logs/sage-worker.log` (session header
  per spawn; `KernelLog`) instead of /dev/null, so "why did Sage die?" has an
  answer. Every kernel registers with **`KernelReaper`**;
  `applicationWillTerminate` group-kills anything left, so quitting Casette
  never leaks a worker (proven live: launch → worker up → quit → `pgrep` clean).
- **`SessionController`** — an **actor** (all kernel I/O off the main actor),
  the Swift port of v0/02's `controller.py`. Eight-state machine surfaced
  through `KernelState`; request/response **routing by ID** over the wire
  queue (strays dropped, the single-consumer rule held by actor
  serialization); eval **timeout with SIGINT → hard-kill escalation** (poll +
  `Task.sleep` loop, never a blocking wait, so `interruptCurrent()`/
  `restart()` land mid-eval); **generation counter** guards every loop and the
  EOF callback (the V0.2 restart-race lesson, in Swift); boot awaits the ready
  banner and **hard-kills before reporting** a hang (the V0.9 lesson). Worker
  death is event-driven (EOF callback → `.crashed` even while idle). State +
  honest issue text stream to the UI over one `AsyncStream<KernelStatus>`.
  Transports come from an injected **factory** (one fresh transport per
  generation); the default factory does V0.9 discovery (stored
  `sage-doctor.json` → Homebrew → /usr/local → `SageMath*.app` glob → conda →
  PATH; `SageDiscovery`/`SageConfigStore` lifted verbatim from v0/09) and
  locates the bundled worker (`WorkerScriptLocator`, with a loud-failing
  `CASETTE_WORKER_PATH` override for tests/dev).
- **State-machine policy decisions:** SIGINT-honored timeout → `.timedOut`
  (worker survived, `canAcceptWork`); escalated hard kill → **`.crashed`**
  with an issue explaining the force-stop (honest: the worker is GONE, and
  the recovery banner offers Restart — V0.2 left this state ambiguous).
  Outcomes the worker never produced (crash, force-stop, kernel-unavailable)
  get **synthetic error envelopes** parent-side so rows stay readable and
  self-describing when persisted (`Evaluation.result` is never nil in
  practice). Refused evals (no kernel) are explicit error rows, not
  forever-pending spinners.
- **UI wiring.** `ShellModel.connectKernel()` attaches the controller, watches
  the status stream (`kernelState` + `kernelIssue`), and submits through a
  **chained task queue** so rapid submissions evaluate strictly in tape order
  against the one namespace (restart/interrupt are deliberately NOT chained —
  they're the escape hatches). Submit → pending row (the legitimate spinner!)
  → `complete(rowID:with:)` via the frozen `EnvelopeMapping` → real
  plain/`≈ approx`/error rendering (V1.2's tape needed zero changes). After
  every eval the **real `symbols` op** refreshes the sidebar (it was cheap —
  ~1ms — so V1.6's data is live early; `SymbolSnapshot(workerResponse:)`).
  Kernel state is visible in a small dot+label **status indicator** in the
  input pane (text differs per state, not color-only; tooltip carries the
  machine state); kernel problems render as a **banner** above the input pane
  with the message + a Restart Sage button; a new **Sage menu** carries
  Interrupt Evaluation (⌘.) and Restart Sage (⌘⇧R), enabled honestly.
  `RootView` starts with an EMPTY session (placeholder seeding removed — the
  tape is real now; `PlaceholderData` survives for previews/tests).
- **worker.py bundling:** `build.sh` copies `v0/01-worker-protocol/worker.py`
  (the canonical worker, untouched) into `Casette.app/Contents/Resources/`
  at assembly — byte-identical by construction (verified with `cmp` at the
  gate), single source of truth, no fork.

**Gate.** `make check` ✓ · `make test` **64/64** (suites: WireQueue framing ·
SessionController state machine/routing/escalation over a scripted
`FakeKernelTransport` · ShellModel kernel wiring incl. strict eval ordering ·
kernel setup (loud override failure, discovery priority) · the V1.2 suites
unchanged · **SageKernel integration vs real Sage 9.5**: full journey
(boot → `2+2` → `1/3+1/5` exact+approx → `x=5`→`x+1`→`6` → `1/0`
ZeroDivisionError → live symbols → interrupt honored → worker survives →
restart → `NameError` → clean shutdown), timeout-honored → `.timedOut`, and
the SIG_IGN runaway hard-kill + recovery) · `make build` ✓ with **bundled
worker.py byte-identical** ✓ · launched `build/Casette.app` via `open`: alive
12s+ with wrapper+worker visible, quit via AppleScript → **zero stray
processes** ✓. **Full V0 regression, all green:** V0.1 **18/18** · V0.2
**35/35** · V0.3 **97/97** · V0.5 **88/88** · V0.6 **24/24** · V0.7 **69/69 +
e2e 19/19** · V0.8 **95/95** · V0.9 **32/32 + live doctor run all-ok** · V0.10
**21/21 + casette-tape 22/22**. `pgrep -fl "sage -python|worker.py"` clean
after everything.

**Learned / surprised (the headline → PROBLEMS.md).**
- **`posix_spawn` children inherit the parent's signal dispositions/mask** —
  under the swift-testing runner the worker started with SIGINT ignored, so
  cysignals never fired and every interrupt escalated to a hard kill, while
  the identical v0/09 code passed from its CLI parent. Fix:
  `POSIX_SPAWN_SETSIGDEF` + `POSIX_SPAWN_SETSIGMASK` at spawn. The v0/09
  proof was right; its *parent context* was an untested variable.
- The blocking `NSCondition` waits in v0/09's `WorkerProcess` could not move
  into an actor (a blocked actor can't receive `interrupt()`/`restart()`).
  The poll + `Task.sleep` slice loop — controller.py's exact shape — is what
  keeps the actor responsive without violating the single-consumer rule.
- `AsyncStream` buffers values yielded before iteration starts (unbounded
  default), so the status stream can be consumed late without losing the
  boot transitions.

**Skill reviews applied.**
- **swiftui-pro:** modern concurrency throughout (actor + `AsyncStream`, no
  GCD, `Task.sleep(for:)`); `@ObservationIgnored` on the model's task
  handles; `[weak self]` + per-iteration strong capture in the status loop;
  logic lives on the model/controller (testable), not in `body`/`task`
  closures; direct `action:` parameters where possible. Accepted, documented
  deviation: `SageKernel`/`WireQueue`/`KernelReaper` are lock-guarded
  `@unchecked Sendable` classes — the proven reader-thread pattern from
  v0/09; an actor cannot own a blocking `read()` loop.
- **macos-design:** ⌘. for interrupt (the system cancel convention) and ⌘⇧R
  in a proper app menu (discoverable, honestly disabled); status indicator
  differs by text, never color alone; the recovery banner is an Xcode-style
  tinted strip with the single relevant action; no new chrome. Banner
  insert/remove is deliberately NOT animated (SWIFTUI-RULES §1.1 trumps the
  every-state-change-animates guidance).
- **typography-designer:** not run — no new type styles; the status/banner
  reuse `Theme.Fonts.meta` per the existing two-axis scale.

**Known gaps (deliberate, per plan).**
- Friendly compiler not wired (V1.4): everything is `CompiledInput.bypass`,
  so `factor x^4 - 1` evaluates as literal (broken) Sage — type raw Sage.
- LaTeX renders as plain text (V1.5); plots show the placeholder box, not the
  PNG (V1.7) — the artifacts ARE saved and the envelope carries them.
- Tracebacks not yet behind a disclosure (V1.5) — Inspector shows error type.
- No ⌘./⌘⇧R *keyboard pass* polish or per-request numeric/precision flags
  (V1.8) — the controller API has room for them (eval request dict).
- Eval timeout is 120s (constant in `SessionController.Configuration`); no
  user-facing setting yet.

**Live gate (PENDING — on-screen verifier checklist).**
1. Launch `build/Casette.app`. Status indicator (bottom-right of input pane)
   reads "Starting Sage…" then **"Sage ready"** (green dot) within ~15s.
   Everything V1.1/V1.2 verified should still hold (layout, ⌘B, focus,
   selection → Inspector/Actions, dark mode).
2. Type `2 + 2` ⏎ → row may flash "Evaluating…" + spinner, then shows **4**.
   Inspector for the row shows Kind integer, Duration, Generated Sage.
3. `1/3 + 1/5` ⏎ → **8/15** with secondary line **≈ 0.5333333333**.
4. `x = 5` ⏎ (statement → input echo only, no result line), then `x + 1` ⏎ →
   **6** (state persists). Symbols tab now lists `x · integer · 5` (live!).
5. `1/0` ⏎ → red **ZeroDivisionError** row, "rational division by zero";
   status indicator back to "Sage ready" (the worker survived).
6. `matrix([[1,2],[3,4]])` ⏎ → multi-line plain matrix text; Actions tab for
   it lists det/rank/rref/… (labels only).
7. **Interrupt:** type `sleep(30)` ⏎ (or `while True: pass`), watch status
   read "Working…", then **Sage ▸ Interrupt Evaluation (⌘.)** → the row turns
   orange "Interrupted" within ~1s and "Sage ready" returns. Then `1 + 1` ⏎ →
   2 (worker survived).
8. **Restart:** **Sage ▸ Restart Sage (⌘⇧R)** → status flicks "Starting
   Sage…" then ready; Symbols tab EMPTIES; `x` ⏎ → red **NameError** (the
   reset is intentional and visible).
9. **Crash visibility:** in Terminal,
   `pgrep -fl worker.py` → `kill -9 <python3 worker pid>` → within ~a second
   the yellow banner appears: "Sage stopped unexpectedly. Restart Sage to
   continue (variables will be reset)." with a **Restart Sage** button; the
   status dot reads "Sage stopped" (red). Click Restart Sage → ready again,
   evals work.
10. Quit (⌘Q). In Terminal: `pgrep -fl "sage -python|worker.py"` → **no
    output** (no orphaned workers — the reaper did its job).
11. Worker log exists and has session headers:
    `cat ~/Library/Application\ Support/Casette/logs/sage-worker.log`.

**Next.** V1.4 — input pane v1: wire the real `FriendlyCompiler` (v0/07) in
front of `CompiledInput`, multiline/history/⌘-Return input behaviors, and the
generated-Sage disclosure.

---
