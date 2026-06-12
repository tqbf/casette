import FriendlyCompiler
import SwiftUI

struct UnaryFormulaBar: View {
    @Bindable var model: ShellModel
    let formula: UnaryFormulaIR

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            FormulaFunctionChip(title: formula.keyword.title)

            HStack(alignment: .center, spacing: 6) {
                FormulaTokenField(
                    title: "expr",
                    prompt: expressionPrompt,
                    text: binding(
                        get: { $0.expression },
                        set: { $0.expression = $1 }))
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    private var expressionPrompt: String {
        switch formula.keyword {
        case .expand: return "(x+1)^3"
        case .factor: return "x^2 - 1"
        case .simplify: return "sin(x)^2 + cos(x)^2"
        }
    }

    private func binding(
        get: @escaping (UnaryFormulaIR) -> String,
        set: @escaping (inout UnaryFormulaIR, String) -> Void
    ) -> Binding<String> {
        Binding {
            guard let current = model.unaryFormula else { return get(formula) }
            return get(current)
        } set: { value in
            var next = model.unaryFormula ?? formula
            set(&next, value)
            model.updateFormula(.unary(next))
        }
    }
}
