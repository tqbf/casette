## A macOS SwiftUI `.popover` is its OWN KEY WINDOW — keys reach neither it nor your editor; transient pickers over a focused text field must be INLINE same-window overlays

**The symptoms, across three fix rounds (V1.4).** The ambiguity picker as a
`.popover(item:)` anchored to the input pane:
- **Round 1** (buttons carried `keyboardShortcut`s): Esc did nothing,
  pressing `2` typed a literal "2" into the field, clearing the field left
  stale candidates showing. Mouse clicks worked.
- **Round 2** (keys moved to `onKeyPress` handlers on the focused
  `TextEditor`): with the popover up, Esc/Return/digits did nothing, a plain
  `z` was swallowed — ordinary key input reached NEITHER the popover NOR the
  text field — and clicking a candidate row stopped working too. Only
  ⌘A+Delete still reached the field.
- **Round 3** (inline overlay in place): everything worked EXCEPT Esc —
  digits/Return/click/type-through all fine, but Esc "never fired" on
  screen, through `.onKeyPress(.escape)`, `.onExitCommand`, AND a local
  NSEvent monitor across two more rounds. **That part was NOT an app bug —
  see "the environment eats Esc" below.** The local-monitor shape was then
  PROVEN correct by posting Esc directly to the app's pid.

Every unit test passed every round (172/172) — the model was fine. This is
window/focus plumbing, invisible to any test that doesn't put real key
events through real windows.

**The cause — deeper than round 1's diagnosis.** Presenting a macOS SwiftUI
`.popover` creates a SEPARATE window that becomes (or contends to become)
the KEY window. The moment it's up, the main window's `TextEditor` loses
first-responder status, so:
- `onKeyPress` handlers on the editor never fire (they live in the main
  window's responder chain, which no longer receives keys), and
- the popover side has no text field and no reliable shortcut routing of
  its own, so the keys die in between. Plain typing is swallowed whole.
Round 1's reading ("the popover is a passive overlay; focus stays in the
editor") was wrong — it explained the round-1 symptoms but predicted the
round-2 fix would work, and it didn't. There is no winning key-routing
arrangement with `.popover` here: whichever side you put the handlers on,
the other side's window has the focus story you needed.

**The robust shape — don't present a second window at all.** Render the
picker as an **inline overlay in the SAME window**: a conditional
`.overlay(alignment: .topLeading)` on the input pane, alignment-guided to
float just above it like an autocomplete/suggestion panel (material
background, rounded, shadow). Because it's the same window:
- the `TextEditor` keeps keyboard focus the entire time, so its
  `onKeyPress` routing (Return → first candidate, digits 2–9 → nth, any
  edit → dismiss via the model's `draft.didSet`) fires reliably;
- **except Esc — which is handled below the SwiftUI layer; the robust hook
  is an AppKit local NSEvent monitor.** Digits and Return arrive at the
  focused text view as ordinary key presses, but Escape is translated by
  the Cocoa key-binding system into the `cancelOperation:` ACTION before
  any `onKeyPress` can see it — so `.onKeyPress(.escape)` never fires; and
  the `NSTextView` backing `TextEditor` implements `cancelOperation:`
  itself, so `.onExitCommand` is unreliable over a focused editor. The
  proven shape (`EscapeInterceptor.swift`, verified by posting a real Esc
  keyDown to the app's pid and watching `cancelAmbiguity()` fire):
  `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` — fires BEFORE
  the window dispatches the key to the text view. On `keyCode == 53`
  (Esc), in the right window (`event.window === view.window`), with
  something actually pending, act and return `nil` (swallow the event);
  otherwise return the event unchanged so plain Esc keeps every default
  behavior (exiting full screen, etc.). Own the monitor with a tiny
  `NSViewRepresentable`-backed `NSView` — `viewDidMoveToWindow` installs
  it exactly once (guard on the stored token, so re-renders can't stack
  duplicates) and removes it on window detach, deinit as the backstop —
  and capture `self` weakly in the handler so the monitor never retains
  the view;
- plain `Button`s in the panel handle the mouse (no `keyboardShortcut`s on
  them — the editor owns the keys; macOS buttons don't grab key focus);
- appear/disappear is a plain structural conditional with NO transition —
  instant, and §1.1-safe (that rule is about *animated* insert/remove).
The model half of the round-1 fix was right and survives unchanged:
`cancelAmbiguity()` / `resolveAmbiguity(at:)` as plain testable methods,
and dismiss-on-edit via `draft.didSet` (so ⌘A+Delete, paste, and
programmatic inserts all dismiss — observe the data, not the keystrokes).

**Rules.**
1. **A transient picker over a focused text field (autocomplete,
   ambiguity, mention/emoji panels) must be an inline same-window overlay,
   never a `.popover`/sheet/window.** The whole interaction contract —
   "keep typing, Esc to keep editing, Return to take the suggestion" —
   depends on the field never losing first responder, and a second window
   guarantees it does.
2. Never advertise a key on ANY surface without proving the event reaches
   it on screen; key routing is unfalsifiable by unit tests.
3. "Dismiss the transient UI when its subject changes" belongs on the
   model (a `didSet` on the subject), or paste/⌘A-Delete paths leak stale UI.
4. **Esc over a focused text view is invisible to SwiftUI — intercept it
   with a local NSEvent monitor.** The key-binding system turns Esc into
   `cancelOperation:` before `.onKeyPress(.escape)` can fire, and the
   NSTextView consumes that action without forwarding it, so
   `.onExitCommand` is unreliable too.
   `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` sees the key
   first. Scope the behavior, not the monitor: swallow the event (return
   `nil`) only when there is actually something to cancel AND it's your
   window; pass everything else through untouched.

---
