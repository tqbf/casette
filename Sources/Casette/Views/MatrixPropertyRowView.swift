import SwiftUI

/// One unavailable Sage matrix `is_*()` property row in the Inspector.
struct MatrixPropertyRowView: View {
    let property: MatrixProperty

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: iconName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(iconStyle)
                .frame(width: 14)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(property.label)
                    .font(Theme.Fonts.matrixPropertyLabel)
                Text(property.name + "()")
                    .font(Theme.Fonts.matrixPropertyMethod)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let error = property.error, property.value == nil {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .help(helpText)
    }

    private var iconName: String {
        if property.value == true { return "checkmark.circle.fill" }
        if property.value == false { return "xmark.circle" }
        return "exclamationmark.triangle"
    }

    private var iconStyle: AnyShapeStyle {
        if property.value == true { return AnyShapeStyle(.green) }
        if property.value == false { return AnyShapeStyle(.tertiary) }
        return AnyShapeStyle(.orange)
    }

    private var accessibilityText: String {
        if property.value == true { return "\(property.label), true, \(property.name)" }
        if property.value == false { return "\(property.label), false, \(property.name)" }
        return "\(property.label), unavailable, \(property.name)"
    }

    private var helpText: String {
        "matrix.\(property.name)()"
    }
}

#Preview {
    VStack(alignment: .leading) {
        MatrixPropertyRowView(
            property: MatrixProperty(
                name: "is_diagonalizable",
                label: "Diagonalizable",
                error: "NotImplementedError: base ring does not support this operation"))
    }
    .padding()
    .frame(width: 280)
}
