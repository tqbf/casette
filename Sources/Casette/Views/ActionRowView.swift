import SwiftUI

/// One row in the Actions tab: the action's title with, for command actions,
/// the concrete Sage command it builds previewed underneath (the command IS
/// what runs — V1.11's "actions generate visible Sage commands", visible
/// already). Three shapes:
///   * command  — click inserts into the input; context menu evaluates/copies
///   * copy     — click copies the value
///   * disabled — listed but inert, with the reason in a tooltip
struct ActionRowView: View {
    let title: String
    var command: String?
    var copyValue: String?
    var onInsert: (() -> Void)?
    var onEvaluate: (() -> Void)?
    var disabledReason: String?

    var body: some View {
        if let disabledReason {
            // A real disabled button (not a dimmed label): consistent row
            // metrics, and assistive tech reads it as a dimmed control with
            // the reason, not a mystery label.
            Button(action: {}) {
                label.contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(true)
            .help(disabledReason)
            .accessibilityHint(disabledReason)
        } else if let copyValue {
            Button(action: { Pasteboard.copy(copyValue) }) {
                label.contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Copy to the clipboard")
        } else {
            Button(action: { onInsert?() }) {
                label.contentShape(.rect)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Insert into Input") { onInsert?() }
                Button("Evaluate Now") { onEvaluate?() }
                if let command {
                    Button("Copy Command") { Pasteboard.copy(command) }
                }
            }
            .accessibilityHint("Inserts the Sage command into the input")
            .help("Click to insert into the input; right-click to evaluate now")
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: copyValue == nil ? "bolt" : "doc.on.doc")
                .lineLimit(1)
                .truncationMode(.tail)
            if let command {
                Text(command)
                    .font(Theme.Fonts.sidebarMono)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, Theme.actionCommandIndent)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    List {
        ActionRowView(
            title: "Determinant",
            command: "(matrix([[1,2],[3,4]])).det()",
            onInsert: {},
            onEvaluate: {}
        )
        ActionRowView(title: "Copy Traceback", copyValue: "Traceback...")
        ActionRowView(title: "Save PNG", disabledReason: "Plot actions arrive with V1.7.")
    }
    .frame(width: 280, height: 300)
}
