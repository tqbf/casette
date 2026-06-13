import SwiftUI

struct MatrixTableCellView: View {
    let value: String
    let row: Int
    let column: Int
    let isHovered: Bool
    let onHover: (Bool) -> Void

    var body: some View {
        Text(value)
            .font(Theme.Fonts.matrixTableCell)
            .foregroundStyle(isZero ? .tertiary : .primary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(width: 104, height: 26, alignment: .trailing)
            .background(cellBackground)
            .overlay(cellBorder)
            .onHover(perform: onHover)
    }

    private var isZero: Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines) == "0"
    }

    private var cellBackground: some ShapeStyle {
        isHovered ? Color.accentColor.opacity(0.13) : Color.clear
    }

    private var cellBorder: some View {
        Rectangle()
            .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
    }
}
