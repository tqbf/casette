import FriendlyCompiler
import SwiftUI

struct ImplicitPlotFormulaBar: View {
    @Bindable var model: ShellModel
    let formula: ImplicitPlotFormulaIR

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            FormulaFunctionChip(title: "IMPLICIT PLOT")

            HStack(alignment: .center, spacing: 6) {
                FormulaTokenField(
                    title: "eq",
                    prompt: "x^2 + y^2 = 1",
                    text: binding(
                        get: { $0.equation },
                        set: { $0.equation = $1 }),
                    // The equation carries a full `LHS = RHS`; give it the wider
                    // ceiling (like SubsFormulaBar's bindings token) so `= 1`
                    // isn't clipped off the visible token.
                    maxWidth: 220,
                    growsWithContent: true)

                // The x-axis range reads as one semantic group: `x  -2 .. 2`.
                axisGroup(
                    label: "x",
                    lowerPrompt: "-2",
                    upperPrompt: "2",
                    lower: binding(
                        get: { $0.xLower ?? "" },
                        set: { $0.xLower = $1.isEmpty ? nil : $1 }),
                    upper: binding(
                        get: { $0.xUpper ?? "" },
                        set: { $0.xUpper = $1.isEmpty ? nil : $1 }))

                // The y-axis range reads as one semantic group: `y  -2 .. 2`.
                axisGroup(
                    label: "y",
                    lowerPrompt: "-2",
                    upperPrompt: "2",
                    lower: binding(
                        get: { $0.yLower ?? "" },
                        set: { $0.yLower = $1.isEmpty ? nil : $1 }),
                    upper: binding(
                        get: { $0.yUpper ?? "" },
                        set: { $0.yUpper = $1.isEmpty ? nil : $1 }))
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    private func axisGroup(
        label: String,
        lowerPrompt: String,
        upperPrompt: String,
        lower: Binding<String>,
        upper: Binding<String>
    ) -> some View {
        HStack(alignment: .center, spacing: 6) {
            FormulaTokenField(title: label, prompt: lowerPrompt, text: lower)

            Text("..")
                .font(Theme.Fonts.formulaPunctuation)
                .foregroundStyle(.tertiary)

            FormulaTokenField(
                title: "",
                prompt: upperPrompt,
                text: upper,
                accessibilityTitle: "\(label) upper")
        }
    }

    private func binding(
        get: @escaping (ImplicitPlotFormulaIR) -> String,
        set: @escaping (inout ImplicitPlotFormulaIR, String) -> Void
    ) -> Binding<String> {
        Binding {
            guard let current = model.implicitPlotFormula else { return get(formula) }
            return get(current)
        } set: { value in
            var next = model.implicitPlotFormula ?? formula
            set(&next, value)
            model.updateFormula(.implicitPlot(next))
        }
    }
}
