import SwiftUI

/// Hover details for a matrix property chip.
struct MatrixPropertyTooltipView: View {
    let label: String
    let method: String
    let value: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(value ? .green : .secondary)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(label)
                    .font(Theme.Fonts.matrixPropertyTooltipLabel)
                    .foregroundStyle(.primary)
            }

            Text(method)
                .font(Theme.Fonts.matrixPropertyTooltipMethod)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minWidth: 150, alignment: .leading)
    }
}

#Preview {
    MatrixPropertyTooltipView(
        label: "Positive Semidefinite",
        method: "is_positive_semidefinite()",
        value: false)
}
