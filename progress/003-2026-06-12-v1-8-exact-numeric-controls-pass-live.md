## 2026-06-12 — V1.8: Exact/numeric controls — PASS (live gate PASSED across two rounds)

**Live gate (opus verifier, computer-use) — PASS, all 14 checks.** Round 1
verified 12/14 on screen: default exact (`8/15` + exactly-10-digit ≈),
Approximate Numerically → fresh selected `.n()` row, precision menu 20 →
zoom-counted 20 digits → back to 10, restart keeps precision AND
`expand((x+1)^2)` immediately after restart works (the chained re-init race
fix), numeric toggle (pressed state + menu checkmark, decimal hero +
`= 1/3 exactly`), namespace purity on screen (`parent(y)` → Rational Field),
toggle-off exact again, Copy Approximation / Copy Exact Value via pbpaste
(contextually swapped — nice), dark mode, min-width layout, no min-height
balloon, clean exit. Round 1 reported a "blocking" tab-bar defect (clicks
opening System Settings → Time Machine) — round 2 PROVED it a verifier
environment artifact (their System Settings window from the dark-mode toggle
overlapped Casette's tab strip and swallowed the clicks; with it closed, all
four tabs switch perfectly). Round 2 completed the two blocked checks:
Inspector shows Exact Value `1/3` on the numeric row, and History Rerun
reproduces the row's recorded numeric flag with the toggle OFF. **Checklist
correction:** the checklist expected "Exact: No" on a force-numeric rational;
the app shows "Exact: Yes" — the app is right (it faithfully displays the
frozen V0.8 envelope's `exact` flag for the underlying rational; the
checklist, not the app, was wrong). **Verifier-environment lesson recorded:**
on-screen verifiers must close System Settings after appearance toggles —
an overlapping window reads as phantom app defects.

**Exactness is now a product feature, not a Sage weirdness.** The default
display was already the V0.8 contract (exact primary, `≈ approx` secondary —
verified intact); V1.8 adds the CONTROLS: a sticky **"≈ Numeric" toggle** in
the input pane (mirrored as a checked **Numeric Results** item on the Sage
menu), a session-scoped **precision menu** ("10 digits" → 5/10/15/20/30/50)
wired to the worker `config` op and **re-applied after restart** like the
boot prelude, an **Approximate Numerically** one-click affordance on the
card's context menu (a real `(expr).n()` tape row), copyable ≈/exact lines,
and the preserved exact form (`= 1/3 exactly`) on every force-numeric card +
an Exact Value field in the Inspector.

### The controls and their scope semantics (the design decisions)

- **Numeric mode is a sticky, always-visible toggle, scoped to TYPED
  submissions only.** macos-design call: a per-submit modifier key is
  invisible state; a pressed accent `Toggle(.button)` next to the input IS
  the scope indicator (and the Sage-menu checkmark always agrees — same
  model flag). While on, each draft submission sends the V0.8 per-request
  `numeric:true` — display-only, worker-guaranteed namespace purity — and
  the row records it (`SessionRow.numeric`, the ONE additive schema field,
  documented in SESSION-FORMAT.md like `truncation`/`error` were). Sidebar
  flows (inspect/forget/actions) are NEVER numeric in either toggle state;
  **rerun reproduces the original row's recorded flag**, not the toggle's
  current state. The exit criterion "numeric mode does not pollute global
  behavior accidentally" is structural: per-request wire flag + visible
  sticky state + per-row honesty (`≈ 0.3333333333` hero with `= 1/3
  exactly` under it — the force-numeric card can't be mistaken for a float).
- **Precision is a SESSION control, deliberately NOT a Settings window.**
  It's worker session state (the `config` op's `precision_digits`, default
  10, recorded in the session header's `precisionDigits` — in the schema
  since V0.10, now actually driven), so it lives next to the input where
  its effect appears, not in app preferences. `ShellModel.setPrecision`
  updates the header and queues the `config` op on the serial kernel queue
  (a precision change never reorders ahead of submitted work); boot/restart
  re-apply it whenever it differs from the worker default 10 (a fresh
  worker silently resets — V0.8 session state). V1.9 persists + restores it
  with the session; a restored non-standard value is injected into the
  menu's choices so the control never shows blank.
- **"Approximation is one click away", honestly:** for every constant exact
  result the approximation is already ZERO clicks (the ≈ secondary line,
  now right-click-copyable on the line and the row). The new context-menu
  **Approximate Numerically** (shown exactly when the envelope offers the
  `approx` action and the row has a reusable expression —
  `SessionRow.approximateCommand`) evaluates the same stateless
  `(expr).n()` command the Actions tab builds, as a fresh SELECTED row.
  Kinds where approximation makes no sense (matrix, list, error) honestly
  offer nothing.
