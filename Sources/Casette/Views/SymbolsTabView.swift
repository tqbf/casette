import SwiftUI

/// Live user variables (the worker `symbols` op, refreshed after every
/// eval), with the V1.6 per-symbol actions: insert / copy Sage / inspect /
/// forget.
struct SymbolsTabView: View {
    var model: ShellModel
    var focusInput: () -> Void

    var body: some View {
        if model.symbols.entries.isEmpty {
            ContentUnavailableView(
                "No Symbols Yet",
                systemImage: "x.squareroot",
                description: Text("Variables you define appear here.")
            )
        } else {
            List(model.symbols.entries) { symbol in
                SymbolRowView(
                    symbol: symbol,
                    onInsert: { insert(symbol) },
                    onInspect: { model.inspectSymbol(symbol.name) },
                    onForget: { model.forgetSymbol(symbol.name) }
                )
                .listRowSeparator(.hidden)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }

    private func insert(_ symbol: SymbolEntry) {
        model.insertSymbolIntoDraft(symbol.name)
        focusInput()
    }
}

#Preview {
    SymbolsTabView(
        model: ShellModel(symbols: PlaceholderData.symbols),
        focusInput: {}
    )
    .frame(width: 280, height: 400)
}
