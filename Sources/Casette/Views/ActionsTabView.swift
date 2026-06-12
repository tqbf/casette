import SwiftUI

/// Context-sensitive actions for the selected result, straight from the
/// envelope's per-kind `actions` list (V1.6). Clicking a command action
/// evaluates its built Sage command immediately; the context menu offers
/// expansion into the input for editing, plus copy. Copy-style actions copy
/// directly. The command strategy lives in `ResultAction`.
struct ActionsTabView: View {
    var model: ShellModel
    let row: SessionRow?
    var focusInput: () -> Void

    var body: some View {
        if let row, let result = row.result, !result.actions.isEmpty {
            let expression = row.reusableExpression
            List {
                Section {
                    ForEach(ResultAction.actions(for: result)) { action in
                        actionRow(action, result: result, expression: expression)
                            .listRowSeparator(.hidden)
                    }
                }

                // The hint lives INSIDE the List as a plain final row — never
                // a Section footer (macOS single-line-truncates those at
                // narrow widths) and never a fixedSize Text pinned outside
                // the scroll content (during window min-size measurement
                // SwiftUI proposes ~zero width, the text wraps to one
                // character per line, and fixedSize forces that ~1500pt
                // height into the window minimum — the V1.6 "window balloons
                // to 1598pt" bug). In-list content is scrollable, so it can
                // never drive the window's minimum size, and a list row's
                // width proposal is always the real column width, so it
                // wraps correctly.
                Text(footerText(expression: expression))
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowSeparator(.hidden)
                    .padding(.top, 4)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        } else {
            ContentUnavailableView(
                "No Actions",
                systemImage: "bolt",
                description: Text(emptyDescription)
            )
        }
    }

    @ViewBuilder
    private func actionRow(
        _ action: ResultAction,
        result: PersistedEnvelope,
        expression: String?
    ) -> some View {
        switch action.behavior {
        case .command:
            if let expression, let command = action.command(wrapping: expression) {
                ActionRowView(
                    title: action.title,
                    command: command,
                    onInsert: { insert(command) },
                    onEvaluate: { model.evaluateActionCommand(command) }
                )
            } else {
                ActionRowView(
                    title: action.title,
                    disabledReason: "This row's result can't be reused as an expression."
                )
            }
        case .copyPlain:
            ActionRowView(title: action.title, copyValue: result.plain)
        case .copyTraceback:
            ActionRowView(
                title: action.title,
                copyValue: result.error?.traceback ?? result.plain
            )
        case let .unavailable(reason):
            ActionRowView(title: action.title, disabledReason: reason)
        }
    }

    private func insert(_ command: String) {
        model.insertIntoDraft(command)
        focusInput()
    }

    private func footerText(expression: String?) -> String {
        if expression == nil {
            "This row's input isn't a single expression, so follow-up commands can't be built from it."
        } else {
            "Click evaluates the command immediately. Right-click to expand it into the input."
        }
    }

    /// Honest empty-state copy: no selection, a row that was never evaluated
    /// (no result yet), or a result whose kind genuinely has no actions.
    private var emptyDescription: String {
        switch row {
        case nil: "Select a result in the tape to see its actions."
        case .some(let row) where row.result == nil: "This row hasn't been evaluated yet."
        default: "This result has no actions."
        }
    }
}

#Preview("Matrix-ish row") {
    ActionsTabView(
        model: ShellModel(rows: PlaceholderData.rows),
        row: PlaceholderData.rows[1],
        focusInput: {}
    )
    .frame(width: 280, height: 400)
}

#Preview("Empty") {
    ActionsTabView(model: ShellModel(), row: nil, focusInput: {})
        .frame(width: 280, height: 400)
}
