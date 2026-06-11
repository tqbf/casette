import SwiftUI

/// Live user variables (placeholder data; V1.6 feeds the worker `symbols`
/// op straight into this view).
struct SymbolsTabView: View {
    let symbols: [SymbolEntry]

    var body: some View {
        if symbols.isEmpty {
            ContentUnavailableView(
                "No Symbols Yet",
                systemImage: "x.squareroot",
                description: Text("Variables you define appear here.")
            )
        } else {
            List(symbols) { symbol in
                SymbolRowView(symbol: symbol)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
    }
}

#Preview {
    SymbolsTabView(symbols: PlaceholderData.symbols)
        .frame(width: 280, height: 400)
}
