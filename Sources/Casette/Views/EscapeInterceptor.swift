import SwiftUI

/// kVK_Escape — the hardware-independent virtual key code for the Esc key.
private let escapeKeyCode: UInt16 = 53

/// The Esc hook for the inline ambiguity panel — an AppKit local event
/// monitor, because NO SwiftUI-level handler can see Esc over a focused
/// `TextEditor` (V1.4 fix rounds 1–4; PROBLEMS.md inline-overlay entry):
/// - `.onKeyPress(.escape)` never fires: the Cocoa key-binding system
///   translates Esc into the `cancelOperation:` ACTION before any key-press
///   handler runs (round 3's diagnosis — still true).
/// - `.onExitCommand` never fires either (round 4's discovery): the
///   `NSTextView` backing `TextEditor` implements `cancelOperation:` itself
///   (completion-session dismissal) and CONSUMES it, so the action never
///   walks up the responder chain to where SwiftUI could surface it.
/// A local `NSEvent` monitor sees the key-down BEFORE the window dispatches
/// it to the focused text view — the only reliable interception point.
///
/// Lifecycle: the monitor lives exactly as long as the backing view sits in
/// a window. `viewDidMoveToWindow` installs it once (the `monitor == nil`
/// guard means SwiftUI re-renders can never stack duplicates) and removes it
/// when the view leaves the window; `deinit` is the backstop. The view is
/// invisible and never hit-testable, so it can't disturb the mouse paths.
///
/// Scope: `onEscape` returns whether it consumed the key — `true` swallows
/// the event, `false` passes Esc through untouched, so with nothing pending
/// Esc keeps every default behavior (exiting full screen, etc.). Events
/// destined for OTHER windows are always passed through (the monitor is
/// app-wide; the `event.window === self.window` check scopes it).
struct EscapeInterceptor: NSViewRepresentable {
    /// Called on Esc key-down in this view's window. Return `true` to
    /// swallow the event, `false` to let it through unchanged.
    let onEscape: () -> Bool

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.onEscape = onEscape  // re-renders refresh the closure, never the monitor
    }

    final class MonitorView: NSView {
        var onEscape: () -> Bool = { false }
        /// The opaque monitor token. `nonisolated(unsafe)` solely so the
        /// deinit backstop below can read it: it is only ever written from
        /// the main actor, and deinit has exclusive access by definition.
        private nonisolated(unsafe) var monitor: Any?

        /// Invisible helper — must never intercept the mouse.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                removeMonitorIfInstalled()
            } else if monitor == nil {
                installMonitor()
            }
        }

        deinit {
            // Backstop only — leaving the window above is the deterministic
            // removal path. `NSEvent.removeMonitor` is nonisolated and
            // deinit has exclusive access to the stored property.
            if let monitor { NSEvent.removeMonitor(monitor) }
        }

        private func installMonitor() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == escapeKeyCode else { return event }
                // Local monitors run synchronously on the main thread (the
                // main run loop dispatches the event), so this never traps.
                let consumed = MainActor.assumeIsolated { () -> Bool in
                    guard let self, event.window === self.window else { return false }
                    return self.onEscape()
                }
                return consumed ? nil : event
            }
        }

        private func removeMonitorIfInstalled() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
