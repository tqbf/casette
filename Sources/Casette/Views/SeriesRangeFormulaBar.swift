import FriendlyCompiler
import SwiftUI

struct SeriesRangeFormulaBar: View {
    @Bindable var model: ShellModel
    let formula: SeriesRangeFormulaIR

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            FormulaFunctionChip(title: formula.kind.title)

            HStack(alignment: .center, spacing: 6) {
                FormulaTokenField(
                    title: "expr",
                    prompt: "k^2",
                    text: binding(
                        get: { $0.expression },
                        set: { $0.expression = $1 }))

                FormulaTokenField(
                    title: "index",
                    prompt: "k",
                    text: binding(
                        get: { $0.indexVariable },
                        set: { $0.indexVariable = $1 }))

                Text(",")
                    .font(Theme.Fonts.formulaPunctuation)
                    .foregroundStyle(.tertiary)

                FormulaTokenField(
                    title: "lower",
                    prompt: "1",
                    text: binding(
                        get: { $0.lowerBound },
                        set: {
                            $0.lowerBound = $1
                            if !$1.isEmpty, $0.indexVariable.isEmpty { $0.indexVariable = "k" }
                        }))

                Text("..")
                    .font(Theme.Fonts.formulaPunctuation)
                    .foregroundStyle(.tertiary)

                FormulaTokenField(
                    title: "upper",
                    prompt: "n",
                    text: binding(
                        get: { $0.upperBound },
                        set: {
                            $0.upperBound = $1
                            if !$1.isEmpty, $0.indexVariable.isEmpty { $0.indexVariable = "k" }
                        }))
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    private func binding(
        get: @escaping (SeriesRangeFormulaIR) -> String,
        set: @escaping (inout SeriesRangeFormulaIR, String) -> Void
    ) -> Binding<String> {
        Binding {
            guard let current = model.seriesRangeFormula else { return get(formula) }
            return get(current)
        } set: { value in
            var next = model.seriesRangeFormula ?? formula
            set(&next, value)
            model.updateFormula(.seriesRange(next))
        }
    }
}
