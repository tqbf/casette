import SwiftUI

/// Live user variables (the worker `symbols` op, refreshed after every
/// eval), with the V1.6 per-symbol actions: insert / copy Sage / inspect /
/// forget.
struct SymbolsTabView: View {
    @AppStorage(UILayout.showBuiltinSymbolsKey) private var showsBuiltinSymbols = false

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
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Symbols")
                        .font(Theme.Fonts.cardSectionLabel)
                        .foregroundStyle(.secondary)

                    Toggle("Show Built-ins", isOn: $showsBuiltinSymbols)
                        .toggleStyle(.checkbox)
                        .font(Theme.Fonts.symbolKind)
                }
                .padding(.horizontal, Theme.sidebarSectionPadding)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)

                if !visibleSymbols.isEmpty {
                    List(visibleSymbols) { symbol in
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
                } else {
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var visibleSymbols: [SymbolEntry] {
        model.symbols.visibleEntries(showingBuiltinSymbols: showsBuiltinSymbols)
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
