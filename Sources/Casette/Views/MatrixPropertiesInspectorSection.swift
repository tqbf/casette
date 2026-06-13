import SwiftUI

/// A compact Inspector section for Sage matrix `is_*()` facts.
struct MatrixPropertiesInspectorSection: View {
    let properties: [MatrixProperty]

    @State private var showUnavailableProperties = false

    private let columns = [
        GridItem(.adaptive(minimum: 112), spacing: 6, alignment: .leading),
    ]

    var body: some View {
        Section("Matrix Properties") {
            if properties.isEmpty {
                Text("No matrix properties reported.")
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent("Summary", value: summary)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(availableProperties) { property in
                        MatrixPropertyChipView(property: property)
                    }
                }
                .padding(.vertical, 2)

                if !unavailableProperties.isEmpty {
                    DisclosureGroup(
                        "Unavailable (\(unavailableProperties.count.formatted()))",
                        isExpanded: $showUnavailableProperties
                    ) {
                        ForEach(unavailableProperties) { property in
                            MatrixPropertyRowView(property: property)
                        }
                    }
                }
            }
        }
    }

    private var availableProperties: [MatrixProperty] {
        properties.filter { $0.value != nil }
    }

    private var trueProperties: [MatrixProperty] {
        properties.filter { $0.value == true }
    }

    private var unavailableProperties: [MatrixProperty] {
        properties.filter { $0.value == nil }
    }

    private var summary: String {
        let trueCount = trueProperties.count.formatted()
        let totalCount = properties.count.formatted()
        return "\(trueCount) true of \(totalCount)"
    }
}

#Preview {
    Form {
        MatrixPropertiesInspectorSection(properties: [
            MatrixProperty(name: "is_square", label: "Square", value: true),
            MatrixProperty(name: "is_symmetric", label: "Symmetric", value: true),
            MatrixProperty(name: "is_zero", label: "Zero", value: false),
            MatrixProperty(name: "is_diagonalizable", label: "Diagonalizable", value: false),
            MatrixProperty(name: "is_positive_definite", label: "Positive Definite", value: false),
            MatrixProperty(
                name: "is_permutation_of",
                label: "Permutation Of",
                error: "TypeError: unable to decide over this base ring"),
        ])
    }
    .formStyle(.grouped)
    .frame(width: 280, height: 360)
}
