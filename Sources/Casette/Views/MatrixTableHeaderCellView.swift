import SwiftUI

struct MatrixTableHeaderCellView: View {
    let text: String
    var alignment: Alignment = .trailing
    var width: CGFloat = 104

    var body: some View {
        Text(text)
            .font(Theme.Fonts.matrixTableHeader)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(width: width, height: 24, alignment: alignment)
            .background(Color.secondary.opacity(0.06))
            .overlay(
                Rectangle()
                    .stroke(Color.secondary.opacity(0.14), lineWidth: 0.5)
            )
    }
}
