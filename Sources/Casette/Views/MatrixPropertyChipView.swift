import SwiftUI

/// One boolean Sage matrix `is_*()` property chip in the Inspector.
struct MatrixPropertyChipView: View {
    let property: MatrixProperty

    @State private var isHovering = false

    var body: some View {
        Text(displayText)
            .font(isHovering ? Theme.Fonts.matrixPropertyMethod : Theme.Fonts.matrixPropertyChip)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(backgroundStyle, in: Capsule())
            .overlay {
                Capsule().strokeBorder(borderStyle)
            }
            .foregroundStyle(textStyle)
            .help(helpText)
            .onHover { isHovering = $0 }
            .overlay(alignment: .top) {
                if isHovering {
                    MatrixPropertyTooltipView(
                        label: property.label,
                        method: methodCall,
                        value: isTrue)
                    .fixedSize()
                    .offset(y: -54)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(property.label)
            .accessibilityValue(isTrue ? "true" : "false")
            .accessibilityHint(methodCall)
    }

    private var isTrue: Bool {
        property.value == true
    }

    private var methodCall: String {
        "\(property.name)()"
    }

    private var displayText: String {
        isHovering ? methodCall : property.label
    }

    private var helpText: String {
        "\(property.label)\n\(methodCall) -> \(isTrue ? "True" : "False")"
    }

    private var backgroundStyle: AnyShapeStyle {
        if isTrue {
            return AnyShapeStyle(.green.opacity(0.16))
        }
        return AnyShapeStyle(.quaternary)
    }

    private var borderStyle: AnyShapeStyle {
        if isTrue {
            return AnyShapeStyle(.green.opacity(0.42))
        }
        return AnyShapeStyle(.tertiary.opacity(0.45))
    }

    private var textStyle: AnyShapeStyle {
        if isTrue {
            return AnyShapeStyle(.green)
        }
        return AnyShapeStyle(.secondary)
    }

}

#Preview {
    VStack(alignment: .leading) {
        MatrixPropertyChipView(
            property: MatrixProperty(name: "is_square", label: "Square", value: true))
        MatrixPropertyChipView(
            property: MatrixProperty(
                name: "is_positive_semidefinite",
                label: "Positive Semidefinite",
                value: false))
    }
    .padding()
    .frame(width: 180)
}
