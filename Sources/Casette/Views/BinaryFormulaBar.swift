import FriendlyCompiler
import SwiftUI

/// The hint lane for the two-argument number-theory commands `choose`, `gcd`,
/// and `lcm`: a kind chip plus two tokens. `choose` labels them `n`/`k`;
/// `gcd`/`lcm` label them `a`/`b`, with the second optional (the bracketed-list
/// form leaves it empty). Every edit funnels through `model.updateFormula(...)`
/// so the draft stays the single source of truth (docs/COMPLETION-UI.md).
struct BinaryFormulaBar: View {
    @Bindable var model: ShellModel
    let formula: BinaryFormulaIR

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            FormulaFunctionChip(title: formula.kind.title)

            HStack(alignment: .center, spacing: 6) {
                FormulaTokenField(
                    title: firstTitle,
                    prompt: firstPrompt,
                    text: binding(
                        get: { $0.first },
                        set: { $0.first = $1 }))

                Text(",")
                    .font(Theme.Fonts.formulaPunctuation)
                    .foregroundStyle(.tertiary)

                FormulaTokenField(
                    title: secondTitle,
                    prompt: secondPrompt,
                    text: binding(
                        get: { $0.second },
                        set: { $0.second = $1 }))
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    private var firstTitle: String { formula.kind == .choose ? "n" : "a" }
    private var secondTitle: String { formula.kind == .choose ? "k" : "b" }
    private var firstPrompt: String { formula.kind == .choose ? "10" : "12" }
    private var secondPrompt: String { formula.kind == .choose ? "3" : "optional" }

    private func binding(
        get: @escaping (BinaryFormulaIR) -> String,
        set: @escaping (inout BinaryFormulaIR, String) -> Void
    ) -> Binding<String> {
        Binding {
            guard let current = model.binaryFormula else { return get(formula) }
            return get(current)
        } set: { value in
            var next = model.binaryFormula ?? formula
            set(&next, value)
            model.updateFormula(.binary(next))
        }
    }
}
