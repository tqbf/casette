## 2026-06-11 — V1.1: App skeleton & layout — PASS

**Did.** Replaced the hello-world `ContentView` with the real three-region
shell in `Sources/Casette/` (18 source files, one type per file):

- **Layout container:** the main content is `VStack { SessionTapeView /
  Divider / InputPaneView }` with the tabbed sidebar attached as a macOS-14
  **`.inspector(isPresented:)`** — the modern idiom for a right-side
  inspector-style panel (full height like Xcode/Keynote, system resize handle
  via `inspectorColumnWidth(min: 240, ideal: 280, max: 400)`). Toggle =
  toolbar button (`sidebar.trailing`, `.primaryAction`) **plus** a proper
  View-menu item carrying **⌘B**, wired through
  `FocusedValues`/`@FocusedBinding` (`SidebarToggleCommands`) so it's
  discoverable in the menu bar and disabled with no window focused.
- **Session tape:** `ScrollView` + `LazyVStack`, `defaultScrollAnchor(.bottom)`
  (calculator-tape semantics) + `ScrollViewReader` follow-append. Rows render
  input echo + timestamp over a result that switches on shape: value (+ the
  V0.8 `≈ approx` secondary line), statement (no output), error
  (type + message in red), plot (placeholder thumbnail box — V1.7 renders the
  real PNG), not-evaluated. Selection (tap) drives Inspector/Actions tabs;
  hover/selected backgrounds per SWIFTUI-RULES §7.2; context menus copy
  input / generated Sage / result / LaTeX (all real, nothing stubbed).
- **Sidebar tabs:** segmented control (Xcode-inspector style) over Symbols
  (name/kind/summary rows), History (newest first; double-click or
  context-menu **Insert into Input** — genuinely sets the draft + refocuses
  input), Inspector (grouped `Form` of the envelope fields: kind, plain,
  approx, LaTeX, raw input, generated Sage, duration, time), Actions (the
  per-kind `actions` list, rendered as labels not stubbed buttons, with an
  honest "runs once Sage is connected" footer). Every tab has a designed
  `ContentUnavailableView` empty state.
- **Focus model:** root-owned `@FocusState` + `.defaultFocus($isInputFocused,
  true)` + a `.task` fallback — input owns keyboard focus on launch; sidebar
  insert hands focus back via a `focusInput` closure.
- **Placeholder data (`PlaceholderData`):** 11 product-shaped rows (integer,
  rational + approx, symbolic, assignments, friendly-compiled `factor x^4-1`,
  long polynomial, eigenvalues list, solve, plot, `1/0` error) with faithful
  kinds/LaTeX/actions from the frozen contracts; 4 symbols matching the
  worker `symbols` op shape. `ShellModel` (`@Observable @MainActor`) is the
  V1.2/V1.3 seam: rows, symbols, selection, draft, `submitDraft()` (appends
  an honest `.notEvaluated` row — no kernel until V1.3).
- **Theme (`Theme` enum):** centralized metrics (8-grid) + a two-axis type
  system — semantic styles only for scale (caption/callout/body/title3),
  monospaced design reserved for math/Sage content, weight carries emphasis
  (medium result hero, semibold symbol names), de-emphasis via
  .secondary/.tertiary. Dark mode is free (semantic styles/materials only;
  input pane on `.bar`, inspector gets system material).

**Gate.** `make check` ✓ · `make test` **9/9** (new ShellModel +
PlaceholderData suites) · `make build` ✓ (ad-hoc signed, verifies) · launched
the .app twice, alive 16s+ (constraint crashes fire in the first display
cycle), killed clean, no strays. **Full V0 regression, all green:** V0.1
**18/18** · V0.2 **35/35** · V0.3 **97/97** · V0.5 **88/88** · V0.6 **24/24**
· V0.7 **69/69 + e2e 19/19** · V0.8 **95/95** · V0.9 **32/32** · V0.10
**21/21**. `pgrep -fl "sage -python|worker.py"` clean.

**Skill reviews applied (swiftui-pro / macos-design / typography-designer).**
- swiftui-pro: manual `FocusedValueKey` → the **`@Entry` macro**;
  `contentShape(Rectangle())` → `.contentShape(.rect)`; tap-selected tape row
  got `.accessibilityAddTraits(.isButton)` (a Button would fight text
  selection + hover); History double-click got an
  `accessibilityAction(named: "Insert into Input")`; if/return →
  if-expressions; `task()` over `onAppear`; `Duration.formatted(.units)` for
  eval times (no C-style formatting); sidebar list rows
  `.listRowSeparator(.hidden)` (§4.3).
- macos-design: confirmed `.inspector` over NavigationSplitView/HSplitView
  for a right-side utility panel; menu-bar parity for ⌘B; sparse toolbar;
  empty states everywhere; opacity-faded "return to evaluate" hint (never
  insert/remove, §1.1).
- typography-designer: the two-axis scale above; removed a confusing
  whole-picker `.help`; timestamps/meta at `.caption` only for metadata.

**Live gate (opus verifier, computer-use) — PASS, all 10 checks.** Verified on
screen: launch-fast + focus lands in input (typed `2+2` with zero clicks,
Return appended an honest "Not evaluated" row, focus retained); three-region
layout reads as a real Mac app; ⌘B + toolbar + View-menu all toggle the
sidebar; row selection drives Inspector (kind/plain/approx/LaTeX/Sage/duration)
and Actions (kind-appropriate, honest "runs once Sage is connected" footer);
History double-click inserts into input with focus; tape rests at bottom and
scrolls smoothly with the `≈ 0.5333333333` line, red `1/0` error row, and plot
placeholder all present; resize + inspector-divider drag never break layout;
dark mode fully legible; Copy Result verified via `pbpaste`; app responsive
after everything, quit clean, no stray processes. **Non-blocking polish notes
for later passes:** min window width is ~900pt (can't reach 720-wide; revisit
if a compact window matters); right-clicking directly on selectable result
*text* shows the OS text menu instead of the custom Copy menu (background
right-click shows the custom one); selecting a row doesn't auto-reveal the
Inspector tab.

**Learned / surprised.**
- `#expect(rows.contains(where: \.isPlot))` does not compile under
  swift-testing — the macro rewrites `contains(where:)` into a context where
  the key-path-as-function argument is treated as throwing. Use a closure
  (`rows.contains { $0.isPlot }`) inside `#expect`.
- `pgrep -fl "sage"` is a useless cleanliness check on a real Mac — it
  matches `iconservicesagent`, `MessagesBlastDoorService`, `UsageTracking…`.
  The discriminating check is `pgrep -fl "sage -python|worker.py"`.

**Next.** V1.2 — session model: lift `Session`/`SessionRow`/
`PersistedEnvelope`/`PersistedArtifact`/`Provenance`/`RowStatus` from
v0/10-persistence verbatim, replace `TapeRow` placeholder fields with the
real types, keep `ShellModel` as the view-facing seam.

---
