import FriendlyCompiler
import SwiftUI

/// The hint lane for `subs`: an expression plus a single bindings token. The
/// bindings are ONE semantic group (`x=3, y=4`), not separate chips, so the
/// bar edits the substitution as a single wider token. Every edit funnels
/// through `model.updateFormula(...)` so the draft stays the single source of
/// truth (docs/COMPLETION-UI.md).
struct SubsFormulaBar: View {
    @Bindable var model: ShellModel
    let formula: SubsFormulaIR

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            FormulaFunctionChip(title: "SUBS")

            HStack(alignment: .center, spacing: 6) {
                FormulaTokenField(
                    title: "expr",
                    prompt: "x^2 + y",
                    text: binding(
                        get: { $0.expression },
                        set: { $0.expression = $1 }))

                Text(",")
                    .font(Theme.Fonts.formulaPunctuation)
                    .foregroundStyle(.tertiary)

                FormulaTokenField(
                    title: "at",
                    prompt: "x=3, y=4",
                    text: binding(
                        get: { $0.bindings },
                        set: { $0.bindings = $1 }),
                    maxWidth: 220,
                    growsWithContent: true)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    private func binding(
        get: @escaping (SubsFormulaIR) -> String,
        set: @escaping (inout SubsFormulaIR, String) -> Void
    ) -> Binding<String> {
        Binding {
            guard let current = model.subsFormula else { return get(formula) }
            return get(current)
        } set: { value in
            var next = model.subsFormula ?? formula
            set(&next, value)
            model.updateFormula(.subs(next))
        }
    }
}
