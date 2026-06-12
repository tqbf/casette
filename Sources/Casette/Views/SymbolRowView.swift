import SwiftUI

/// One symbol-table entry: name + kind on the first line, the bounded
/// summary below. Double-click inserts the name into the input; the context
/// menu carries the full V1.6 action set (insert / copy Sage / inspect /
/// forget) — the macOS idiom for actionable rows (§7.4).
struct SymbolRowView: View {
    let symbol: SymbolEntry
    let onInsert: () -> Void
    let onInspect: () -> Void
    let onForget: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(symbol.name)
                    .font(Theme.Fonts.symbolName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: Theme.inputElementSpacing)
                Text(symbol.kind)
                    .font(Theme.Fonts.symbolKind)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Text(symbol.summary)
                .font(Theme.Fonts.sidebarMono)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .onTapGesture(count: 2, perform: onInsert)
        .contextMenu {
            Button("Insert into Input", action: onInsert)
            Button("Copy Sage") { Pasteboard.copy(symbol.sageSnippet) }
            Button("Copy Summary") { Pasteboard.copy(symbol.summary) }
            Button("Inspect", action: onInspect)
            Divider()
            Button("Forget \(symbol.name)", role: .destructive, action: onForget)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Insert into Input", onInsert)
        .accessibilityAction(named: "Inspect", onInspect)
        .accessibilityAction(named: "Forget", onForget)
        .help("Double-click to insert \(symbol.name) into the input")
    }
}

#Preview {
    List(PlaceholderData.symbols.entries) { symbol in
        SymbolRowView(symbol: symbol, onInsert: {}, onInspect: {}, onForget: {})
    }
    .frame(width: 280, height: 300)
}
