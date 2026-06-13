import FriendlyCompiler
import SwiftUI

/// The hint lane for the vector-calculus family: `gradient`, `hessian`, and
/// `jacobian`. The pinned chip names the kind; the tokens differ per kind —
/// `gradient` takes an expression and an optional variable list, `hessian`
/// just an expression, `jacobian` a functions list and a variable list. Like
/// the other bars, every edit funnels through `model.updateFormula(...)` so
/// the draft stays the single source of truth (docs/COMPLETION-UI.md).
struct VectorCalculusFormulaBar: View {
    @Bindable var model: ShellModel
    let formula: VectorCalculusFormulaIR

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            FormulaFunctionChip(title: formula.kind.title)

            HStack(alignment: .center, spacing: 6) {
                FormulaTokenField(
                    title: expressionTitle,
                    prompt: expressionPrompt,
                    text: binding(
                        get: { $0.expression },
                        set: { $0.expression = $1 }))

                if formula.kind != .hessian {
                    Text(",")
                        .font(Theme.Fonts.formulaPunctuation)
                        .foregroundStyle(.tertiary)

                    FormulaTokenField(
                        title: "vars",
                        prompt: variablesPrompt,
                        text: binding(
                            get: { $0.variables },
                            set: { $0.variables = $1 }))
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    /// `jacobian` operates on a list of functions, so its leading token names
    /// the functions; `gradient`/`hessian` take a single expression.
    private var expressionTitle: String {
        formula.kind == .jacobian ? "fns" : "expr"
    }

    private var expressionPrompt: String {
        formula.kind == .jacobian ? "[x^2+y, sin(x*y)]" : "x^2 + y^2"
    }

    private var variablesPrompt: String {
        formula.kind == .jacobian ? "[x,y]" : "optional [x,y]"
    }

    private func binding(
        get: @escaping (VectorCalculusFormulaIR) -> String,
        set: @escaping (inout VectorCalculusFormulaIR, String) -> Void
    ) -> Binding<String> {
        Binding {
            guard let current = model.vectorCalculusFormula else { return get(formula) }
            return get(current)
        } set: { value in
            var next = model.vectorCalculusFormula ?? formula
            set(&next, value)
            model.updateFormula(.vectorCalculus(next))
        }
    }
}
