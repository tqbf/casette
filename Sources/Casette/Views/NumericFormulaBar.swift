import FriendlyCompiler
import SwiftUI

/// The hint lane for `numeric`: an expression plus an optional digit count.
/// Every edit funnels through `model.updateFormula(...)` so the draft stays
/// the single source of truth (docs/COMPLETION-UI.md).
struct NumericFormulaBar: View {
    @Bindable var model: ShellModel
    let formula: NumericFormulaIR

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            FormulaFunctionChip(title: "NUMERIC")

            HStack(alignment: .center, spacing: 6) {
                FormulaTokenField(
                    title: "expr",
                    prompt: "pi",
                    text: binding(
                        get: { $0.expression },
                        set: { $0.expression = $1 }))

                Text(",")
                    .font(Theme.Fonts.formulaPunctuation)
                    .foregroundStyle(.tertiary)

                FormulaTokenField(
                    title: "digits",
                    prompt: "optional",
                    text: binding(
                        get: { $0.digits },
                        set: { $0.digits = $1 }))
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    private func binding(
        get: @escaping (NumericFormulaIR) -> String,
        set: @escaping (inout NumericFormulaIR, String) -> Void
    ) -> Binding<String> {
        Binding {
            guard let current = model.numericFormula else { return get(formula) }
            return get(current)
        } set: { value in
            var next = model.numericFormula ?? formula
            set(&next, value)
            model.updateFormula(.numeric(next))
        }
    }
}
