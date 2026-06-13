import FriendlyCompiler
import SwiftUI

/// The hint lane for `assume`: a single condition token. Both grammar forms —
/// a comparison (`x > 0`) and a property (`x real`) — ride in the one token.
/// Every edit funnels through `model.updateFormula(...)` so the draft stays the
/// single source of truth (docs/COMPLETION-UI.md).
struct AssumeFormulaBar: View {
    @Bindable var model: ShellModel
    let formula: AssumeFormulaIR

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            FormulaFunctionChip(title: "ASSUME")

            HStack(alignment: .center, spacing: 6) {
                FormulaTokenField(
                    title: "condition",
                    prompt: "x > 0",
                    text: binding(
                        get: { $0.condition },
                        set: { $0.condition = $1 }),
                    maxWidth: 220)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    private func binding(
        get: @escaping (AssumeFormulaIR) -> String,
        set: @escaping (inout AssumeFormulaIR, String) -> Void
    ) -> Binding<String> {
        Binding {
            guard let current = model.assumeFormula else { return get(formula) }
            return get(current)
        } set: { value in
            var next = model.assumeFormula ?? formula
            set(&next, value)
            model.updateFormula(.assume(next))
        }
    }
}
