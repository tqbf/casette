import SwiftUI

/// The bottom input pane — a single prominent calculator line with the
/// kernel status indicator at its trailing edge. Return submits and
/// evaluates; the real input behaviors (multiline, history, generated-Sage
/// disclosure, compiler integration) arrive in V1.4.
struct InputPaneView: View {
    @Bindable var model: ShellModel
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: Theme.inputElementSpacing) {
            Image(systemName: "chevron.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(
                "Expression",
                text: $model.draft,
                prompt: Text("Type math — try  factor x^4 - 1")
            )
            .textFieldStyle(.plain)
            .font(Theme.Fonts.input)
            .focused(isFocused)
            .onSubmit(model.submitDraft)
            .labelsHidden()
            // Always mounted, opacity-faded (never insert/remove — §1.1).
            Text("return to evaluate")
                .font(Theme.Fonts.meta)
                .foregroundStyle(.tertiary)
                .opacity(model.draft.isEmpty ? 0 : 1)
                .animation(.easeOut(duration: 0.15), value: model.draft.isEmpty)
                .accessibilityHidden(true)
            KernelStatusView(state: model.kernelState, issue: model.kernelIssue)
        }
        .padding(.horizontal, Theme.inputPaddingHorizontal)
        .padding(.vertical, Theme.inputPaddingVertical)
        .background(.bar)
    }
}