- **Force-numeric cards render `plain`, never `latex`:** the worker's
  numeric envelope keeps the EXACT form's LaTeX (it computes latex before
  re-presenting the echoed value), so the old hero path would have typeset
  `≈ 1/3` over a decimal `plain`. `ResultHeroView` now branches on
  `exactValue != nil` → mono decimal hero `≈ 0.3333333333` + the
  `= 1/3 exactly` secondary (value in the mono Sage voice, "exactly" as a
  chrome word at the meta scale — no new type tokens).

### Kernel API changes (wire shapes per WORKER-PROTOCOL.md; worker.py untouched)

- `SessionController.evaluate(_:numeric:precisionDigits:)` — additive
  defaulted parameters; a plain eval's wire shape is byte-identical to
  V1.3's (`numeric`/`precision_digits` keys appear only when asked).
- `SessionController.configure(precisionDigits:) async -> Bool` — the
  session `config` op (send + poll with the metadata timeout, single-
  consumer discipline preserved); reports the worker's accept/reject.
- **`restartKernel` re-architected (a latent race the gate caught):** the
  `restart()` call stays un-chained (it must preempt a stuck eval) but the
  re-init (boot prelude + precision re-apply + symbols refresh) now rides
  the serial kernel queue awaiting it — a submission typed right after ⌘⇧R
  deterministically evaluates AFTER the fresh worker is initialized. The
  pre-existing flake it fixed ("expand((x+1)^2) → NameError right after
  restart") and the rules are in PROBLEMS.md ("Restart re-init must
  CHAIN…").

### Gate (all PASS; live gate pending)

- `make check` ✓ · **`make test` 249/249** (39 suites; was 236 — +13:
  `ExactNumericTests` ×10 over the fake transport (eval wire shape sends
  the V0.8 fields only when asked; `config` op shape + accept/reject +
  no-kernel; numeric-mode scope: flag on the wire AND the row, off after
  toggle, never on sidebar flows in either toggle state, rerun reproduces
  the recorded flag; setPrecision header+config in queue order, no-op/
  invalid guarded; boot-at-default sends NO config, restart re-applies a
  changed precision across worker generations; approximateNumerically →
  fresh selected row + draft untouched + no-approx-action rows offer
  nothing; `SessionRow.numeric` Codable round-trip incl. omitted-when-nil
  + legacy decode), `ExactNumericIntegrationTests` ×3 against REAL Sage
  9.5 (the V0.8 harness cases through the app's seams: `y = 1/3` →
  numeric eval → decimal primary + `exact_value` "1/3" + next plain `y`
  exact again + `parent(y)` = Rational Field + per-request 5-digit
  override leaves the session at 10; config 20 →
  `0.53333333333333333333` and sqrt(2) to 20 digits → back to 10, 0
  rejected; the full model journey: toggle scope, precision through the
  UI seam, restart re-applies 20 — proven via a sentinel symbol so the
  restart pipeline is OBSERVABLY complete — and the card's one-click
  `(1/3 + 1/5).n()` row)).
- **Full V0 regression:** V0.1 **18/18** · V0.2 **35/35** · V0.3 **97/97**
  · V0.5 **88/88** · V0.6 **24/24** · V0.8 **95/95** · V0.7 swift **69/69**
  + e2e **19/19** · V0.9 swift **32/32** · V0.10 swift **21/21** (run
  `--no-parallel` per the documented setenv race).
  `pgrep -fl "sage -python|worker.py"` clean.
- **Skills:** swiftui-pro — bindings are real (`@Bindable` +
  `$model.numericMode` / the computed `$model.precisionDigits`, no
  `Binding(get:set:)` in body), controls keep their system typography
  (§5.1), the glyph-labeled toggle carries an `accessibilityLabel`
  ("Numeric results"), context menus on actionable rows, no new
  non-scrolling wrapping text (the min-height-bomb check), no NSView
  changes (AttributeGraph invariant untouched). macos-design — session
  state controlled AT the session surface (input pane, beside the kernel
  status), not a Settings window; sticky pressed-button state as the scope
  indicator; menu mirror for discoverability; NO keyboard shortcut
  advertised for the new controls (V1.12 certifies keys; PROBLEMS.md
  "never advertise a key unverified"). typography-designer — no new
  tokens; the one new line reuses `resultSecondary` (mono value) + `meta`
  ("exactly" chrome word), per the frozen two-axis system.
- `make build` ✓ (bundled worker.py `cmp` byte-identical) · launched
  `build/Casette.app` via `open`: alive 14s with exactly ONE worker chain,
  AppleScript quit → `pgrep -fl "Casette|sage -python|worker.py"` clean.

### Known gaps (deliberate)

- The precision menu offers fixed choices (5/10/15/20/30/50 + the current
  value when restored non-standard); a free-form digits field is later
  polish if ever needed.
- "Approximate Numerically" uses `.n()` at Sage's default 53-bit precision
  (the frozen V1.6 Actions-tab command), NOT the session digits — the
  session digits drive the envelope's `≈` line. Visible and editable
  before evaluating, like every action command.
- Numeric mode doesn't re-render EXISTING rows (each row keeps the display
  it was evaluated with — deliberately: rows are honest records, and the
  recorded `numeric` flag is what V1.9's replay reproduces).
- A non-constant symbolic row (e.g. `x^2 + 5*x + 6`) still offers
  Approximate Numerically (the worker lists `approx` for all symbolic);
  evaluating it yields a readable TypeError row — honest, visible, cheap.
- No keyboard shortcut for the toggle yet (V1.12 keyboard pass).

### On-screen verifier checklist (V1.8 — pending)

In `build/Casette.app` (real Sage), verify on screen:

1. **Default exact:** evaluate `1/3 + 1/5` → typeset `8/15` hero with
   `≈ 0.5333333333` (exactly 10 digits) beneath it. `sqrt(2)` → radical
   hero + `≈ 1.414213562` line.
2. **One-click approx:** right-click the `8/15` row → menu shows Copy
   Approximation (→ `pbpaste` = `0.5333333333`) and **Approximate
   Numerically**; click the latter → a FRESH row `(1/3 + 1/5).n()`
   evaluates at the tape end showing `≈ 0.533333333333333`, SELECTED
   (Inspector follows it). The original `8/15` row is untouched.
3. **No approx where it makes no sense:** evaluate `matrix([[1,2],[3,4]])`
   → its context menu offers neither Copy Approximation nor Approximate
   Numerically.
4. **Precision to 20:** click the input-pane "10 digits" menu → choose
   "20 digits" → evaluate `1/3 + 1/5` → `≈ 0.53333333333333333333`
   (20 digits). `sqrt(2)` → `≈ 1.4142135623730950488`.
5. **Back to 10:** choose "10 digits" → `1/3 + 1/5` → `≈ 0.5333333333`.
6. **Numeric toggle ON:** click "≈ Numeric" (button reads pressed/accent;
   Sage menu → Numeric Results shows a checkmark). Evaluate `1/3` → hero
   `≈ 0.3333333333` with the secondary line `= 1/3 exactly`; the
   Inspector for that row shows Kind `rational`, Exact `Yes`, and an
   **Exact Value** field `1/3`. Row context menu → Copy Exact Value →
   `pbpaste` = `1/3`.
7. **Namespace purity on screen:** with the toggle still ON, evaluate
   `y = 1/3` (statement row), then `parent(y)` → `Rational Field`;
   Symbols tab lists `y · rational · 1/3` — the stored value stayed exact
   through a numeric-mode assignment.
8. **Toggle OFF → exact again:** click "≈ Numeric" off (button
   un-presses, menu checkmark clears) → evaluate `1/3` → plain `1/3` hero
   with `≈ 0.3333333333` secondary — the very NEXT eval is exact; nothing
   global changed.
9. **Rerun honesty:** History tab → right-click the NUMERIC `1/3` row →
   Rerun → the fresh row is numeric again (`≈ 0.3333333333` +
   `= 1/3 exactly`) even though the toggle is now off.
10. **Restart re-applies precision:** set 20 digits, evaluate `1/3 + 1/5`
    (20-digit ≈), then Sage → Restart Sage (menu item; ⌘⇧R doesn't fire
    through the MCP key tool — V1.7 harness note). After "Sage ready" +
    Symbols shows `t x y z`, evaluate `1/3 + 1/5` →
    `≈ 0.53333333333333333333` STILL 20 digits (the menu still reads
    "20 digits").
11. **Immediately-after-restart ordering (the race fix):** restart again
    and, as soon as the input accepts typing, submit `expand((x+1)^2)` →
    `x^2 + 2*x + 1` with NO NameError (the re-init is queue-ordered ahead
    of it).
12. **Dark mode:** the toggle's pressed state, the precision menu, the
    `= 1/3 exactly` line, and the Inspector's Exact/Exact Value fields
    all legible in dark mode.
13. **Layout:** at the window's minimum width with the sidebar open, the
    input pane still shows editor + controls + status without clipping;
    clicking either control never steals keyboard focus from the editor
    (typing continues immediately).
14. Quit ⌘Q → `pgrep -fl "Casette|sage -python|worker.py"` → empty.

**Next.** V1.9 — session persistence (after the V1.8 live gate passes).

---
