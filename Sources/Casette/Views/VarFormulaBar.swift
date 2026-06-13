import FriendlyCompiler
import SwiftUI

/// The hint lane for `var`: a single token holding the space-separated names to
/// declare. Every edit funnels through `model.updateFormula(...)` so the draft
/// stays the single source of truth (docs/COMPLETION-UI.md).
struct VarFormulaBar: View {
    @Bindable var model: ShellModel
    let formula: VarFormulaIR

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            FormulaFunctionChip(title: "VAR")

            HStack(alignment: .center, spacing: 6) {
                FormulaTokenField(
                    title: "names",
                    prompt: "a b c",
                    text: binding(
                        get: { $0.names },
                        set: { $0.names = $1 }))
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    private func binding(
        get: @escaping (VarFormulaIR) -> String,
        set: @escaping (inout VarFormulaIR, String) -> Void
    ) -> Binding<String> {
        Binding {
            guard let current = model.varFormula else { return get(formula) }
            return get(current)
        } set: { value in
            var next = model.varFormula ?? formula
            set(&next, value)
            model.updateFormula(.varDeclaration(next))
        }
    }
}
