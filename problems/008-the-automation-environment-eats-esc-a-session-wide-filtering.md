## THE AUTOMATION ENVIRONMENT EATS Esc — a session-wide filtering event tap consumes keyCode 53 before ANY app sees it; verify Esc via `CGEvent.postToPid`

**The symptom that burned two full fix/verify rounds (V1.4).** The inline
ambiguity panel's Esc-to-dismiss "failed on screen" through three different
implementations (`.onKeyPress(.escape)`, `.onExitCommand`, a local NSEvent
monitor) while every OTHER key worked. Instrumenting the local monitor
showed the truth: it logged every keyDown (letters, Return, digits) but a
pressed/injected **Esc produced NO keyDown event at all** — not in the app,
and not even in a `CGEventTapCreateForPid` tap on the app's process. Yet a
session-level head-insert tap DID see the Esc. Conclusion: something
between the session stream and per-app delivery consumes Esc system-wide.

**The culprit.** `CGGetEventTapList` showed an enabled session-wide
**FILTERING** tap on `keyDown` owned by the **computer-use automation
harness itself** (the `claude` process). The harness uses Esc as its abort
key and swallows every one — physical or injected, MCP `key` tool or
AppleScript `key code 53`. (A lurking
`com.apple.accessibility.universalAccessAuthWarn` panel was a red herring;
killing it changed nothing.) So **on this machine, no app can ever receive
Esc through normal injection — "Esc didn't work" in a computer-use
verification is evidence of NOTHING about the app.**

**The proof + the workaround.** `CGEvent(keyboardEventSource:…,
virtualKey: 53, keyDown:…).postToPid(appPid)` delivers straight to the
app's event queue, BELOW the session tap. With that, the app's
`EscapeInterceptor` fired immediately (`onEscape -> true`, panel
dismissed) — the round-4 code had been correct all along.
`scripts/send-key.swift <keycode> <pid>` is the reusable helper.

**Rules.**
1. When a key "doesn't work" under computer-use verification, FIRST prove
   the event reaches the process (temporary NSEvent-monitor logging, or a
   pid-level CGEvent tap) before touching app code. Key delivery has more
   layers than the responder chain: session filtering taps run before
   per-app routing.
2. On-screen verification of Esc-driven UI (and any key an automation
   harness might claim) must inject via `scripts/send-key.swift`
   (`CGEvent.postToPid`), not the MCP `key` tool or System Events.
3. V1.12 (keyboard pass) must use this for every shortcut it certifies —
   and treat any "key didn't fire" verdict as unproven until delivery is
   confirmed at the process boundary.

---
