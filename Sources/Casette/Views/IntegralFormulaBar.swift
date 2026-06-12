import FriendlyCompiler
import SwiftUI

struct IntegralFormulaBar: View {
    @Bindable var model: ShellModel
    let formula: IntegralFormulaIR

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            FormulaFunctionChip(title: "INTEGRAL")

            HStack(alignment: .center, spacing: 6) {
                FormulaTokenField(
                    title: "expr",
                    prompt: "x^2",
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
        get: @escaping (IntegralFormulaIR) -> String,
        set: @escaping (inout IntegralFormulaIR, String) -> Void
    ) -> Binding<String> {
        Binding {
            guard let current = model.integralFormula else { return get(formula) }
            return get(current)
        } set: { value in
            var next = model.integralFormula ?? formula
            set(&next, value)
            model.updateIntegralFormula(next)
        }
    }
}
