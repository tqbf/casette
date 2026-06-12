import FriendlyCompiler
import SwiftUI

struct SolveFormulaBar: View {
    @Bindable var model: ShellModel
    let formula: SolveFormulaIR

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            FormulaFunctionChip(title: "SOLVE")

            HStack(alignment: .center, spacing: 6) {
                FormulaTokenField(
                    title: "eqn",
                    prompt: "x^2 + 5*x + 6 = 0",
                    text: binding(
                        get: { $0.equation },
                        set: { $0.equation = $1 }))

                FormulaTokenField(
                    title: "for",
                    prompt: "optional",
                    text: binding(
                        get: { $0.variable },
                        set: {
                            $0.variable = $1
                            $0.hasExplicitVariable = true
                        }))
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    private func binding(
        get: @escaping (SolveFormulaIR) -> String,
        set: @escaping (inout SolveFormulaIR, String) -> Void
    ) -> Binding<String> {
        Binding {
            guard let current = model.solveFormula else { return get(formula) }
            return get(current)
        } set: { value in
            var next = model.solveFormula ?? formula
            set(&next, value)
            model.updateFormula(.solve(next))
        }
    }
}
