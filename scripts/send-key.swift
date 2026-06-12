// Verification helper: post a key-down/up pair DIRECTLY to a process,
// bypassing session-level event routing.
//
// Why this exists (V1.4 Esc saga, PROBLEMS.md): the computer-use automation
// harness on this machine holds a session-wide FILTERING CGEvent tap on
// keyDown that consumes Esc (its abort key) before any app sees it — so Esc
// can never be exercised through normal injection (System Events, MCP `key`).
// `CGEvent.postToPid` delivers straight to the target process's event queue,
// below the session tap, so on-screen verification of Esc-driven UI uses:
//
//   swift scripts/send-key.swift <keycode> <pid>
//
// Esc = 53. Find the app pid with `pgrep -x Casette`.
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 3,
      let key = UInt16(CommandLine.arguments[1]),
      let pid = pid_t(CommandLine.arguments[2]) else {
    print("usage: swift send-key.swift <keycode> <pid>")
    exit(1)
}
let source = CGEventSource(stateID: .hidSystemState)
guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
      let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else {
    print("could not create key events")
    exit(1)
}
down.postToPid(pid)
usleep(50_000)
up.postToPid(pid)
print("posted keycode \(key) to pid \(pid)")
