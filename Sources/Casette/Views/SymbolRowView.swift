import SwiftUI

/// One symbol-table entry: name + kind on the first line, the bounded
/// summary below.
struct SymbolRowView: View {
    let symbol: SymbolEntry

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
        .contextMenu {
            Button("Copy Name") { Pasteboard.copy(symbol.name) }
            Button("Copy Summary") { Pasteboard.copy(symbol.summary) }
        }
    }
}

#Preview {
    List(PlaceholderData.symbols.entries) { symbol in
        SymbolRowView(symbol: symbol)
    }
    .frame(width: 280, height: 300)
}
