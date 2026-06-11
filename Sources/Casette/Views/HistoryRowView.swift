import SwiftUI

/// One history entry: the raw input plus its time, double-click or
/// context-menu to reuse it.
struct HistoryRowView: View {
    let row: TapeRow
    let onInsert: () -> Void

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
        .accessibilityAction(named: "Insert into Input", onInsert)
        .contextMenu {
            Button("Insert into Input", action: onInsert)
            Button("Copy") { Pasteboard.copy(row.input) }
        }
        .help("Double-click to insert into the input")
    }
}

#Preview {
    List(PlaceholderData.rows) { row in
        HistoryRowView(row: row, onInsert: {})
    }
    .frame(width: 280, height: 300)
}
