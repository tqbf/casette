import SwiftUI

/// One history entry: the raw input plus its time. Double-click inserts it
/// into the input; the context menu adds rerun and copy.
struct HistoryRowView: View {
    let row: SessionRow
    let canRerun: Bool
    let onInsert: () -> Void
    let onRerun: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(row.input)
                .font(Theme.Fonts.sidebarMono)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: Theme.inputElementSpacing)
            Text(row.timestamp, style: .time)
                .font(Theme.Fonts.meta)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .onTapGesture(count: 2, perform: onInsert)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Insert into Input", onInsert)
        .accessibilityAction(named: "Rerun") {
            guard canRerun else { return }
            onRerun()
        }
        .contextMenu {
            Button("Rerun", action: onRerun)
                .disabled(!canRerun)
                .help(canRerun ? "Re-evaluate this row" : "Replay the session before rerunning restored rows")
            Button("Insert into Input", action: onInsert)
            Button("Copy") { Pasteboard.copy(row.input) }
        }
        .help("Double-click to insert into the input")
    }
}

#Preview {
    List(PlaceholderData.rows) { row in
        HistoryRowView(row: row, canRerun: true, onInsert: {}, onRerun: {})
    }
    .frame(width: 280, height: 300)
}
