import FriendlyCompiler
import SwiftUI

struct DerivativeFormulaBar: View {
    @Bindable var model: ShellModel
    let formula: DerivativeFormulaIR

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            FormulaFunctionChip(title: "DERIVATIVE")

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

                FormulaTokenField(
                    title: "order",
                    prompt: "optional",
                    text: binding(
                        get: { $0.order ?? "" },
                        set: { $0.order = $1.isEmpty ? nil : $1 }))
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    private func binding(
        get: @escaping (DerivativeFormulaIR) -> String,
        set: @escaping (inout DerivativeFormulaIR, String) -> Void
    ) -> Binding<String> {
        Binding {
            guard let current = model.derivativeFormula else { return get(formula) }
            return get(current)
        } set: { value in
            var next = model.derivativeFormula ?? formula
            set(&next, value)
            model.updateFormula(.derivative(next))
        }
    }
}
