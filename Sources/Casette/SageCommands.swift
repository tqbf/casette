import SwiftUI

/// The Sage menu: kernel control commands wired to the focused window's
/// model. Restart is the INTENTIONAL state reset (fresh worker, fresh
/// namespace — variables are deliberately cleared); Interrupt asks the
/// in-flight evaluation to stop (SIGINT, escalating to a hard kill if Sage
/// won't yield). Shortcuts are the planned V1.12 bindings, carried on menu
/// items so they're discoverable; both disable honestly when they can't act.
struct SageCommands: Commands {
    @FocusedValue(\.shellModel) private var model: ShellModel?

    var body: some Commands {
        CommandMenu("Sage") {
            // ⌘↩ — evaluate the input WITHOUT advancing (the draft stays in
            // place for iteration). On the menu so it's discoverable; as a
            // key equivalent it works while the input field has focus.
            Button("Evaluate Without Advancing") {
                model?.evaluateInPlace()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(model == nil)

            Divider()

            // V1.8 numeric mode — the menu mirror of the input pane's
            // "≈ Numeric" toggle (same model flag; the checkmark and the
            // pressed button always agree). No shortcut yet: V1.12 is the
            // keyboard pass, and a key must never be advertised unverified
            // (PROBLEMS.md).
            if let model {
                @Bindable var model = model
                Toggle("Numeric Results", isOn: $model.numericMode)
            } else {
                Toggle("Numeric Results", isOn: .constant(false))
                    .disabled(true)
            }

            Divider()

            Button("Interrupt Evaluation") {
                model?.interruptEvaluation()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(model?.kernelState != .running)

            Button("Restart Sage") {
                model?.restartKernel()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(model == nil || model?.kernelState == .restarting)
        }
    }
}
