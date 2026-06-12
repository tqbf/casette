import SwiftUI

struct FormulaFunctionChip: View {
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "function")
                .font(.callout.weight(.semibold))
            Text(title)
                .font(Theme.Fonts.formulaFunction)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: Theme.formulaTokenCornerRadius, style: .continuous)
                .fill(Color.accentColor.opacity(0.13))
        }
        .fixedSize()
        .accessibilityLabel("\(title.capitalized) formula")
    }
}
