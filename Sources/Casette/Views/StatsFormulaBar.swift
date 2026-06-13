import FriendlyCompiler
import SwiftUI

/// The hint lane for probability distribution commands. A pinned function chip
/// is followed by one or two positional tokens and the command's named
/// parameters. Edits flow back through friendly input, keeping the draft as the
/// single source of truth.
struct StatsFormulaBar: View {
    @Bindable var model: ShellModel
    let formula: StatsFormulaIR

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            FormulaFunctionChip(title: formula.kind.title)

            ForEach(Array(formula.kind.positionalTitles.enumerated()), id: \.offset) { index, title in
                if index > 0 {
                    Text(",")
                        .font(Theme.Fonts.formulaPunctuation)
                        .foregroundStyle(.tertiary)
                }
                FormulaTokenField(
                    title: title,
                    prompt: positionalPrompt(at: index),
                    text: positionalBinding(at: index))
            }

            ForEach(formula.kind.namedFields, id: \.key) { field in
                Text(",")
                    .font(Theme.Fonts.formulaPunctuation)
                    .foregroundStyle(.tertiary)
                FormulaTokenField(
                    title: field.title,
                    prompt: field.prompt,
                    text: namedBinding(field.key),
                    maxWidth: field.key == "lambda" ? 170 : 150)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    private func positionalPrompt(at index: Int) -> String {
        let prompts = formula.kind.positionalPrompts
        guard prompts.indices.contains(index) else { return "" }
        return prompts[index]
    }

    private func positionalBinding(at index: Int) -> Binding<String> {
        Binding {
            let current = model.statsFormula ?? formula
            guard current.positional.indices.contains(index) else { return "" }
            return current.positional[index]
        } set: { value in
            var next = model.statsFormula ?? formula
            while next.positional.count <= index {
                next.positional.append("")
            }
            next.positional[index] = value
            model.updateFormula(.stats(next))
        }
    }

    private func namedBinding(_ key: String) -> Binding<String> {
        Binding {
            let current = model.statsFormula ?? formula
            return current.named[key] ?? ""
        } set: { value in
            var next = model.statsFormula ?? formula
            next.named[key] = value
            model.updateFormula(.stats(next))
        }
    }
}
