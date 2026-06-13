import SwiftUI

struct MatrixTableWindowView: View {
    let title: String
    let table: MatrixTableData
    let onDismiss: () -> Void

    @State private var hoveredRow: Int?
    @State private var hoveredColumn: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    columnHeaderRow
                    ForEach(0..<table.rowCount, id: \.self) { row in
                        HStack(spacing: 0) {
                            MatrixTableHeaderCellView(text: "\(row + 1)", width: 58)
                            ForEach(0..<table.columnCount, id: \.self) { column in
                                MatrixTableCellView(
                                    value: value(row: row, column: column),
                                    row: row,
                                    column: column,
                                    isHovered: hoveredRow == row && hoveredColumn == column,
                                    onHover: { isHovered in setHover(isHovered, row: row, column: column) }
                                )
                            }
                        }
                    }
                }
                .padding(16)
                .accessibilityHidden(true)
            }
            .accessibilityLabel("\(title), \(table.rowCount) rows by \(table.columnCount) columns")
        }
        .frame(minWidth: 520, minHeight: 360)
        .background(.background)
        .background(EscapeInterceptor {
            onDismiss()
            return true
        })
    }

    private var header: some View {
        HStack(spacing: Theme.inputElementSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Fonts.matrixTableTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(table.rowCount) rows × \(table.columnCount) columns")
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Theme.inputElementSpacing)
            if let hoveredRow, let hoveredColumn {
                Label("Row \(hoveredRow + 1), Column \(hoveredColumn + 1)", systemImage: "scope")
                    .font(Theme.Fonts.matrixTableHover)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.10))
                    )
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .animation(.easeOut(duration: 0.12), value: hoveredRow)
        .animation(.easeOut(duration: 0.12), value: hoveredColumn)
    }

    private var columnHeaderRow: some View {
        HStack(spacing: 0) {
            MatrixTableHeaderCellView(text: "", alignment: .center, width: 58)
            ForEach(0..<table.columnCount, id: \.self) { column in
                MatrixTableHeaderCellView(text: "\(column + 1)")
            }
        }
    }

    private func value(row: Int, column: Int) -> String {
        guard table.rows.indices.contains(row),
              table.rows[row].indices.contains(column)
        else { return "" }
        return table.rows[row][column]
    }

    private func setHover(_ isHovered: Bool, row: Int, column: Int) {
        if isHovered {
            hoveredRow = row
            hoveredColumn = column
        } else if hoveredRow == row && hoveredColumn == column {
            hoveredRow = nil
            hoveredColumn = nil
        }
    }
}

#Preview {
    MatrixTableWindowView(
        title: "Matrix #8",
        table: MatrixTableData(
            rows: [
                ["1", "0", "3", "4", "5", "6", "7"],
                ["0", "9", "10", "11", "12", "13", "14"],
            ],
            rowCount: 2,
            columnCount: 7
        ),
        onDismiss: {}
    )
}
