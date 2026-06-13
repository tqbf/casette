import FriendlyCompiler
import SwiftUI

struct PlotFormulaBar: View {
    @Bindable var model: ShellModel
    let formula: PlotFormulaIR

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            FormulaFunctionChip(title: "PLOT")

            HStack(alignment: .center, spacing: 6) {
                FormulaTokenField(
                    title: "expr",
                    prompt: "sin(x)",
                    text: binding(
                        get: { $0.expression },
                        set: { $0.expression = $1 }))

                FormulaTokenField(
                    title: "var",
                    prompt: "x",
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
                    prompt: "optional",
                    text: binding(
                        get: { $0.lowerBound ?? "" },
                        set: {
                            $0.lowerBound = $1.isEmpty ? nil : $1
                            if !$1.isEmpty, $0.variable.isEmpty { $0.variable = "x" }
                        }))

                Text("..")
                    .font(Theme.Fonts.formulaPunctuation)
                    .foregroundStyle(.tertiary)

                FormulaTokenField(
                    title: "upper",
                    prompt: "optional",
                    text: binding(
                        get: { $0.upperBound ?? "" },
                        set: {
                            $0.upperBound = $1.isEmpty ? nil : $1
                            if !$1.isEmpty, $0.variable.isEmpty { $0.variable = "x" }
                        }))
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    private func binding(
        get: @escaping (PlotFormulaIR) -> String,
        set: @escaping (inout PlotFormulaIR, String) -> Void
    ) -> Binding<String> {
        Binding {
            guard let current = model.plotFormula else { return get(formula) }
            return get(current)
        } set: { value in
            var next = model.plotFormula ?? formula
            set(&next, value)
            model.updateFormula(.plot(next))
        }
    }
}
