import FriendlyCompiler
import SwiftUI

struct ParametricPlotFormulaBar: View {
    @Bindable var model: ShellModel
    let formula: ParametricPlotFormulaIR

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            FormulaFunctionChip(title: "PARAMETRIC")

            HStack(alignment: .center, spacing: 6) {
                FormulaTokenField(
                    title: "x(t)",
                    prompt: "cos(t)",
                    text: binding(
                        get: { $0.xExpression },
                        set: { $0.xExpression = $1 }))

                FormulaTokenField(
                    title: "y(t)",
                    prompt: "sin(t)",
                    text: binding(
                        get: { $0.yExpression },
                        set: { $0.yExpression = $1 }))

                FormulaTokenField(
                    title: "var",
                    prompt: "t",
                    text: binding(
                        get: { $0.variable },
                        set: {
                            $0.variable = $1
                            $0.hasExplicitVariable = true
                        }))

                Text(",")
                    .font(Theme.Fonts.formulaPunctuation)
                    .foregroundStyle(.tertiary)

                FormulaTokenField(
                    title: "lower",
                    prompt: "0",
                    text: binding(
                        get: { $0.lowerBound ?? "" },
                        set: {
                            $0.lowerBound = $1.isEmpty ? nil : $1
                            if !$1.isEmpty, $0.variable.isEmpty { $0.variable = "t" }
                        }))

                Text("..")
                    .font(Theme.Fonts.formulaPunctuation)
                    .foregroundStyle(.tertiary)

                FormulaTokenField(
                    title: "upper",
                    prompt: "2*pi",
                    text: binding(
                        get: { $0.upperBound ?? "" },
                        set: {
                            $0.upperBound = $1.isEmpty ? nil : $1
                            if !$1.isEmpty, $0.variable.isEmpty { $0.variable = "t" }
                        }))
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    private func binding(
        get: @escaping (ParametricPlotFormulaIR) -> String,
        set: @escaping (inout ParametricPlotFormulaIR, String) -> Void
    ) -> Binding<String> {
        Binding {
            guard let current = model.parametricPlotFormula else { return get(formula) }
            return get(current)
        } set: { value in
            var next = model.parametricPlotFormula ?? formula
            set(&next, value)
            model.updateFormula(.parametricPlot(next))
        }
    }
}
