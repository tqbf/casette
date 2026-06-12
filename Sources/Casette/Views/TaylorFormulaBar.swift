import FriendlyCompiler
import SwiftUI

struct TaylorFormulaBar: View {
    @Bindable var model: ShellModel
    let formula: TaylorFormulaIR

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            FormulaFunctionChip(title: "TAYLOR")

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
                        set: { $0.variable = $1 }))

                Text("=")
                    .font(Theme.Fonts.formulaPunctuation)
                    .foregroundStyle(.tertiary)

                FormulaTokenField(
                    title: "around",
                    prompt: "0",
                    text: binding(
                        get: { $0.center },
                        set: { $0.center = $1 }))

                FormulaTokenField(
                    title: "order",
                    prompt: "7",
                    text: binding(
                        get: { $0.order },
                        set: { $0.order = $1 }))
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    private func binding(
        get: @escaping (TaylorFormulaIR) -> String,
        set: @escaping (inout TaylorFormulaIR, String) -> Void
    ) -> Binding<String> {
        Binding {
            guard let current = model.taylorFormula else { return get(formula) }
            return get(current)
        } set: { value in
            var next = model.taylorFormula ?? formula
            set(&next, value)
            model.updateFormula(.taylor(next))
        }
    }
}
